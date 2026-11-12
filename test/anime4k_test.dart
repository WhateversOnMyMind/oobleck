import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/core/player/anime4k.dart';

void main() {
  group('Anime4K.checkPasses (mpv vo-passes)', () {
    // Shape of mpv's vo-passes property as a string (JSON node).
    const running = '{"fresh":[{"desc":"Anime4K-v4.0-Restore-CNN-(M)-Conv-4x3x3x3","last":1,"avg":1,"peak":1,"count":1,"samples":[1]},'
        '{"desc":"Anime4K-v4.0-Upscale-CNN-x2-(M)-Conv-4x3x3x3","last":1,"avg":1,"peak":1,"count":1,"samples":[1]},'
        '{"desc":"scaling","last":1,"avg":1,"peak":1,"count":1,"samples":[1]}],"redraw":[]}';
    const plain = '{"fresh":[{"desc":"scaling","last":1,"avg":1,"peak":1,"count":1,"samples":[1]}],"redraw":[]}';

    test('counts Anime4K passes', () {
      final r = Anime4K.checkPasses(running);
      expect(r.running, isTrue);
      expect(r.count, 2);
    });

    test('frames without Anime4K passes mean it is not running', () {
      expect(Anime4K.checkPasses(plain).running, isFalse);
    });

    test('no passes reported means unknown', () {
      expect(Anime4K.checkPasses(null).running, isNull);
      expect(Anime4K.checkPasses('').running, isNull);
      expect(Anime4K.checkPasses('{"fresh":[],"redraw":[]}').running, isNull);
    });
  });
}
