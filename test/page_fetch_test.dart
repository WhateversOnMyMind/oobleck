import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/core/manga/manga_models.dart';
import 'package:oobleck/core/manga/page_fetch.dart';

final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, ...List.filled(64, 1)]);

/// Answers by host: [ok] serve an image, [hang] never answer, [html] serve a
/// filter page, anything else resets like a blocked network.
class Hosts implements HttpClientAdapter {
  Hosts({this.ok = const {}, this.hang = const {}, this.html = const {}});
  final Set<String> ok, hang, html;
  final hits = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancelFuture) async {
    final h = o.uri.host;
    hits.add(h);
    if (ok.contains(h)) return ResponseBody.fromBytes(jpeg, 200);
    if (html.contains(h)) return ResponseBody.fromString('<html>blocked</html>', 200);
    if (hang.contains(h)) {
      await (cancelFuture ?? Completer<void>().future);
      throw DioException.requestCancelled(requestOptions: o, reason: 'cancelled');
    }
    throw DioException.connectionError(requestOptions: o, reason: 'reset', error: const SocketException('Connection reset by peer'));
  }

  @override
  void close({bool force = false}) {}
}

MangaPage page(int i) => MangaPage(i, 'https://a.test/$i.jpg', fallback: 'http://b.test/$i.jpg');

void main() {
  test('a blocked host hands over to the mirror at once, and is tried last afterwards', () async {
    final hosts = Hosts(ok: {'b.test'});
    final f = PageFetcher(Dio()..httpClientAdapter = hosts);
    expect(await f.fetch(page(0)), jpeg);
    expect(hosts.hits, ['a.test', 'b.test'], reason: 'one try each, no retries on the blocked host first');
    hosts.hits.clear();
    expect(await f.fetch(page(1)), jpeg);
    expect(hosts.hits, ['b.test'], reason: 'the host that just failed waits its turn');
  });

  test('a host that never answers is given up on after the stall timeout', () async {
    final hosts = Hosts(hang: {'a.test'}, ok: {'b.test'});
    final f = PageFetcher(Dio()..httpClientAdapter = hosts, stallTimeout: const Duration(milliseconds: 200));
    final watch = Stopwatch()..start();
    expect(await f.fetch(page(0)), jpeg);
    expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    expect(f.order(page(1)).first, 'http://b.test/1.jpg');
  });

  test('a web page served instead of the image counts as a failure', () async {
    final hosts = Hosts(html: {'a.test'}, ok: {'b.test'});
    expect(await PageFetcher(Dio()..httpClientAdapter = hosts).fetch(page(0)), jpeg);
  });

  test('when every copy fails the error names each host', () async {
    final f = PageFetcher(Dio()..httpClientAdapter = Hosts());
    final e = await f.fetch(page(0)).then<Object?>((_) => null, onError: (Object e) => e);
    expect(e, isA<PageLoadException>());
    expect('$e', allOf(contains('a.test'), contains('b.test'), contains('Connection reset')));
  });

  test('cancelling stops at once', () async {
    final token = CancelToken();
    final f = PageFetcher(Dio()..httpClientAdapter = Hosts(hang: {'a.test', 'b.test'}));
    final done = f.fetch(page(0), cancel: token);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    token.cancel();
    await expectLater(done, throwsA(isA<DioException>().having((e) => e.type, 'type', DioExceptionType.cancel)));
  });
}
