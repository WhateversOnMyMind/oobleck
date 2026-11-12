import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:path/path.dart' as p;

import '../log.dart';
import '../models.dart';
import 'hls.dart';

class DownloadResult {
  DownloadResult({required this.path, required this.bytes, required this.durationMs, required this.quality});
  final String path;
  final int bytes;
  final int durationMs;
  final String quality;
}

typedef ProgressCallback = void Function(int bytes, int doneSegments, int totalSegments);

class DownloadCancelled implements Exception {
  @override
  String toString() => 'cancelled';
}

/// Our own HLS downloader. Segments are stored in `<out>.parts/` so a paused
/// or interrupted download resumes where it stopped; they are joined into a
/// single file at the end. Re-signs URLs on 403 (megaplay tokens expire ~90 s).
class HlsDownloader {
  HlsDownloader(this.dio, {this.retries = 5, this.backoff = const Duration(milliseconds: 400)});
  final Dio dio;
  final int retries;
  final Duration backoff;

  Future<List<int>> _getBytes(String url, StreamSource src, CancelToken cancel) async {
    var attempt = 0;
    var delay = backoff;
    while (true) {
      attempt++;
      try {
        final signed = src.signed(url);
        final r = await dio.get<List<int>>(signed,
            cancelToken: cancel,
            options: Options(
              responseType: ResponseType.bytes,
              headers: src.headers,
              validateStatus: (s) => s != null && s < 400,
            ));
        return r.data ?? const [];
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) throw DownloadCancelled();
        final code = e.response?.statusCode;
        // 403 -> next attempt signs again (fresh token).
        final retryable = code == null || code == 403 || code == 429 || code >= 500;
        if (!retryable || attempt >= retries) rethrow;
      }
      await Future<void>.delayed(delay);
      delay *= 2;
    }
  }

  Future<String> _getText(String url, StreamSource src, CancelToken cancel) async =>
      String.fromCharCodes(await _getBytes(url, src, cancel));

  Future<DownloadResult> download({
    required StreamSource source,
    required String quality,
    required String outBase,
    required CancelToken cancel,
    int concurrency = 6,
    ProgressCallback? onProgress,
  }) async {
    var playlistUrl = source.url;
    var text = await _getText(playlistUrl, source, cancel);
    var qualityLabel = '';
    if (isMasterPlaylist(text)) {
      final variants = parseMasterPlaylist(text, Uri.parse(playlistUrl));
      if (variants.isEmpty) throw const FormatException('Empty master playlist');
      final v = pickVariant(variants, quality);
      qualityLabel = v.label;
      playlistUrl = v.url.toString();
      text = await _getText(playlistUrl, source, cancel);
    }
    final media = parseMediaPlaylist(text, Uri.parse(playlistUrl));
    if (media.segments.isEmpty) throw const FormatException('Playlist has no segments');

    final partsDir = Directory('$outBase.parts')..createSync(recursive: true);
    final ext = media.initSegment != null ? 'mp4' : 'ts';
    final outPath = '$outBase.$ext';
    final total = media.segments.length;
    var done = 0;
    var bytes = 0;

    Future<List<int>> keyBytes(HlsKey k, Map<Uri, List<int>> cache) async =>
        cache[k.uri] ??= await _getBytes(k.uri.toString(), source, cancel);
    final keyCache = <Uri, List<int>>{};

    File partFile(int i) => File(p.join(partsDir.path, i.toString().padLeft(6, '0')));

    // Count segments that already exist (resume).
    for (var i = 0; i < total; i++) {
      final f = partFile(i);
      if (f.existsSync() && f.lengthSync() > 0) {
        done++;
        bytes += f.lengthSync();
      }
    }
    onProgress?.call(bytes, done, total);

    if (media.initSegment != null) {
      final f = File(p.join(partsDir.path, 'init'));
      if (!f.existsSync()) await f.writeAsBytes(await _getBytes(media.initSegment.toString(), source, cancel));
    }

    var next = 0;
    Object? failure;
    Future<void> worker() async {
      while (failure == null) {
        final i = next++;
        if (i >= total) return;
        final f = partFile(i);
        if (f.existsSync() && f.lengthSync() > 0) continue;
        try {
          final seg = media.segments[i];
          var data = Uint8List.fromList(await _getBytes(seg.url.toString(), source, cancel));
          if (seg.key != null) {
            final key = await keyBytes(seg.key!, keyCache);
            final iv = seg.key!.iv ?? _ivFromSequence(seg.sequence);
            final e = enc.Encrypter(enc.AES(enc.Key(Uint8List.fromList(key)), mode: enc.AESMode.cbc, padding: 'PKCS7'));
            data = Uint8List.fromList(e.decryptBytes(enc.Encrypted(data), iv: enc.IV(Uint8List.fromList(iv))));
          }
          data = unwrapSegment(data);
          final tmp = File('${f.path}.tmp');
          await tmp.writeAsBytes(data, flush: true);
          await tmp.rename(f.path);
          done++;
          bytes += data.length;
          onProgress?.call(bytes, done, total);
        } catch (e) {
          failure ??= e;
          return;
        }
      }
    }

    await Future.wait([for (var i = 0; i < min(concurrency, total); i++) worker()]);
    if (failure != null) {
      if (failure is DownloadCancelled) throw failure!;
      throw failure!;
    }

    // Join.
    final sink = File(outPath).openWrite();
    try {
      final init = File(p.join(partsDir.path, 'init'));
      if (init.existsSync()) sink.add(await init.readAsBytes());
      for (var i = 0; i < total; i++) {
        sink.add(await partFile(i).readAsBytes());
      }
    } finally {
      await sink.close();
    }
    partsDir.deleteSync(recursive: true);
    Log.d('hls', 'finished $outPath ($bytes bytes, $total segments)');
    return DownloadResult(
      path: outPath,
      bytes: File(outPath).lengthSync(),
      durationMs: (media.totalDuration * 1000).round(),
      quality: qualityLabel,
    );
  }

  static List<int> _ivFromSequence(int seq) {
    final b = Uint8List(16);
    ByteData.view(b.buffer).setUint32(12, seq);
    return b;
  }

  /// Plain (non-HLS) file with ranged resume into `<out>.part`.
  Future<DownloadResult> downloadFile({
    required StreamSource source,
    required String outPath,
    required CancelToken cancel,
    ProgressCallback? onProgress,
  }) async {
    final part = File('$outPath.part');
    var have = part.existsSync() ? part.lengthSync() : 0;
    final r = await dio.get<ResponseBody>(source.signed(source.url),
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.stream,
          headers: {...source.headers, if (have > 0) 'Range': 'bytes=$have-'},
          validateStatus: (s) => s != null && (s < 400 || s == 416),
        ));
    if (r.statusCode == 416) {
      // Already complete.
      await part.rename(outPath);
      return DownloadResult(path: outPath, bytes: File(outPath).lengthSync(), durationMs: 0, quality: '');
    }
    final resumed = r.statusCode == 206;
    if (!resumed) have = 0;
    final len = int.tryParse(r.headers.value(Headers.contentLengthHeader) ?? '') ?? 0;
    final totalLen = have + len;
    final sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
    try {
      await for (final chunk in r.data!.stream) {
        sink.add(chunk);
        have += chunk.length;
        onProgress?.call(have, totalLen == 0 ? 0 : (have * 100 ~/ totalLen), 100);
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) throw DownloadCancelled();
      rethrow;
    } finally {
      await sink.close();
    }
    await part.rename(outPath);
    return DownloadResult(path: outPath, bytes: File(outPath).lengthSync(), durationMs: 0, quality: '');
  }
}

