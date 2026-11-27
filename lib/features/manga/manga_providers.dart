import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/providers.dart';
import '../../core/log.dart';
import '../../core/manga/manga_downloader.dart';
import '../../core/manga/manga_models.dart';
import '../../core/manga/page_cache.dart';
import '../../core/sources/manga_source.dart';
import '../../core/sources/toon11/toon11_address.dart';
import '../../core/sources/toon11/toon11_source.dart';
import '../../core/storage/app_db.dart';
import '../../core/storage/manga_records.dart';
import 'manga_logic.dart';
import 'manga_sources.dart';

/// Settings key for the 11toon address (the site moves domains now and then).
const mangaBaseUrlKey = 'manga.toon11BaseUrl';

/// The site address set in Settings, null for the built-in default.
class MangaBaseUrl extends Notifier<String?> {
  @override
  String? build() => ref.watch(dbProvider).setting<String>(mangaBaseUrlKey);

  Future<void> set(String? url) async {
    var u = url?.trim() ?? '';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    // Bare IP addresses (how 11toon is often reachable) are plain http.
    if (u.isNotEmpty && !u.contains('://')) u = RegExp(r'^\d+\.\d+\.\d+\.\d+(:\d+)?$').hasMatch(u) ? 'http://$u' : 'https://$u';
    await ref.read(dbProvider).setSetting(mangaBaseUrlKey, u.isEmpty ? null : u);
    state = u.isEmpty ? null : u;
  }
}

final mangaBaseUrlProvider = NotifierProvider<MangaBaseUrl, String?>(MangaBaseUrl.new);

/// Settings key for the address found automatically (see [MangaSiteFinder]).
const mangaFoundUrlKey = 'manga.toon11Found';

/// The last address that was found to work when the default did not.
class MangaFoundUrl extends Notifier<String?> {
  @override
  String? build() => ref.watch(dbProvider).setting<String>(mangaFoundUrlKey);

  Future<void> set(String? url) async {
    await ref.read(dbProvider).setSetting(mangaFoundUrlKey, url);
    state = url;
  }
}

final mangaFoundUrlProvider = NotifierProvider<MangaFoundUrl, String?>(MangaFoundUrl.new);

/// The address in use: typed in Settings, else found automatically, else the default.
final mangaSiteAddressProvider = Provider<String>(
    (ref) => ref.watch(mangaBaseUrlProvider) ?? ref.watch(mangaFoundUrlProvider) ?? Toon11Source.defaultBaseUrl);

/// Looks up the site's current address when loading fails (the site moves
/// and some networks block its domains). Never runs over an address typed
/// in Settings unless asked from there.
class MangaSiteFinder {
  MangaSiteFinder(this.ref);
  final Ref ref;
  Future<String?>? _running;
  DateTime? _lastAuto;

  /// Finds a working address and switches to it. Returns the new address, or
  /// null when nothing changed. Automatic calls run at most once a minute.
  Future<String?> recover({bool fromSettings = false}) async {
    if (!fromSettings) {
      if (ref.read(mangaBaseUrlProvider) != null) return null;
      final now = DateTime.now();
      if (_lastAuto != null && now.difference(_lastAuto!) < const Duration(minutes: 1)) return null;
      _lastAuto = now;
    }
    return _running ??= _find(fromSettings).whenComplete(() => _running = null);
  }

  Future<String?> _find(bool fromSettings) async {
    final current = ref.read(mangaSiteAddressProvider);
    final finder = Toon11AddressFinder(ref.read(dioProvider));
    // Settings asks for the newest address, so the public page comes first.
    final found = await finder.find(tryFirst: fromSettings ? const [] : [Toon11Source.defaultBaseUrl]);
    Log.d('manga', 'site address: $current -> ${found ?? 'none found'}');
    if (found == null || found == current) return null;
    if (fromSettings) await ref.read(mangaBaseUrlProvider.notifier).set(null);
    await ref.read(mangaFoundUrlProvider.notifier).set(found == Toon11Source.defaultBaseUrl ? null : found);
    return found;
  }
}

final mangaSiteFinderProvider = Provider<MangaSiteFinder>(MangaSiteFinder.new);

/// The manga site. One for now; storage keys carry the source id so more
/// can be added later.
final mangaSourceProvider = Provider<MangaSource>((ref) {
  return buildMangaSource(ref.watch(dioProvider), baseUrl: ref.watch(mangaSiteAddressProvider));
});

