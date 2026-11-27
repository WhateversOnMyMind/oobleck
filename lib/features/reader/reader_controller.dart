import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../core/log.dart';
import '../../core/manga/image_header.dart';
import '../../core/manga/manga_models.dart';
import '../../core/manga/page_cache.dart';
import '../../core/sources/manga_source.dart';
import '../../core/storage/app_db.dart';
import '../../core/storage/manga_records.dart';
import '../manga/manga_logic.dart';
import 'reader_settings.dart';

/// One image of a chapter: a downloaded file or a page on the site.
class ReaderPageRef {
  const ReaderPageRef.file(this.index, String path)
      : file = path,
        remote = null;
  const ReaderPageRef.remote(this.index, MangaPage page)
      : remote = page,
        file = null;

  final int index;
  final String? file;
  final MangaPage? remote;

  String get id => file ?? remote!.url;
}

/// Something the menu or keyboard asks the active view to do.
sealed class ReaderCommand {
  const ReaderCommand();
}

/// Go to page [page] of the current chapter.
class JumpTo extends ReaderCommand {
  const JumpTo(this.page);
  final int page;
}

/// Next (+1) or previous (-1) page or screen.
class PageStep extends ReaderCommand {
  const PageStep(this.direction);
  final int direction;
}

/// A chapter the reader has loaded (or is loading).
class ReaderChapter {
  ReaderChapter(this.chapter);
  final ChapterRecord chapter;
  List<ReaderPageRef> pages = const [];
  Object? error;
  bool loading = true;
}

/// State of an open reader: which chapters are loaded, where the reader is,
/// and saving progress as pages go by.
class ReaderController extends ChangeNotifier {
  ReaderController({
    required this.db,
    required this.source,
    required this.cache,
    required this.mangaKey,
    required this.settings,
  });

  final AppDb db;
  final MangaSource? source;
  final PageCache cache;
  final String mangaKey;
  final ReaderSettings Function() settings;

  late MangaRecord manga;
  List<ChapterRecord> chapters = const [];

  /// Loaded chapters in reading order. Paged modes keep one; the long-strip
  /// reader appends the next chapter as the reader nears the end.
  final segments = <ReaderChapter>[];
  int segment = 0;
  int page = 0;
  double offset = 0;
  bool menuVisible = false;
  ReaderMode mode = ReaderMode.auto;

  /// Bumped when the reader jumps to another chapter, so views reset.
  int generation = 0;

  bool _disposed = false;
  Timer? _saveTimer;

  final _commands = StreamController<ReaderCommand>.broadcast();
  Stream<ReaderCommand> get commands => _commands.stream;
  void command(ReaderCommand c) => _commands.add(c);

  /// Real page sizes seen this session, so rebuilt items keep their height.
  final aspects = <String, double>{};

  ReaderChapter? get current => segments.isEmpty ? null : segments[segment.clamp(0, segments.length - 1)];
  ChapterRecord? get previousChapter => current == null ? null : neighbours(chapters, current!.chapter.id).$1;
  ChapterRecord? get nextChapter => current == null ? null : neighbours(chapters, current!.chapter.id).$2;

  Map<String, String> get imageHeaders => source?.imageHeaders ?? const {};

  /// Longest wait on the first page when picking the layout automatically.
  static const decideTimeout = Duration(seconds: 6);

  /// Opens [chapterId]; resumes where it was left unless it was finished.
  Future<void> open(String chapterId, {bool fromStart = false}) async {
    manga = db.manga(mangaKey)!;
    chapters = db.chapters(mangaKey);
    final rec = chapters.where((c) => c.id == chapterId).firstOrNull;
    if (rec == null) throw StateError('chapter $chapterId not found');
    final st = db.chapterState(mangaKey, chapterId);
    final resume = !fromStart && (st?.started ?? false);
    segments
      ..clear()
      ..add(ReaderChapter(rec));
    segment = 0;
    page = resume ? st!.page : 0;
    offset = resume ? st!.offset : 0;
    generation++;
    notifyListeners();
    await _load(segments.first, notify: false);
    if (_disposed) return;
    mode = await _decideMode(segments.first);
    if (_disposed) return;
    if (page >= segments.first.pages.length) page = 0;
    notifyListeners();
    _scheduleSave();
  }

  Future<void> _load(ReaderChapter rc, {bool notify = true}) async {
    rc.loading = true;
    rc.error = null;
    notifyListeners();
    try {
      final dl = db.mangaDownload(ChapterState.keyOf(mangaKey, rc.chapter.id));
      final files = dl?.isDone == true ? dl!.files : const <String>[];
      // Read offline only when every saved page is still there.
      final present = await Future.wait([for (final f in files) File(f).exists()]);
      if (files.isNotEmpty && !present.contains(false)) {
        rc.pages = [for (var i = 0; i < files.length; i++) ReaderPageRef.file(i, files[i])];
      } else {
        final src = source;
        if (src == null) throw StateError('source unavailable');
        final pages = await src.pages(rc.chapter.toInfo(manga.mangaId));
        rc.pages = [for (final p in pages) ReaderPageRef.remote(p.index, p)];
      }
    } catch (e) {
      Log.d('reader', 'load ${rc.chapter.id}: $e');
      rc.error = e;
    }
    rc.loading = false;
    if (notify && !_disposed) notifyListeners();
  }

  Future<void> retry() async {
    final rc = current;
    if (rc != null) await _load(rc);
  }

