import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/core/downloads/download_manager.dart';
import 'package:oobleck/core/downloads/hls_downloader.dart';
import 'package:oobleck/core/http.dart';
import 'package:oobleck/core/models.dart';

/// The 1x1 PNG that megaplay's CDN put in front of every segment
/// (taken from a real download, 2026-11-12).
final Uint8List fakePng = Uint8List.fromList(_hex(
    '89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d4944415478da6364f8cf500f00038601805a347d6b0000000049454e44ae426082'));

List<int> _hex(String s) => [for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)];

/// [n] fake TS packets (sync byte + packet index).
Uint8List tsPackets(int n) {
  final b = Uint8List(188 * n);
  for (var i = 0; i < n; i++) {
    b[i * 188] = 0x47;
    b[i * 188 + 1] = i & 0xff;
  }
  return b;
}

void main() {
  group('unwrapSegment', () {
    test('strips the fake PNG header', () {
      final ts = tsPackets(10);
      final out = unwrapSegment(Uint8List.fromList([...fakePng, ...ts]));
      expect(out, ts);
    });

    test('skips a partial packet after the header (as seen in real data)', () {
      final partial = Uint8List(182)..[0] = 0x47;
      final ts = tsPackets(10);
      final out = unwrapSegment(Uint8List.fromList([...fakePng, ...partial, ...ts]));
      expect(out, ts);
    });

    test('leaves plain TS, fMP4 and unknown data alone', () {
      final ts = tsPackets(6);
      expect(identical(unwrapSegment(ts), ts), isTrue);
      final fmp4 = Uint8List.fromList([0, 0, 0, 24, ...'moof'.codeUnits, ...List.filled(2000, 0x47)]);
      expect(identical(unwrapSegment(fmp4), fmp4), isTrue);
      final junk = Uint8List.fromList(List.generate(5000, (i) => (i * 7) & 0xff));
      expect(identical(unwrapSegment(junk), junk), isTrue);
    });
  });

  final hasFfmpeg = (() {
    try {
      return Process.runSync('ffmpeg', ['-version']).exitCode == 0;
    } catch (_) {
      return false;
    }
  })();

  test('a PNG-disguised HLS stream downloads and remuxes to its full length', () async {
    final tmp = Directory.systemTemp.createTempSync('oobleck_disguised');
    final src = '${tmp.path}/src.ts';
    final gen = Process.runSync('ffmpeg', [
      '-y', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc=duration=6:size=160x90:rate=10',
      '-f', 'lavfi', '-i', 'sine=duration=6', '-c:v', 'mpeg2video', '-c:a', 'mp2', '-f', 'mpegts', src,
    ]);
    expect(gen.exitCode, 0, reason: '${gen.stderr}');

    // Cut the stream into 3 segments on packet boundaries, each behind the fake PNG.
    final bytes = File(src).readAsBytesSync();
    final packets = bytes.length ~/ 188;
    final per = (packets / 3).ceil();
    final segs = <Uint8List>[];
    for (var s = 0; s * per < packets; s++) {
      final end = ((s + 1) * per).clamp(0, packets);
      segs.add(Uint8List.fromList([...fakePng, ...bytes.sublist(s * per * 188, end * 188)]));
    }

    final server = await HttpServer.bind('127.0.0.1', 0);
    server.listen((req) async {
      final path = req.uri.path.substring(1);
      if (path == 'index.m3u8') {
        final b = StringBuffer('#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:0\n');
        for (var i = 0; i < segs.length; i++) {
          b.write('#EXTINF:2.0,\ns$i.png\n');
        }
        b.write('#EXT-X-ENDLIST\n');
        req.response.write(b);
      } else if (path.startsWith('s')) {
        req.response.add(segs[int.parse(path.substring(1, path.length - 4))]);
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });

    final r = await HlsDownloader(buildDio()).download(
      source: StreamSource(url: 'http://127.0.0.1:${server.port}/index.m3u8', serverName: 'T', type: AudioType.sub),
      quality: 'best',
      outBase: '${tmp.path}/ep',
      cancel: CancelToken(),
      concurrency: 2,
    );
    await server.close(force: true);
    expect(File(r.path).readAsBytesSync(), bytes.sublist(0, packets * 188));

    final mp4 = await remuxToMp4(r.path);
    expect(mp4.endsWith('.mp4'), isTrue);
    final probe = Process.runSync('ffmpeg', ['-hide_banner', '-i', mp4]);
    final info = '${probe.stderr}';
    expect(info, contains('mpeg2video'));
    expect(info, isNot(contains('png')));
    final m = RegExp(r'Duration: 00:00:(\d+)\.(\d+)').firstMatch(info);
    expect(m, isNotNull, reason: info);
    expect(int.parse(m!.group(1)!), greaterThanOrEqualTo(5));
    tmp.deleteSync(recursive: true);
  }, skip: hasFfmpeg ? false : 'ffmpeg not installed');
}
