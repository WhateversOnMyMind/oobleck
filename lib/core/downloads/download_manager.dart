import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/providers.dart';
import '../log.dart';
import '../models.dart';
import '../sources/source.dart';
import '../storage/app_db.dart';
import '../storage/records.dart';
import 'foreground.dart';
import 'hls_downloader.dart';

final downloadManagerProvider = Provider<DownloadManager>((ref) {
  final m = DownloadManager(
    db: ref.watch(dbProvider),
    source: ref.watch(sourceProvider),
    dio: ref.watch(dioProvider),
    settings: () => ref.read(settingsProvider),
    cachePoster: (slug, url) => cachePoster(ref, slug, url),
    foreground: DownloadForeground(),
  );
  ref.onDispose(m.dispose);
  return m;
});

/// Persistent download queue: pause / resume / cancel / retry, a global
/// episode concurrency limit and server fallback.
class DownloadManager {
  DownloadManager({
    required this.db,
    required this.source,
    required this.dio,
    required this.settings,
    required this.cachePoster,
    this.foreground,
    this.baseDirOverride,
    this.fetchSubtitles = true,
  }) {
    // Anything interrupted by a restart goes back to the queue.
    for (final d in db.allDownloads()) {
      if (d.status == DownloadStatus.downloading) {
        d.status = DownloadStatus.queued;
        unawaited(db.putDownload(d));
      }
    }
    scheduleMicrotask(_pump);
  }

  final AppDb db;
  final Source source;
  final Dio dio;
  final AppSettings Function() settings;
  final Future<String?> Function(String slug, String? posterUrl) cachePoster;
  final DownloadForeground? foreground;
  final String? baseDirOverride;
  final bool fetchSubtitles;

  final Map<String, CancelToken> _active = {};
  final Map<String, _Speed> _speed = {};
  bool _disposed = false;

  void dispose() => _disposed = true;

  // ---- public API ---------------------------------------------------------
  Future<void> enqueue(ShowDetail show, List<EpisodeInfo> episodes, AudioType type, String quality) async {
    final existing = db.show(show.slug);
    await db.putShow(ShowRecord.fromDetail(show, posterPath: existing?.posterPath));
    unawaited(cachePoster(show.slug, show.poster));
    for (final e in episodes) {
      final key = DownloadRecord.keyOf(show.slug, e.number, type);
      final cur = db.download(key);
      if (cur != null && (cur.isDone || cur.status == DownloadStatus.downloading || cur.status == DownloadStatus.queued)) continue;
      await db.putDownload(DownloadRecord(
        slug: show.slug,
        episode: e.number,
        type: type,
        episodeTitle: e.title,
        serverKey: e.serverKey,
        malId: e.malId,
        preferredQuality: quality,
      ));
    }
    _pump();
  }

  Future<void> pause(String key) async {
    final d = db.download(key);
    if (d == null || d.isDone) return;
    d.status = DownloadStatus.paused;
    await db.putDownload(d);
    _active[key]?.cancel('pause');
  }

  Future<void> resume(String key) async {
    final d = db.download(key);
    if (d == null || d.isDone) return;
    d.status = DownloadStatus.queued;
    d.error = null;
    await db.putDownload(d);
    _pump();
  }

  Future<void> retry(String key) => resume(key);

  Future<void> pauseAll() async {
    for (final d in db.allDownloads().where((d) => d.status == DownloadStatus.queued || d.status == DownloadStatus.downloading)) {
      await pause(d.key);
    }
  }

  Future<void> resumeAll() async {
    for (final d in db.allDownloads().where((d) => d.status == DownloadStatus.paused || d.status == DownloadStatus.failed)) {
      await resume(d.key);
    }
  }

  /// Stops and removes a queued/active download and its partial files.
  Future<void> cancel(String key) async {
    final d = db.download(key);
    _active[key]?.cancel('cancel');
    await db.deleteDownload(key);
    if (d != null) await _deleteFiles(d);
  }

  /// Deletes a finished episode (video + subtitles).
  Future<void> deleteEpisode(String key) => cancel(key);

  Future<void> deleteShow(String slug) async {
    for (final d in db.allDownloads().where((d) => d.slug == slug)) {
      await cancel(d.key);
    }
    final s = db.show(slug);
    if (s?.posterPath != null) {
      try {
        File(s!.posterPath!).deleteSync();
      } catch (_) {}
    }
    // Keep the show record if it has watch history; the Library only lists
    // shows with completed downloads, so nothing else to do.
  }