  /// Picks the layout: the series' own choice, then the app default; "auto"
  /// looks at the first page (tall strips scroll, book pages turn).
  Future<ReaderMode> _decideMode(ReaderChapter rc) async {
    final own = ReaderMode.parse(manga.readerMode, ReaderMode.auto);
    final chosen = own != ReaderMode.auto ? own : settings().mode;
    if (chosen != ReaderMode.auto) return chosen;
    if (rc.pages.isEmpty) return ReaderMode.webtoon;
    // Don't hold the whole reader on one slow image: the page keeps loading
    // on its own and shows its own progress or error.
    Future<ReaderMode> look() async {
      final size = await imageSize(await bytesOf(rc.pages.first));
      return autoModeFor(size.width, size.height);
    }

    try {
      return await look().timeout(decideTimeout);
    } catch (e) {
      Log.d('reader', 'auto layout: $e');
      return ReaderMode.webtoon;
    }
  }

  /// Switches the layout and remembers it for this series.
  Future<void> setMode(ReaderMode m) async {
    await db.putManga(db.manga(mangaKey)!.copyWith(readerMode: m == ReaderMode.auto ? null : m.name));
    manga = db.manga(mangaKey)!;
    if (current == null) return;
    final next = m == ReaderMode.auto ? await _decideMode(current!) : m;
    if (_disposed) return;
    // Keep only the current chapter when switching layouts.
    final keep = current!;
    segments
      ..clear()
      ..add(keep);
    segment = 0;
    mode = next;
    generation++;
    notifyListeners();
  }

  /// Bytes of a page. Only real images come back (downloads, the cache and
  /// saved chapters are all checked), so the decoder never sees an error page.
  Future<Uint8List> bytesOf(ReaderPageRef p) {
    if (p.file != null) {
      return File(p.file!).readAsBytes().then((b) {
        if (sniffImage(b) == null) throw FormatException('not an image (${describeNonImage(b)})');
        return b;
      });
    }
    return cache.bytes(p.remote!, headers: imageHeaders);
  }

  /// Warms the cache for the pages after [index] in the current chapter.
  void preloadAfter(int index) {
    final rc = current;
    if (rc == null) return;
    final n = settings().preload;
    for (var i = index + 1; i <= index + n && i < rc.pages.length; i++) {
      final p = rc.pages[i];
      if (p.remote != null) unawaited(cache.bytes(p.remote!, headers: imageHeaders).then((_) {}, onError: (_) {}));
    }
  }

  // ---- position ------------------------------------------------------------------
  /// Called by the views as the reader moves. [finished] once the last page
  /// has been fully seen.
  void onPosition(int seg, int pageIndex, double pageOffset, {bool finished = false}) {
    if (seg < 0 || seg >= segments.length) return;
    final changedChapter = seg != segment;
    if (changedChapter) {
      // Moving into the next chapter means the previous one was read.
      if (seg > segment) _saveNow(segment: segment, finished: true);
      segment = seg;
    }
    final changed = changedChapter || pageIndex != page;
    page = pageIndex;
    offset = pageOffset;
    if (finished) {
      _saveNow(finished: true);
    } else {
      _scheduleSave();
    }
    if (changed) {
      preloadAfter(pageIndex);
      notifyListeners();
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () => _saveNow());
  }

  void _saveNow({int? segment, bool finished = false}) {
    final index = segment ?? this.segment;
    final s = segments.elementAtOrNull(index);
    if (s == null || s.pages.isEmpty) return;
    final isCurrent = index == this.segment;
    unawaited(db.saveReading(
      mangaKey,
      s.chapter.id,
      page: isCurrent ? page.clamp(0, s.pages.length - 1) : s.pages.length - 1,
      pageCount: s.pages.length,
      offset: isCurrent ? offset : 1,
      finished: finished,
      incognito: settings().incognito,
    ));
  }

  /// Saves now (leaving the reader).
  void flush() {
    _saveTimer?.cancel();
    _saveNow();
  }

  // ---- chapters --------------------------------------------------------------------
  bool _appending = false;

  /// Long-strip mode: loads the next chapter below the current ones.
  Future<void> appendNext() async {
    if (_appending || segments.isEmpty) return;
    final last = segments.last;
    final next = neighbours(chapters, last.chapter.id).$2;
    if (next == null || segments.any((s) => s.chapter.id == next.id)) return;
    _appending = true;
    final rc = ReaderChapter(next);
    segments.add(rc);
    notifyListeners();
    await _load(rc);
    _appending = false;
  }

  /// Jumps to another chapter (from the menu or the end of a paged chapter).
  Future<void> goTo(ChapterRecord c) async {
    flush();
    await open(c.id, fromStart: true);
  }

  void toggleMenu([bool? show]) {
    menuVisible = show ?? !menuVisible;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    flush();
    unawaited(_commands.close());
    super.dispose();
  }
}

/// Tall strips (height more than ~2.2x the width) read best as a webtoon.
ReaderMode autoModeFor(int width, int height) =>
    width > 0 && height / width > 2.2 ? ReaderMode.webtoon : ReaderMode.rtl;

/// Image dimensions without decoding the pixels.
Future<({int width, int height})> imageSize(Uint8List bytes) async {
  // The header is enough for the common formats and needs no decoder.
  final quick = headerSize(bytes);
  if (quick != null) return quick;
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final desc = await ui.ImageDescriptor.encoded(buffer);
  final r = (width: desc.width, height: desc.height);
  desc.dispose();
  buffer.dispose();
  return r;
}
