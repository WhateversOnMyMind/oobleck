import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../downloads/download_manager.dart';
import '../http.dart';
import '../log.dart';
import '../sources/manga_source.dart';
import '../storage/app_db.dart';
import '../storage/manga_records.dart';
import 'manga_models.dart';

/// Saves chapters for offline reading, one chapter at a time, a few pages in
/// parallel. Files go to `<root>/<series>/<chapter>/001.jpg`, so they are
/// also readable in any image viewer.
class MangaDownloader {
  MangaDownloader({
    required this.db,
    required this.dio,
    required this.sourceFor,
    this.rootOverride,
    this.customRoot,
    this.pageConcurrency = 3,
  });

  final AppDb db;
  final Dio dio;
  final MangaSource? Function(String sourceId) sourceFor;
  final String? rootOverride;

  /// The user's download folder from Settings (manga go into `Manga/` there).
  final String? Function()? customRoot;
  final int pageConcurrency;

  bool _running = false;
  CancelToken? _cancel;
  String? _activeKey;

  /// Queues [chapters] of [manga] (already downloaded or queued ones are skipped).
  Future<int> enqueue(MangaRecord manga, List<ChapterInfo> chapters, {int? now}) async {
    var at = now ?? DateTime.now().millisecondsSinceEpoch;
    var added = 0;
    for (final c in chapters) {
      final key = ChapterState.keyOf(manga.key, c.id);
      final cur = db.mangaDownload(key);
      if (cur != null && cur.status != MangaDownloadStatus.failed) continue;
      await db.putMangaDownload(MangaDownloadRecord(
        mangaKey: manga.key,
        chapterId: c.id,
        chapterTitle: c.title,
        number: c.number,
        createdAt: at++,
      ));
      added++;
    }
    unawaited(run());
    return added;
  }

