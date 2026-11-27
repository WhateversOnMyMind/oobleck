import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../http.dart';
import 'manga_models.dart';

/// Disk cache for manga page images, so going back a page or re-opening a
/// chapter does not download it again. Oldest files are dropped once the
/// cache grows past [maxBytes].
class PageCache {
  PageCache({required this.dio, required this.dir, this.maxBytes = 800 * 1024 * 1024});

  final Dio dio;
  final String dir;
  int maxBytes;

  final _inFlight = <String, Future<Uint8List>>{};
  int _writesSinceTrim = 0;

  String pathFor(String url) {
    final ext = p.extension(Uri.tryParse(url)?.path ?? '').toLowerCase();
    final safeExt = const {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.avif'}.contains(ext) ? ext : '.img';
    return p.join(dir, '${sha1.convert(utf8.encode(url))}$safeExt');
  }

  /// The image bytes for [page]: from disk if cached, otherwise downloaded
  /// (falling back to the page's mirror) and cached. Parallel requests for the
  /// same page share one download.
  Future<Uint8List> bytes(MangaPage page, {Map<String, String> headers = const {}, CancelToken? cancel}) {
    final key = page.url;
    return _inFlight[key] ??= _load(page, headers, cancel).whenComplete(() => _inFlight.remove(key));
  }

  Future<Uint8List> _load(MangaPage page, Map<String, String> headers, CancelToken? cancel) async {
    final file = File(pathFor(page.url));
    if (file.existsSync()) {
      try {
        final b = await file.readAsBytes();
        if (b.isNotEmpty) {
          unawaited(file.setLastModified(DateTime.now()).catchError((_) {}));
          return b;
        }
      } catch (_) {
        // unreadable: download again
      }
    }
    Uint8List data;
    try {
      data = await _fetch(page.url, headers, cancel);
    } catch (e) {
      final fb = page.fallback;
      if (fb == null || (e is DioException && e.type == DioExceptionType.cancel)) rethrow;
      data = await _fetch(fb, headers, cancel);
    }
    await _store(file, data);
    return data;
  }

  Future<Uint8List> _fetch(String url, Map<String, String> headers, CancelToken? cancel) async {
    final r = await withRetry(() => dio.get<List<int>>(
          url,
          cancelToken: cancel,
          options: Options(responseType: ResponseType.bytes, headers: headers),
        ));
    final data = r.data;
    if (data == null || data.isEmpty) throw const FormatException('empty image');
    return data is Uint8List ? data : Uint8List.fromList(data);
  }

  Future<void> _store(File file, Uint8List data) async {
    try {
      file.parent.createSync(recursive: true);
      final tmp = File('${file.path}.part');
      await tmp.writeAsBytes(data, flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      return; // caching is best effort
    }
    if (++_writesSinceTrim >= 40) {
      _writesSinceTrim = 0;
      unawaited(trim());
    }
  }

  /// Total size on disk.
  Future<int> sizeBytes() async {
    final d = Directory(dir);
    if (!d.existsSync()) return 0;
    var total = 0;
    await for (final f in d.list()) {
      if (f is File) total += await f.length();
    }
    return total;
  }

  /// Deletes least recently used files until the cache fits [maxBytes].
  Future<void> trim() async {
    final d = Directory(dir);
    if (!d.existsSync()) return;
    final files = <(File, int, DateTime)>[];
    var total = 0;
    await for (final f in d.list()) {
      if (f is! File) continue;
      final st = await f.stat();
      files.add((f, st.size, st.modified));
      total += st.size;
    }
    if (total <= maxBytes) return;
    files.sort((a, b) => a.$3.compareTo(b.$3));
    for (final (f, size, _) in files) {
      if (total <= maxBytes * 0.9) break;
      try {
        await f.delete();
        total -= size;
      } catch (_) {}
    }
  }

  Future<void> clear() async {
    final d = Directory(dir);
    if (d.existsSync()) await d.delete(recursive: true);
  }
}
