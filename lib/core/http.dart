import 'package:dio/dio.dart';

const String kUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/126.0.0.0 Safari/537.36';

/// Shared Dio factory. Tests pass their own [HttpClientAdapter].
Dio buildDio({HttpClientAdapter? adapter, Map<String, String>? headers}) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    followRedirects: true,
    validateStatus: (s) => s != null && s < 400,
    headers: {'User-Agent': kUserAgent, ...?headers},
  ));
  if (adapter != null) dio.httpClientAdapter = adapter;
  return dio;
}

/// Retries transient failures with exponential backoff.
Future<T> withRetry<T>(Future<T> Function() fn,
    {int attempts = 3, Duration base = const Duration(milliseconds: 400)}) async {
  var delay = base;
  for (var i = 1;; i++) {
    try {
      return await fn();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final fatal = code != null && code >= 400 && code < 500 && code != 429;
      if (i >= attempts || fatal || e.type == DioExceptionType.cancel) rethrow;
    }
    await Future<void>.delayed(delay);
    delay *= 2;
  }
}