MangaSource? mangaSourceFor(Ref ref, String sourceId) {
  final s = ref.read(mangaSourceProvider);
  return s.id == sourceId ? s : null;
}

final pageCacheProvider = Provider<PageCache>((ref) {
  return PageCache(dio: ref.watch(dioProvider), dir: p.join(ref.watch(supportDirProvider), 'manga_cache'));
});

final mangaDownloaderProvider = Provider<MangaDownloader>((ref) {
  final d = MangaDownloader(
    db: ref.watch(dbProvider),
    dio: ref.watch(dioProvider),
    sourceFor: (id) => mangaSourceFor(ref, id),
    fetcher: ref.watch(pageCacheProvider).fetcher,
    customRoot: () => ref.read(settingsProvider).downloadDir,
  );
  unawaited(d.restore());
  return d;
});

// ---- raw streams ------------------------------------------------------------------
final mangaRecordsProvider = StreamProvider<List<MangaRecord>>((ref) => ref.watch(dbProvider).watchManga());
final chapterStateTickProvider = StreamProvider<int>((ref) => ref.watch(dbProvider).watchChapterStates());
final chapterListTickProvider = StreamProvider<int>((ref) => ref.watch(dbProvider).watchChapterLists());
final mangaDownloadsProvider =
    StreamProvider<List<MangaDownloadRecord>>((ref) => ref.watch(dbProvider).watchMangaDownloads());
final mangaUpdatesProvider = StreamProvider<List<MangaUpdate>>((ref) => ref.watch(dbProvider).watchMangaUpdates());

// ---- per series -------------------------------------------------------------------
final mangaRecordProvider = Provider.family<MangaRecord?, String>((ref, key) {
  ref.watch(mangaRecordsProvider);
  return ref.read(dbProvider).manga(key);
});

final chaptersProvider = Provider.family<List<ChapterRecord>, String>((ref, key) {
  ref.watch(chapterListTickProvider);
  return ref.read(dbProvider).chapters(key);
});

final chapterStatesProvider = Provider.family<Map<String, ChapterState>, String>((ref, key) {
  ref.watch(chapterStateTickProvider);
  return ref.read(dbProvider).chapterStates(key);
});

/// Done downloads of a series, by chapter id.
final seriesDownloadsProvider = Provider.family<Map<String, MangaDownloadRecord>, String>((ref, key) {
  final all = ref.watch(mangaDownloadsProvider).value ?? const [];
  return {for (final d in all) if (d.mangaKey == key) d.chapterId: d};
});

/// Fetches series detail and chapters from the site, saves them, and
/// returns the stored record. Offline, it falls back to what was saved.
final mangaRefreshProvider = FutureProvider.family<MangaRecord, String>((ref, key) async {
  final db = ref.read(dbProvider);
  final existing = db.manga(key);
  final sourceId = key.split(':').first;
  final mangaId = key.substring(sourceId.length + 1);
  final source = mangaSourceFor(ref, sourceId);
  if (source == null) {
    if (existing != null) return existing;
    throw StateError('unknown source $sourceId');
  }
  try {
    try {
      return (await refreshSeries(db, source, mangaId, cacheCover: (m) => cacheMangaCover(ref, m))).$1;
    } catch (_) {
      // The site may have moved: look up its address once, then try again there.
      if (await ref.read(mangaSiteFinderProvider).recover() == null) rethrow;
      final moved = mangaSourceFor(ref, sourceId) ?? source;
      return (await refreshSeries(db, moved, mangaId, cacheCover: (m) => cacheMangaCover(ref, m))).$1;
    }
  } catch (e) {
    if (existing != null && db.chapters(key).isNotEmpty) {
      Log.d('manga', 'refresh $key failed, using saved copy: $e');
      throw OfflineCopy(existing, e);
    }
    rethrow;
  }
});

/// Thrown by [mangaRefreshProvider] when the site failed but a saved copy exists.
class OfflineCopy implements Exception {
  OfflineCopy(this.record, this.cause);
  final MangaRecord record;
  final Object cause;
  @override
  String toString() => 'offline: $cause';
}

