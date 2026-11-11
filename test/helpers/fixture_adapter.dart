import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Serves canned responses by URL substring; records requests.
class FixtureAdapter implements HttpClientAdapter {
  FixtureAdapter(this.routes);

  /// Ordered: first key contained in the full URL wins. Value is a String body
  /// or a function (RequestOptions) -> String.
  final Map<String, Object> routes;
  final List<RequestOptions> requests = [];

  static String fixture(String name) => File('test/fixtures/anikoto/$name').readAsStringSync();

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final url = options.uri.toString();
    for (final e in routes.entries) {
      if (url.contains(e.key)) {
        final v = e.value;
        final body = v is Function ? (v as dynamic)(options) as String : v as String;
        return ResponseBody.fromString(body, 200, headers: {
          Headers.contentTypeHeader: ['application/json'],
        });
      }
    }
    return ResponseBody.fromString('not found: $url', 404, headers: {
      Headers.contentTypeHeader: ['text/plain'],
    });
  }

  @override
  void close({bool force = false}) {}
}
