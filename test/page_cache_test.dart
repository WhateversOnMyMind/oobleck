import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/core/manga/manga_models.dart';
import 'package:oobleck/core/manga/page_cache.dart';
import 'package:oobleck/core/manga/page_fetch.dart';

final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, ...List.filled(64, 7)]);

class Counting implements HttpClientAdapter {
  var calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancelFuture) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return ResponseBody.fromBytes(jpeg, 200);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('page_cache'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a downloaded page is returned, shared between callers and read from disk later', () async {
    final net = Counting();
    final cache = PageCache(fetcher: PageFetcher(Dio()..httpClientAdapter = net), dir: dir.path);
    const page = MangaPage(0, 'https://img.test/0.jpg');
    // Two readers of the same page share one download, and both get the bytes
    // (this used to wait forever once the download had finished).
    final both = await Future.wait([cache.bytes(page), cache.bytes(page)]).timeout(const Duration(seconds: 5));
    expect(both, [jpeg, jpeg]);
    expect(net.calls, 1);
    expect(await cache.bytes(page).timeout(const Duration(seconds: 5)), jpeg);
    expect(net.calls, 1, reason: 'second time from disk');
  });

  test('a cached error page is fetched again', () async {
    final net = Counting();
    final cache = PageCache(fetcher: PageFetcher(Dio()..httpClientAdapter = net), dir: dir.path);
    const page = MangaPage(0, 'https://img.test/1.jpg');
    File(cache.pathFor(page.url))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('<html>blocked</html>');
    expect(await cache.bytes(page).timeout(const Duration(seconds: 5)), jpeg);
    expect(net.calls, 1);
  });
}
