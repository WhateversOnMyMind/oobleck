import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'image_header.dart';
import 'manga_models.dart';

/// Every copy of a page failed. [toString] lists what each host answered.
class PageLoadException implements Exception {
  PageLoadException(this.failures);
  final List<String> failures;

  @override
  String toString() => 'page did not load: ${failures.join('; ')}';
}

/// Downloads page images. Each copy (the page and its mirror) gets one quick
/// try before the other, instead of several slow retries, and hosts that just
/// failed are tried last for later pages. A network that blocks one image
/// host then costs a few seconds once rather than minutes on every page.
class PageFetcher {
  PageFetcher(
    this.dio, {
    this.stallTimeout = const Duration(seconds: 12),
    this.rounds = 2,
    this.rememberFailure = const Duration(minutes: 5),
  });

  final Dio dio;

  /// Gives up on a copy when no bytes arrive for this long.
  final Duration stallTimeout;

  /// Passes over the copies before giving up.
  final int rounds;

  /// How long a failed host stays at the back of the queue.
  final Duration rememberFailure;

  final _failedAt = <String, DateTime>{};

  static String _host(String url) => Uri.tryParse(url)?.host ?? url;

  bool _recentlyFailed(String url) {
    final t = _failedAt[_host(url)];
    return t != null && DateTime.now().difference(t) < rememberFailure;
  }

  /// The order copies of [page] are tried in.
  List<String> order(MangaPage page) {
    final fb = page.fallback;
    if (fb == null || fb == page.url) return [page.url];
    return _recentlyFailed(page.url) && !_recentlyFailed(fb) ? [fb, page.url] : [page.url, fb];
  }

  Future<Uint8List> fetch(MangaPage page, {Map<String, String> headers = const {}, CancelToken? cancel}) async {
    final urls = order(page);
    final failures = <String>[];
    for (var round = 0; round < rounds; round++) {
      if (round > 0) await Future<void>.delayed(const Duration(milliseconds: 500));
      for (final url in urls) {
        if (cancel?.isCancelled ?? false) throw cancel!.cancelError!;
        try {
          final data = await _once(url, headers, cancel);
          _failedAt.remove(_host(url));
          return data;
        } on DioException catch (e) {
          if (e.type == DioExceptionType.cancel) rethrow;
          final code = e.response?.statusCode;
          // No answer at all: likely blocked or down, so try it last next time.
          if (code == null) _failedAt[_host(url)] = DateTime.now();
          failures.add('${_host(url)}: ${code != null ? 'HTTP $code' : _cause(e)}');
        } on FormatException catch (e) {
          failures.add('${_host(url)}: ${e.message}');
        }
      }
    }
    throw PageLoadException(failures);
  }

  static String _cause(DioException e) {
    final cause = (e.error?.toString() ?? e.message ?? '').split('\n').first;
    return cause.isEmpty ? e.type.name : '${e.type.name}: $cause';
  }

  Future<Uint8List> _once(String url, Map<String, String> headers, CancelToken? outer) async {
    final token = CancelToken();
    unawaited(outer?.whenCancel.then((_) => token.cancel()));
    var stalled = false;
    Timer? timer;
    void arm() {
      timer?.cancel();
      timer = Timer(stallTimeout, () {
        stalled = true;
        token.cancel('stalled');
      });
    }

    arm();
    try {
      final r = await dio.get<List<int>>(
        url,
        cancelToken: token,
        onReceiveProgress: (_, _) => arm(),
        options: Options(responseType: ResponseType.bytes, headers: headers),
      );
      final data = r.data;
      if (data == null || data.isEmpty) throw const FormatException('empty image');
      final bytes = data is Uint8List ? data : Uint8List.fromList(data);
      // A filter or error page served with status 200 is not a page.
      if (sniffImage(bytes) == null) throw FormatException('not an image (${describeNonImage(bytes)})');
      return bytes;
    } on DioException catch (e) {
      if (stalled) {
        throw DioException(
          requestOptions: e.requestOptions,
          type: DioExceptionType.receiveTimeout,
          message: 'no answer for ${stallTimeout.inSeconds}s',
        );
      }
      rethrow;
    } finally {
      timer?.cancel();
    }
  }
}