/// Downloads a series and merges it into storage. Returns the new record and
/// how many chapters are new (0 on the first fetch of a series).
Future<(MangaRecord, int)> refreshSeries(
  AppDb db,
  MangaSource source,
  String mangaId, {
  Future<void> Function(MangaRecord)? cacheCover,
  int? now,
}) async {
  final bundle = await source.fetch(mangaId);
  final key = mangaKeyOf(source.id, mangaId);
  final rec = MangaRecord.fromDetail(source.id, bundle.detail, existing: db.manga(key));
  await db.putManga(rec);
  final fresh = await db.mergeChapters(key, bundle.chapters, now: now);
  if (cacheCover != null) unawaited(cacheCover(rec));
  return (db.manga(key)!, fresh.length);
}

/// Keeps the cover on disk so the library looks right offline.
Future<void> cacheMangaCover(Ref ref, MangaRecord m) async {
  final url = m.cover;
  if (url == null) return;
  final db = ref.read(dbProvider);
  if (m.coverPath != null && File(m.coverPath!).existsSync()) return;
  try {
    final dir = Directory(p.join(ref.read(supportDirProvider), 'manga_covers'))..createSync(recursive: true);
    final ext = p.extension(Uri.parse(url).path);
    final path = p.join(dir.path, '${m.sourceId}_${m.mangaId}${ext.isEmpty ? '.jpg' : ext}');
    final source = mangaSourceFor(ref, m.sourceId);
    await ref.read(dioProvider).download(url, path, options: Options(headers: source?.imageHeaders));
    final cur = db.manga(m.key);
    if (cur != null) await db.putManga(cur.copyWith(coverPath: path));
  } catch (e) {
    Log.d('manga', 'cover ${m.key}: $e');
  }
}

/// Saves a card the user tapped so the detail screen can draw at once.
Future<String> rememberSummary(AppDb db, MangaSource source, MangaSummary s) async {
  final key = mangaKeyOf(source.id, s.id);
  if (db.manga(key) == null) await db.putManga(MangaRecord.fromSummary(source.id, s));
  return key;
}

// ---- library ---------------------------------------------------------------------------
/// Chapter lists of the library series. Separate from [libraryEntriesProvider]
/// so saving the reading position does not decode every list again.
final _libraryChaptersProvider = Provider<Map<String, List<ChapterRecord>>>((ref) {
  ref.watch(chapterListTickProvider);
  final records = ref.watch(mangaRecordsProvider).value ?? const [];
  final db = ref.read(dbProvider);
  return {for (final m in records.where((m) => m.inLibrary)) m.key: db.chapters(m.key)};
});

final libraryEntriesProvider = Provider<List<LibraryEntry>>((ref) {
  ref.watch(chapterStateTickProvider);
  final chapters = ref.watch(_libraryChaptersProvider);
  final records = ref.watch(mangaRecordsProvider).value ?? const [];
  final downloads = ref.watch(mangaDownloadsProvider).value ?? const [];
  final db = ref.read(dbProvider);
  final done = <String, Set<String>>{};
  for (final d in downloads.where((d) => d.isDone)) {
    done.putIfAbsent(d.mangaKey, () => {}).add(d.chapterId);
  }
  // One pass over all reading states (this reruns on every page the reader saves).
  final states = <String, Map<String, ChapterState>>{};
  for (final s in db.allChapterStates()) {
    states.putIfAbsent(s.mangaKey, () => {})[s.chapterId] = s;
  }
  return [
    for (final m in records.where((m) => m.inLibrary))
      libraryEntryFor(m, chapters[m.key] ?? db.chapters(m.key), states[m.key] ?? const {}, done[m.key] ?? const {}),
  ];
});

/// Progress of "check for new chapters".
class LibraryRefreshState {
  const LibraryRefreshState({this.running = false, this.done = 0, this.total = 0, this.found = 0, this.failed = 0});
  final bool running;
  final int done;
  final int total;
  final int found;
  final int failed;
}

class LibraryRefresher extends Notifier<LibraryRefreshState> {
  @override
  LibraryRefreshState build() => const LibraryRefreshState();

