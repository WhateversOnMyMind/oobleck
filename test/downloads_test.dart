import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/app/settings.dart';
import 'package:oobleck/core/downloads/download_manager.dart';
import 'package:oobleck/core/downloads/hls.dart';
import 'package:oobleck/core/sources/source.dart';
import 'package:oobleck/core/storage/app_db.dart';
import 'package:oobleck/core/storage/records.dart';
import 'package:oobleck/core/downloads/hls_downloader.dart';
import 'package:oobleck/core/http.dart';
import 'package:oobleck/core/models.dart';
import 'package:oobleck/core/player/anime4k.dart';
import 'package:oobleck/core/subtitles/smi.dart';
import 'package:oobleck/core/subtitles/subtitle_import.dart';
import 'package:oobleck/core/subtitles/text_decode.dart';

/// Serves a generated 2-variant HLS stream (one AES-128 encrypted) from a
/// local HttpServer. Segment requests fail with 403 until a token is present
/// once, to exercise re-signing.
class _Hls {
  late HttpServer server;
  final Map<String, Uint8List> segs = {};
  final key = Uint8List.fromList(List.generate(16, (i) => i + 1));
  int forbidden = 0;
  int get port => server.port;

  Future<void> start() async {
    for (var i = 0; i < 5; i++) {
      segs['v720/s$i.ts'] = Uint8List.fromList(List.filled(1000, i + 10));
    }
    server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      final path = req.uri.path.substring(1);
      final res = req.response;
      if (path == 'master.m3u8') {
        res.write('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360\nv360/index.m3u8\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=2400000,RESOLUTION=1280x720\nv720/index.m3u8\n');
      } else if (path == 'v720/index.m3u8') {
        final b = StringBuffer('#EXTM3U\n#EXT-X-MEDIA-SEQUENCE:0\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n');
        for (var i = 0; i < 5; i++) {
          b.write('#EXTINF:4.0,\ns$i.ts\n');
        }
        b.write('#EXT-X-ENDLIST\n');
        res.write(b);
      } else if (path == 'v720/key.bin') {
        res.add(key);
      } else if (path.startsWith('v720/s')) {
        if (req.uri.queryParameters['t'] != '2' && forbidden < 2) {
          forbidden++;
          res.statusCode = 403;
        } else {
          final i = int.parse(path.substring(6, path.length - 3));
          final iv = Uint8List(16)..buffer.asByteData().setUint32(12, i);
          final e = enc.Encrypter(enc.AES(enc.Key(key), mode: enc.AESMode.cbc, padding: 'PKCS7'));
          res.add(e.encryptBytes(segs['v720/s$i.ts']!, iv: enc.IV(iv)).bytes);
        }
      } else {
        res.statusCode = 404;
      }
      await res.close();
    });
  }
}

