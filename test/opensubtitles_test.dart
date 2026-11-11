import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/core/http.dart';
import 'package:oobleck/core/subtitles/opensubtitles.dart';

import 'helpers/fixture_adapter.dart';

// SYNTHETIC responses shaped like the public OpenSubtitles REST v1 docs.
void main() {
  test('search maps results and sends key + user agent', () async {
    final a = FixtureAdapter({
      'api/v1/subtitles':
          '{"data":[{"attributes":{"release":"Show.S01E05.1080p","download_count":42,"files":[{"file_id":777,"file_name":"show.ko.srt"}]}},{"attributes":{"files":[]}}]}',
    });
    final c = OpenSubtitlesClient(buildDio(adapter: a), apiKey: 'KEY');
    final r = await c.search('Show', 5);
    expect(r.single.fileId, 777);
    expect(r.single.downloads, 42);
    final req = a.requests.single;
    expect(req.headers['Api-Key'], 'KEY');
    expect(req.headers['User-Agent'], 'Oobleck v1.0');
    expect(req.uri.queryParameters, containsPair('languages', 'ko'));
    expect(req.uri.queryParameters, containsPair('episode_number', '5'));
  });

  test('download logs in, then fetches the link with a bearer token', () async {
    final a = FixtureAdapter({
      'api/v1/login': '{"token":"JWT123"}',
      'api/v1/download': '{"link":"https://files.example/sub.srt","file_name":"x.srt"}',
      'files.example/sub.srt': '1\n00:00:01,000 --> 00:00:02,000\nhi\n',
    });
    final c = OpenSubtitlesClient(buildDio(adapter: a), apiKey: 'KEY', username: 'u', password: 'p');
    final (name, bytes) = await c.download(OpenSubtitlesResult(fileId: 1, fileName: 'f', release: '', downloads: 0));
    expect(name, 'x.srt');
    expect(String.fromCharCodes(bytes), contains('hi'));
    final dl = a.requests.firstWhere((r) => r.uri.path.endsWith('/download'));
    expect(dl.headers['Authorization'], 'Bearer JWT123');
    expect(dl.data, {'file_id': 1});
  });

  test('download without login skips the login call', () async {
    final a = FixtureAdapter({
      'api/v1/download': '{"link":"https://files.example/s.srt"}',
      'files.example/s.srt': 'x',
    });
    final c = OpenSubtitlesClient(buildDio(adapter: a), apiKey: 'KEY');
    await c.download(OpenSubtitlesResult(fileId: 2, fileName: 'f.srt', release: '', downloads: 0));
    expect(a.requests.any((r) => r.uri.path.endsWith('/login')), isFalse);
  });
}