  /// Refreshes every library series (3 at a time). Returns new chapters found.
  Future<int> refreshAll({Iterable<String>? keys}) async {
    if (state.running) return 0;
    final db = ref.read(dbProvider);
    final targets = (keys?.map(db.manga).whereType<MangaRecord>() ?? db.libraryManga()).toList();
    if (targets.isEmpty) return 0;
    var done = 0, found = 0, failed = 0;
    state = LibraryRefreshState(running: true, total: targets.length);
    var next = 0;
    Future<void> worker() async {
      while (next < targets.length) {
        final m = targets[next++];
        final source = mangaSourceFor(ref, m.sourceId);
        try {
          if (source == null) throw StateError('no source');
          found += (await refreshSeries(db, source, m.mangaId, cacheCover: (r) => cacheMangaCover(ref, r))).$2;
        } catch (e) {
          failed++;
          Log.d('manga', 'update ${m.key}: $e');
        }
        done++;
        state = LibraryRefreshState(running: true, done: done, total: targets.length, found: found, failed: failed);
      }
    }

    await Future.wait([for (var i = 0; i < 3; i++) worker()]);
    state = LibraryRefreshState(done: done, total: targets.length, found: found, failed: failed);
    return found;
  }
}

final libraryRefresherProvider = NotifierProvider<LibraryRefresher, LibraryRefreshState>(LibraryRefresher.new);

// ---- history -------------------------------------------------------------------------------
final mangaHistoryProvider = Provider<List<(MangaRecord, ChapterState)>>((ref) {
  ref.watch(chapterStateTickProvider);
  ref.watch(mangaRecordsProvider);
  return ref.read(dbProvider).mangaHistory();
});

// ---- browsing ------------------------------------------------------------------------------
/// What a paged list shows (a catalog or a search).
class ListingQuery {
  const ListingQuery({this.catalog, this.query, this.genres = const {}});
  final String? catalog;
  final String? query;
  final Set<String> genres;

  @override
  bool operator ==(Object other) =>
      other is ListingQuery &&
      other.catalog == catalog &&
      other.query == query &&
      other.genres.length == genres.length &&
      other.genres.containsAll(genres);

  @override
  int get hashCode => Object.hash(catalog, query, Object.hashAllUnordered(genres));
}

class ListingState {
  const ListingState({this.items = const [], this.page = 0, this.hasNext = true, this.loading = false, this.error});
  final List<MangaSummary> items;
  final int page;
  final bool hasNext;
  final bool loading;
  final Object? error;

  ListingState copyWith({List<MangaSummary>? items, int? page, bool? hasNext, bool? loading, Object? error, bool clearError = false}) =>
      ListingState(
        items: items ?? this.items,
        page: page ?? this.page,
        hasNext: hasNext ?? this.hasNext,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

class ListingNotifier extends Notifier<ListingState> {
  ListingNotifier(this.query);
  final ListingQuery query;

  @override
  ListingState build() {
    // A new site address rebuilds the listing.
    ref.watch(mangaSourceProvider);
    _request++;
    Future.microtask(loadMore);
    return const ListingState(loading: true);
  }

  /// Bumped by [reload]; an answer for an older request is dropped.
  int _request = 0;

  Future<void> loadMore() async {
    if ((state.loading && state.page > 0) || !state.hasNext) return;
    if (state.loading && state.items.isNotEmpty) return;
    state = state.copyWith(loading: true, clearError: true);
    final source = ref.read(mangaSourceProvider);
    final page = state.page + 1;
    final request = _request;
    try {
      final q = query.query;
      final r = q != null
          ? await source.search(q, page: page)
          : await source.browse(query.catalog ?? source.catalogs.first.id, page: page, genres: query.genres);
      if (request != _request) return;
      final seen = {for (final m in state.items) m.id};
      state = state.copyWith(
        items: [...state.items, ...r.items.where((m) => seen.add(m.id))],
        page: page,
        hasNext: r.hasNext && r.items.isNotEmpty,
        loading: false,
      );
    } catch (e) {
      if (request != _request) return;
      // First page failed: the site may have moved. A new address rebuilds
      // this listing (see build), so there is nothing more to do here.
      if (page == 1 && await ref.read(mangaSiteFinderProvider).recover() != null) return;
      if (request != _request) return;
      state = state.copyWith(loading: false, error: e);
    }
  }

  Future<void> reload() async {
    _request++;
    state = const ListingState(loading: true);
    await loadMore();
  }
}

final listingProvider =
    NotifierProvider.family<ListingNotifier, ListingState, ListingQuery>(ListingNotifier.new);