  /// Works through the queue until it is empty. Safe to call repeatedly.
  Future<void> run() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final next = db.allMangaDownloads().where((d) => d.status == MangaDownloadStatus.queued).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        if (next.isEmpty) break;
        await _download(next.first);
      }
    } finally {
      _running = false;
    }
  }

  /// Resumes downloads that were running when the app closed.
  Future<void> restore() async {
    for (final d in db.allMangaDownloads().where((d) => d.status == MangaDownloadStatus.running)) {
      await db.putMangaDownload(d.copyWith(status: MangaDownloadStatus.queued));
    }
    unawaited(run());
  }

  Future<void> pause(String key) async {
    final d = db.mangaDownload(key);
    if (d == null || d.isDone) return;
    if (_activeKey == key) _cancel?.cancel();
    await db.putMangaDownload(d.copyWith(status: MangaDownloadStatus.paused));
  }

  Future<void> resume(String key) async {
    final d = db.mangaDownload(key);
    if (d == null || d.isDone) return;
    await db.putMangaDownload(d.copyWith(status: MangaDownloadStatus.queued, error: null));
    unawaited(run());
  }

  Future<void> delete(String key) async {
    final d = db.mangaDownload(key);
    if (d == null) return;
    if (_activeKey == key) _cancel?.cancel();
    await db.deleteMangaDownload(key);
    if (d.dir.isNotEmpty) {
      try {
        final dir = Directory(d.dir);
        if (dir.existsSync()) await dir.delete(recursive: true);
        // Remove the series folder once it is empty.
        final parent = dir.parent;
        if (parent.existsSync() && parent.listSync().isEmpty) await parent.delete();
      } catch (e) {
        Log.d('manga-dl', 'delete ${d.dir}: $e');
      }
    }
  }

  Future<String> root() async {
    if (rootOverride != null) return rootOverride!;
    final custom = customRoot?.call();
    if (custom != null && custom.isNotEmpty) return p.join(custom, 'Manga');
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'];
      if (home != null) return p.join(home, 'Pictures', 'Oobleck Manga');
    }
    if (Platform.isAndroid) {
      final dirs = await getExternalStorageDirectories(type: StorageDirectory.pictures);
      if (dirs != null && dirs.isNotEmpty) return p.join(dirs.first.path, 'Oobleck Manga');
    }
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'Oobleck Manga');
  }

  Future<void> _download(MangaDownloadRecord d) async {
    final manga = db.manga(d.mangaKey);
    final source = manga == null ? null : sourceFor(manga.sourceId);
    if (manga == null || source == null) {
      await db.putMangaDownload(d.copyWith(status: MangaDownloadStatus.failed, error: 'unknown series'));
      return;
    }
    final cancel = _cancel = CancelToken();
    _activeKey = d.key;
    var rec = d.copyWith(status: MangaDownloadStatus.running, error: null);
    await db.putMangaDownload(rec);
    try {
      final chapter = db.chapters(manga.key).where((c) => c.id == d.chapterId).firstOrNull?.toInfo(manga.mangaId) ??
          ChapterInfo(id: d.chapterId, mangaId: manga.mangaId, title: d.chapterTitle, number: d.number);
      final pages = await source.pages(chapter);
      // Paused or deleted while the page list was loading.
      if (cancel.isCancelled) return;
      if (pages.isEmpty) throw const FormatException('no pages');
      final folder = Directory(p.join(
        await root(),
        DownloadManager.sanitize(manga.title).ifEmpty(manga.mangaId),
        // The id keeps two chapters with the same title apart.
        '${DownloadManager.sanitize(d.chapterTitle).ifEmpty(d.chapterId)} (${d.chapterId})',
      ))
        ..createSync(recursive: true);
      rec = rec.copyWith(dir: folder.path, pagesTotal: pages.length);
      if (cancel.isCancelled) return;
      await db.putMangaDownload(rec);

      final files = List<String?>.filled(pages.length, null);
      var done = 0;
      var bytes = 0;
      var nextIndex = 0;
      Future<void> worker() async {
        while (!cancel.isCancelled) {
          final i = nextIndex++;
          if (i >= pages.length) return;
          final page = pages[i];
          final name = (i + 1).toString().padLeft(3, '0') + _ext(page.url);
          final out = File(p.join(folder.path, name));
          if (!out.existsSync() || out.lengthSync() == 0) {
            final data = await _fetchPage(page, source.imageHeaders, cancel);
            // Written next to it and renamed, so a killed app never leaves half a page.
            final part = File('${out.path}.part');
            await part.writeAsBytes(data, flush: true);
            await part.rename(out.path);
          }
          if (cancel.isCancelled) return;
          files[i] = out.path;
          done++;
          bytes += out.lengthSync();
          // Progress is written every few pages to keep the database calm.
          if ((done % 3 == 0 || done == pages.length) && !cancel.isCancelled) {
            rec = rec.copyWith(pagesDone: done, bytes: bytes);
            await db.putMangaDownload(rec);
          }
        }
      }

      await Future.wait([for (var w = 0; w < pageConcurrency; w++) worker()]);
      if (cancel.isCancelled) return; // paused or deleted; state was written by pause/delete
      await db.putMangaDownload(rec.copyWith(
        status: MangaDownloadStatus.done,
        pagesDone: pages.length,
        bytes: bytes,
        files: files.whereType<String>().toList(),
      ));
    } catch (e) {
      if (cancel.isCancelled) return;
      Log.d('manga-dl', '${d.key}: $e');
      if (db.mangaDownload(d.key) != null) {
        await db.putMangaDownload(rec.copyWith(status: MangaDownloadStatus.failed, error: e.toString()));
      }
    } finally {
      _activeKey = null;
    }
  }

  Future<Uint8List> _fetchPage(MangaPage page, Map<String, String> headers, CancelToken cancel) async {
    Future<Uint8List> get(String url) async {
      final r = await withRetry(() => dio.get<List<int>>(url,
          cancelToken: cancel, options: Options(responseType: ResponseType.bytes, headers: headers)));
      final data = r.data;
      if (data == null || data.isEmpty) throw const FormatException('empty image');
      return data is Uint8List ? data : Uint8List.fromList(data);
    }

    try {
      return await get(page.url);
    } catch (e) {
      if (page.fallback == null || cancel.isCancelled) rethrow;
      return get(page.fallback!);
    }
  }

  static String _ext(String url) {
    final e = p.extension(Uri.tryParse(url)?.path ?? '').toLowerCase();
    return const {'.jpg', '.jpeg', '.png', '.webp', '.gif'}.contains(e) ? e : '.jpg';
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
