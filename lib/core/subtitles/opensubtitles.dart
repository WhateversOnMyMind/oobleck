import 'package:dio/dio.dart';

/// OpenSubtitles REST API v1 (api.opensubtitles.com). Optional: the user
/// enters their own free API key (and, for downloads, their account login) in
/// Settings. TODO(blocked): not verifiable offline without a key; written to
/// the public v1 docs.
class OpenSubtitlesResult {
  OpenSubtitlesResult({required this.fileId, required this.fileName, required this.release, required this.downloads});
  final int fileId;
  final String fileName;
  final String release;
  final int downloads;
}

class OpenSubtitlesClient {
  OpenSubtitlesClient(this.dio, {required this.apiKey, this.username = '', this.password = ''});
  final Dio dio;
  final String apiKey;
  final String username;
  final String password;
  String? _token;

  static const String base = 'https://api.opensubtitles.com/api/v1';

  Map<String, String> get _headers => {
        'Api-Key': apiKey,
        'User-Agent': 'Oobleck v1.0',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Future<List<OpenSubtitlesResult>> search(String title, int episode, {String language = 'ko'}) async {
    final r = await dio.get<Map<String, dynamic>>('$base/subtitles',
        queryParameters: {'query': title, 'languages': language, 'episode_number': episode, 'type': 'episode'},
        options: Options(headers: _headers));
    final out = <OpenSubtitlesResult>[];
    for (final x in (r.data?['data'] as List?) ?? const []) {
      final a = ((x as Map)['attributes'] as Map?) ?? const {};
      final files = (a['files'] as List?) ?? const [];
      if (files.isEmpty) continue;
      final f = files.first as Map;
      out.add(OpenSubtitlesResult(
        fileId: f['file_id'] as int,
        fileName: (f['file_name'] as String?) ?? (a['release'] as String? ?? 'subtitle'),
        release: a['release'] as String? ?? '',
        downloads: a['download_count'] as int? ?? 0,
      ));
    }
    return out;
  }

  Future<void> _login() async {
    if (_token != null || username.isEmpty) return;
    final r = await dio.post<Map<String, dynamic>>('$base/login',
        data: {'username': username, 'password': password}, options: Options(headers: _headers));
    _token = r.data?['token'] as String?;
  }

  /// Returns (file name, bytes).
  Future<(String, List<int>)> download(OpenSubtitlesResult res) async {
    await _login();
    final r = await dio.post<Map<String, dynamic>>('$base/download',
        data: {'file_id': res.fileId},
        options: Options(headers: {..._headers, if (_token != null) 'Authorization': 'Bearer $_token'}));
    final link = r.data?['link'] as String?;
    if (link == null) throw const FormatException('OpenSubtitles returned no link');
    final f = await dio.get<List<int>>(link, options: Options(responseType: ResponseType.bytes));
    return (r.data?['file_name'] as String? ?? res.fileName, f.data ?? const <int>[]);
  }
}
