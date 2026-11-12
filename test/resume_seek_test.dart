import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/features/player/resume_seek.dart';

/// A stand-in for mpv: seeks are ignored until the stream knows its length,
/// and [ignoreSeeks] more after that (a seek mpv dropped while buffering).
class _FakePlayer {
  _FakePlayer({this.ignoreSeeks = 0});
  int ignoreSeeks;
  Duration duration = Duration.zero;
  Duration position = const Duration(seconds: 1);
  final durations = StreamController<Duration>.broadcast();
  final seeks = <Duration>[];

  Future<void> seek(Duration to) async {
    seeks.add(to);
    if (duration <= Duration.zero) return;
    if (ignoreSeeks > 0) {
      ignoreSeeks--;
      return;
    }
    position = to;
  }

  void ready() {
    duration = const Duration(minutes: 24);
    durations.add(duration);
  }

  Future<bool> resume(Duration target, {bool Function()? cancelled, Duration readyTimeout = const Duration(seconds: 2)}) => seekWhenReady(
        target: target,
        duration: () => duration,
        durationChanges: durations.stream,
        position: () => position,
        seek: seek,
        cancelled: cancelled ?? () => false,
        settle: const Duration(milliseconds: 5),
        readyTimeout: readyTimeout,
      );
}

void main() {
  const target = Duration(minutes: 13, seconds: 46);

  test('waits until the stream is seekable, then lands on the saved position', () async {
    final p = _FakePlayer();
    final done = p.resume(target);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(p.seeks, isEmpty, reason: 'no seek before the stream has a length');
    p.ready();
    expect(await done, isTrue);
    expect(p.position, target);
  });

  test('a dropped seek (stuck at 0:01, as reported) is retried', () async {
    final p = _FakePlayer(ignoreSeeks: 1)..ready();
    expect(await p.resume(target), isTrue);
    expect(p.seeks, [target, target]);
    expect(p.position, target);
  });

  test('reports failure instead of claiming a resume that did not happen', () async {
    final p = _FakePlayer(ignoreSeeks: 99)..ready();
    expect(await p.resume(target), isFalse);
    expect(p.seeks.length, 3);
  });

  test('gives up if the stream never becomes seekable, or the episode changed', () async {
    expect(await _FakePlayer().resume(target, readyTimeout: const Duration(milliseconds: 30)), isFalse);
    final p = _FakePlayer()..ready();
    expect(await p.resume(target, cancelled: () => true), isFalse);
    expect(p.seeks, isEmpty);
  });
}