  // ---- storage paths -------------------------------------------------------
  Future<String> downloadRoot() async {
    if (baseDirOverride != null) return baseDirOverride!;
    final custom = settings().downloadDir;
    if (custom != null && custom.isNotEmpty) return custom;
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'];
      if (home != null) return p.join(home, 'Videos', 'Oobleck');
    }
    if (Platform.isAndroid) {
      final dirs = await getExternalStorageDirectories(type: StorageDirectory.movies);
      if (dirs != null && dirs.isNotEmpty) return p.join(dirs.first.path, 'Oobleck');
    }
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'Oobleck');
  }

  static String sanitize(String s) => s.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

  Future<String> outBase(DownloadRecord d) async {
    final show = db.show(d.slug)?.title ?? d.slug;
    final name = sanitize(show);
    final ep = d.episode.contains('.') ? d.episode : d.episode.padLeft(2, '0');
    final suffix = d.type == AudioType.dub ? ' (Dub)' : '';
    final dir = Directory(p.join(await downloadRoot(), name))..createSync(recursive: true);
    return p.join(dir.path, '$name - E$ep$suffix');
  }

  Future<void> _deleteFiles(DownloadRecord d) async {
    Future<void> rm(String? path) async {
      if (path == null) return;
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }

    await rm(d.filePath);
    for (final s in d.subs) {
      await rm(s.path);
    }
    try {
      final base = await outBase(d);
      final parts = Directory('$base.parts');
      if (parts.existsSync()) parts.deleteSync(recursive: true);
      await rm('$base.part');
    } catch (_) {}
  }

  // ---- scheduler -----------------------------------------------------------
  void _pump() {
    if (_disposed) return;
    final all = db.allDownloads();
    final running = all.where((d) => d.status == DownloadStatus.downloading).length;
    final queued = all.where((d) => d.status == DownloadStatus.queued).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    var slots = settings().maxConcurrent - running;
    for (final d in queued) {
      if (slots <= 0) break;
      if (_active.containsKey(d.key)) continue;
      slots--;
      unawaited(_run(d));
    }
    _updateNotification();
  }

  void _updateNotification() {
    final fg = foreground;
    if (fg == null) return;
    final all = db.allDownloads();
    final active = all.where((d) => d.status == DownloadStatus.downloading || d.status == DownloadStatus.queued).toList();
    if (active.isEmpty) {
      unawaited(fg.stop());
      return;
    }
    final cur = active.firstWhere((d) => d.status == DownloadStatus.downloading, orElse: () => active.first);
    final title = db.show(cur.slug)?.title ?? 'Downloading';
    unawaited(fg.show('Downloading ${active.length} episode${active.length == 1 ? '' : 's'}',
        '$title · E${cur.episode} · ${(cur.progress * 100).round()}%'));
  }

  Future<void> _run(DownloadRecord d) async {
    final key = d.key;
    final token = CancelToken();
    _active[key] = token;
    d.status = DownloadStatus.downloading;
    d.error = null;
    await db.putDownload(d);
    try {
      await _download(d, token);
    } on DownloadCancelled {
      // pause/cancel already updated the record
    } catch (e) {
      if (token.isCancelled) {
        // fallthrough: user action
      } else {
        Log.d('dl', 'failed $key: $e');
        final cur = db.download(key);
        if (cur != null) {
          cur.status = DownloadStatus.failed;
          cur.error = 'Download failed. Tap retry to try again.';
          await db.putDownload(cur);
        }
      }
    } finally {
      _active.remove(key);
      _speed.remove(key);
      _pump();
    }
  }

  Future<void> _download(DownloadRecord d, CancelToken token) async {
    final ep = EpisodeInfo(number: d.episode, serverKey: d.serverKey, title: d.episodeTitle, malId: d.malId);
    final streams = <StreamSource>[];
    try {
      streams.addAll(await source.resolveStreams(ep, d.type).toList().timeout(const Duration(seconds: 25)));
    } on TimeoutException {
      // use whatever arrived: handled below by re-resolving once
    }
    if (streams.isEmpty) {
      streams.add(await source.resolveBest(ep, d.type, preference: settings().serverOrder));
    }
    final order = settings().serverOrder.map((e) => e.toLowerCase()).toList();
    int rank(StreamSource s) {
      final i = order.indexOf(s.serverName.toLowerCase());
      return i < 0 ? 999 : i;
    }

    streams.sort((a, b) => rank(a).compareTo(rank(b)));

    final base = await outBase(d);
    final dl = HlsDownloader(dio);
    Object? lastError;
    for (final s in streams) {
      if (token.isCancelled) throw DownloadCancelled();
      try {
        final result = s.isHls
            ? await dl.download(
                source: s,
                quality: d.preferredQuality,
                outBase: base,
                cancel: token,
                concurrency: settings().segmentConcurrency,
                onProgress: (bytes, done, total) => _progress(d, bytes, done, total),
              )
            : await dl.downloadFile(
                source: s,
                outPath: '$base.mp4',
                cancel: token,
                onProgress: (bytes, done, total) => _progress(d, bytes, done, total),
              );
        final subs = fetchSubtitles ? await _downloadSubs(s, base, token) : <DownloadedSub>[];
        final remuxed = await _maybeRemux(result.path);
        final cur = db.download(d.key) ?? d;
        cur
          ..status = DownloadStatus.done
          ..progress = 1
          ..filePath = remuxed
          ..totalBytes = File(remuxed).lengthSync()
          ..bytes = File(remuxed).lengthSync()
          ..durationMs = result.durationMs
          ..quality = result.quality
          ..subs = subs
          ..error = null;
        await db.putDownload(cur);
        return;
      } on DownloadCancelled {
        rethrow;
      } catch (e) {
        lastError = e;
        Log.d('dl', '${s.serverName} failed, trying next: $e');
      }
    }
    throw lastError ?? SourceException('No server could be downloaded');
  }

  void _progress(DownloadRecord d, int bytes, int done, int total) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final sp = _speed.putIfAbsent(d.key, () => _Speed(now, bytes));
    final cur = db.download(d.key);
    if (cur == null || cur.status != DownloadStatus.downloading) return;
    if (now - sp.lastWrite < 800 && done < total) return;
    final dt = (now - sp.t0) / 1000;
    cur
      ..progress = total == 0 ? 0 : done / total
      ..bytes = bytes
      ..speedBps = dt > 0.5 ? ((bytes - sp.b0) / dt).round() : 0
      ..totalBytes = done == 0 ? 0 : (bytes * total / done).round();
    sp.lastWrite = now;
    unawaited(db.putDownload(cur));
    if (now % 5 == 0) _updateNotification();
  }

  Future<List<DownloadedSub>> _downloadSubs(StreamSource s, String base, CancelToken token) async {
    final out = <DownloadedSub>[];
    final used = <String, int>{};
    for (final t in s.subtitles) {
      try {
        final r = await dio.get<List<int>>(t.url,
            cancelToken: token, options: Options(responseType: ResponseType.bytes, headers: s.headers));
        final lang = t.language;
        final n = used.update(lang, (v) => v + 1, ifAbsent: () => 0);
        var ext = p.extension(Uri.parse(t.url).path).toLowerCase();
        if (!const ['.vtt', '.srt', '.ass', '.ssa', '.smi'].contains(ext)) ext = '.vtt';
        final path = '$base.$lang${n == 0 ? '' : '$n'}$ext';
        await File(path).writeAsBytes(r.data ?? const []);
        out.add(DownloadedSub(path: path, label: t.label, language: lang));
      } catch (e) {
        Log.d('dl', 'subtitle ${t.label} failed: $e');
      }
    }
    return out;
  }

  Future<String> _maybeRemux(String path) => remuxToMp4(path);
}

/// Desktop only: if ffmpeg is on PATH, remux .ts -> .mp4 (stream copy) and
/// delete the .ts. Returns the new path, or [path] unchanged on any failure.
/// The input format is forced to MPEG-TS so stray bytes at the start can never
/// make ffmpeg probe it as something else (a PNG header once did), and only
/// audio/video are kept (segments also carry a timed ID3 data stream).
Future<String> remuxToMp4(String path, {String ffmpeg = 'ffmpeg'}) async {
  if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS) || !path.endsWith('.ts')) return path;
  try {
    final out = '${p.withoutExtension(path)}.mp4';
    final r = await Process.run(ffmpeg, ['-y', '-loglevel', 'error', '-f', 'mpegts', '-i', path, '-map', '0:v?', '-map', '0:a?', '-c', 'copy', out]);
    if (r.exitCode == 0 && File(out).existsSync() && File(out).lengthSync() > 0) {
      File(path).deleteSync();
      return out;
    }
  } catch (_) {
    // ffmpeg not installed: keep .ts
  }
  return path;
}

class _Speed {
  _Speed(this.t0, this.b0) : lastWrite = 0;
  final int t0;
  final int b0;
  int lastWrite;
}
