// Playback smoke test against a public HLS stream. Needs libmpv and network, so
// it only runs when OOBLECK_PLAYBACK=1 (the CI "playback" job sets it).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:oobleck/core/player/anime4k.dart';
import 'package:path/path.dart' as p;

const _stream = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';

Future<T> _first<T>(Stream<T> s, bool Function(T) test, {int seconds = 40}) =>
    s.firstWhere(test).timeout(Duration(seconds: seconds));

void main() {
  final enabled = Platform.environment['OOBLECK_PLAYBACK'] == '1';

  test('plays an HLS stream, seeks, and accepts the mpv properties the app sets', () async {
    MediaKit.ensureInitialized();
    final player = Player(configuration: const PlayerConfiguration(vo: 'null', libass: true));
    final errors = <String>[];
    final sub = player.stream.error.listen(errors.add);
    addTearDown(() async {
      await sub.cancel();
      await player.dispose();
    });

    // CI/sandboxes have no audio device; without this mpv stalls.
    await (player.platform as dynamic).setProperty('ao', 'null');
    await player.open(Media(_stream, start: const Duration(seconds: 5)), play: true);
    await _first(player.stream.duration, (d) => d > Duration.zero);
    expect(player.state.duration, greaterThan(const Duration(seconds: 30)));
    await _first(player.stream.position, (d) => d > const Duration(seconds: 6));
    expect(player.state.playing, isTrue);

    // Same properties PlayerSession sets for subtitles and Anime4K.
    final native = player.platform as dynamic;
    for (final e in {
      'sub-delay': '0.3',
      'sub-font-size': '46',
      'sub-color': '#FFFFFF',
      'sub-border-size': '2.5',
      'sub-back-color': '#00000000',
      'sub-pos': '100',
      'glsl-shaders': Anime4K.shaderList('a', p.absolute('assets/shaders/anime4k')),
    }.entries) {
      await native.setProperty(e.key, e.value);
    }
    await native.setProperty('glsl-shaders', '');

    await player.setRate(1.5);
    await player.seek(const Duration(seconds: 40));
    await _first(player.stream.position, (d) => d >= const Duration(seconds: 39));
    await player.pause();
    expect(player.state.playing, isFalse);
    expect(errors, isEmpty);
  }, skip: enabled ? false : 'set OOBLECK_PLAYBACK=1 (needs libmpv + network)', timeout: const Timeout(Duration(minutes: 2)));
}