/// Strips a fake file header that some CDNs put in front of HLS segments.
///
/// Megaplay's CDN (observed 2026-11-12) serves each MPEG-TS segment behind a
/// small PNG image header. Players that stream skip it, but joined segments
/// then look like a PNG to ffmpeg, which remuxed a 24-minute episode into a
/// 13-second "video". Finds the first offset where TS packets start (sync
/// byte 0x47 every 188 bytes) and drops what precedes it. Segments that
/// already start with TS packets, or that are not TS at all, are returned unchanged.
Uint8List unwrapSegment(Uint8List data) {
  const packet = 188;
  bool tsAt(int i) {
    for (var k = 0; k < 5; k++) {
      final j = i + k * packet;
      if (j >= data.length || data[j] != 0x47) return false;
    }
    return true;
  }

  if (data.length < 8 || tsAt(0)) return data;
  // Fragmented MP4 segments start with a box (size + type); leave them alone.
  final box = String.fromCharCodes(data.sublist(4, 8));
  if (const {'ftyp', 'styp', 'moof', 'sidx'}.contains(box)) return data;
  final limit = min(data.length, 64 * 1024);
  for (var i = 1; i < limit; i++) {
    if (data[i] == 0x47 && tsAt(i)) return Uint8List.sublistView(data, i);
  }
  return data;
}
