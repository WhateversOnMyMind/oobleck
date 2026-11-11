import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/core/downloads/download_manager.dart';

void main() {
  final hasFfmpeg = (() {
    try {
      return Process.runSync('ffmpeg', ['-version']).exitCode == 0;
    } catch (_) {
      return false;
    }
  })();

  test('remux turns a real .ts into a playable .mp4 and removes the .ts', () async {
    final tmp = Directory.systemTemp.createTempSync('oobleck_remux');
    final ts = '${tmp.path}/ep.ts';
    final gen = Process.runSync('ffmpeg', [
      '-y', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc=duration=2:size=160x90:rate=10',
      '-f', 'lavfi', '-i', 'sine=duration=2', '-c:v', 'mpeg2video', '-c:a', 'mp2', '-f', 'mpegts', ts,
    ]);
    expect(gen.exitCode, 0, reason: '${gen.stderr}');
    final out = await remuxToMp4(ts);
    expect(out.endsWith('.mp4'), isTrue);
    expect(File(out).lengthSync(), greaterThan(0));
    expect(File(ts).existsSync(), isFalse);
    tmp.deleteSync(recursive: true);
  }, skip: hasFfmpeg ? false : 'ffmpeg not installed');

  test('remux keeps the .ts when ffmpeg is missing or fails', () async {
    final tmp = Directory.systemTemp.createTempSync('oobleck_remux2');
    final ts = File('${tmp.path}/bad.ts')..writeAsBytesSync([1, 2, 3]);
    expect(await remuxToMp4(ts.path, ffmpeg: 'definitely-not-ffmpeg'), ts.path);
    expect(ts.existsSync(), isTrue);
    expect(await remuxToMp4(ts.path), ts.path); // garbage input: ffmpeg fails, file kept
    tmp.deleteSync(recursive: true);
  });
}