class _FakeSource implements Source {
  _FakeSource(this.url);
  final String url;
  @override
  Stream<StreamSource> resolveStreams(EpisodeInfo episode, AudioType type) => Stream.value(StreamSource(
        url: url,
        serverName: 'T',
        type: type,
        subtitles: const [],
      ));
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  test('queue downloads an episode into the offline library and persists', () async {
    final hls = _Hls();
    await hls.start();
    final tmp = Directory.systemTemp.createTempSync('oobleck_mgr');
    var db = await AppDb.open('${tmp.path}/db');
    final mgr = DownloadManager(
      db: db,
      source: _FakeSource('http://127.0.0.1:${hls.port}/master.m3u8'),
      dio: buildDio(),
      settings: () => const AppSettings(),
      cachePoster: (_, _) async => null,
      baseDirOverride: '${tmp.path}/dl',
      fetchSubtitles: false,
    );
    hls.forbidden = 99; // never block (no signer in this test)
    const show = ShowDetail(slug: 'demo', siteId: '1', title: 'Demo: Show?', url: 'u', synopsis: 'syn');
    await mgr.enqueue(show, const [EpisodeInfo(number: '1', serverKey: 'k', title: 'Pilot')], AudioType.sub, '720');
    final key = DownloadRecord.keyOf('demo', '1', AudioType.sub);
    for (var i = 0; i < 100 && !(db.download(key)?.isDone ?? false); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final rec = db.download(key)!;
    expect(rec.isDone, isTrue, reason: '${rec.status} ${rec.error}');
    expect(File(rec.filePath!).existsSync(), isTrue);
    expect(rec.filePath, contains('Demo Show - E01'));
    expect(rec.quality, '720p');
    expect(db.show('demo')!.synopsis, 'syn');
    // survives a restart
    await db.close();
    db = await AppDb.open('${tmp.path}/db');
    expect(db.download(key)!.isDone, isTrue);
    final mgr2 = DownloadManager(
      db: db,
      source: _FakeSource('x'),
      dio: buildDio(),
      settings: () => const AppSettings(),
      cachePoster: (_, _) async => null,
      baseDirOverride: '${tmp.path}/dl',
    );
    await mgr2.deleteEpisode(key);
    expect(db.download(key), isNull);
    expect(File(rec.filePath!).existsSync(), isFalse);
    await db.close();
    await hls.server.close(force: true);
    tmp.deleteSync(recursive: true);
  });

  test('master playlist parsing and variant choice', () {
    final v = parseMasterPlaylist(
        '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=640x360\na.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=3,RESOLUTION=1920x1080\nb.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=2,RESOLUTION=1280x720\nc.m3u8',
        Uri.parse('http://h/x/master.m3u8'));
    expect(pickVariant(v, 'best').label, '1080p');
    expect(pickVariant(v, '720').label, '720p');
    expect(pickVariant(v, '480').label, '360p');
    expect(pickVariant(v, '144').label, '360p');
    expect(v.first.url.toString(), 'http://h/x/a.m3u8');
  });

  test('downloads AES-128 HLS, picks quality, re-signs on 403', () async {
    final hls = _Hls();
    await hls.start();
    final tmp = Directory.systemTemp.createTempSync('oobleck_dl');
    var signs = 0;
    final src = StreamSource(
      url: 'http://127.0.0.1:${hls.port}/master.m3u8',
      serverName: 'T',
      type: AudioType.sub,
      resign: (u) {
        signs++;
        return u.contains('/s') ? '$u?t=${signs > 3 ? 2 : 1}' : u;
      },
    );
    final progress = <int>[];
    final r = await HlsDownloader(buildDio(), backoff: const Duration(milliseconds: 5)).download(
      source: src,
      quality: '720',
      outBase: '${tmp.path}/ep',
      cancel: CancelToken(),
      concurrency: 2,
      onProgress: (b, d, t) => progress.add(d),
    );
    expect(r.quality, '720p');
    expect(r.durationMs, 20000);
    final out = File(r.path).readAsBytesSync();
    expect(out.length, 5000);
    expect(out.sublist(2000, 3000), List.filled(1000, 12));
    expect(Directory('${tmp.path}/ep.parts').existsSync(), isFalse);
    expect(progress.last, 5);
    expect(hls.forbidden, greaterThan(0));
    await hls.server.close(force: true);
    tmp.deleteSync(recursive: true);
  });

  group('subtitles', () {
    const smi = '''<SAMI><HEAD><TITLE>x</TITLE></HEAD><BODY>
<SYNC Start=1000><P Class=ENCC>Hello
<SYNC Start=1000><P Class=KRCC>안녕하세요<br>두번째 줄
<SYNC Start=3000><P Class=KRCC>&nbsp;
<SYNC Start=4000><P Class=KRCC>끝
</BODY></SAMI>''';

    test('SMI parses and picks the Korean class', () {
      final cues = parseSmi(smi);
      expect(cues.length, 2);
      expect(cues.first.text, '안녕하세요\n두번째 줄');
      expect(cues.first.startMs, 1000);
      expect(cues.first.endMs, 3000);
      expect(cuesToSrt(cues), contains('00:00:01,000 --> 00:00:03,000'));
      expect(cuesToVtt(cues), startsWith('WEBVTT'));
    });

    test('CP949 round trip and detection', () {
      const text = '안녕하세요 오블렉 자막 테스트 ♥';
      final bytes = encodeCp949(text);
      expect(bytes.any((b) => b > 0x80), isTrue);
      expect(decodeSubtitleBytes(bytes), contains('안녕하세요 오블렉 자막 테스트'));
      expect(decodeSubtitleBytes(utf8.encode(text)), text);
      // known real-world bytes: "가나다" in EUC-KR
      expect(decodeCp949([0xB0, 0xA1, 0xB3, 0xAA, 0xB4, 0xD9]), '가나다');
    });

    test('prepareSubtitle converts CP949 SMI to UTF-8 SRT', () {
      final p = prepareSubtitle(encodeCp949(smi), 'ep01.smi');
      expect(p.ext, '.srt');
      expect(p.text, contains('안녕하세요'));
    });

    test('episode picking ignores resolution noise', () {
      expect(pickForEpisode(['Show - 01 [1080p].smi', 'Show - 02 [1080p].smi', 'Show - 12 [1080p].smi'], 2), 'Show - 02 [1080p].smi');
      expect(pickForEpisode(['a.smi', 'b.smi'], 3), isNull);
    });
  });

  test('Anime4K chains reference only bundled shaders', () {
    for (final f in Anime4K.allFiles) {
      expect(File('assets/shaders/anime4k/$f').existsSync(), isTrue, reason: f);
    }
    expect(Anime4K.chain('a').length, 6);
  });
}
