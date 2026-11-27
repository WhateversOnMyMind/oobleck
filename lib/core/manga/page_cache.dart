import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../files.dart';
import 'image_header.dart';
import 'manga_models.dart';
import 'page_fetch.dart';

/// Disk cache for manga page images, so going back a page or re-opening a
/// chapter does not download it again. Oldest files are dropped once the
/// cache grows past [maxBytes].
class PageCache {
  PageCache({required this.fetcher, required this.dir, this.maxBytes = 800 * 1024 * 1024});

  final PageFetcher fetcher;
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
    // A block body on purpose: `=> _inFlight.remove(key)` would return this
    // very future, and whenComplete would then wait for itself forever.
    return _inFlight[key] ??= _load(page, headers, cancel).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  Future<Uint8List> _load(MangaPage page, Map<String, String> headers, CancelToken? cancel) async {
    final file = File(pathFor(page.url));
    if (file.existsSync()) {
      try {
        final b = await file.readAsBytes();
        // Older versions could have cached an error page; fetch those again.
        if (sniffImage(b) != null) {
          unawaited(file.setLastModified(DateTime.now()).catchError((_) {}));
          return b;
        }
      } catch (_) {
        // unreadable: download again
      }
    }
    final data = await fetcher.fetch(page, headers: headers, cancel: cancel);
    await _store(file, data);
    return data;
  }

  Future<void> _store(File file, Uint8List data) async {
    try {
      file.parent.createSync(recursive: true);
      await writeFileAtomic(file, data);
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
