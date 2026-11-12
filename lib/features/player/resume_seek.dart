import 'dart:async';

/// Seeks to [target] once the stream is ready and checks it actually got
/// there, retrying a few times.
///
/// mpv's per-file `start` option (what `Media(start:)` uses) was unreliable on
/// the site's HLS streams: playback began at 0:00 while the app announced
/// "Resumed at 13:46" (seen 2026-11-12). Seeking after the stream reports its
/// length, and confirming the position, is dependable.
///
/// Returns true when the position landed within [tolerance] of [target];
/// false when it never did or [cancelled] became true.
Future<bool> seekWhenReady({
  required Duration target,
  required Duration Function() duration,
  required Stream<Duration> durationChanges,
  required Duration Function() position,
  required Future<void> Function(Duration) seek,
  required bool Function() cancelled,
  int attempts = 3,
  Duration settle = const Duration(milliseconds: 800),
  Duration readyTimeout = const Duration(seconds: 30),
  Duration tolerance = const Duration(seconds: 15),
}) async {
  if (duration() <= Duration.zero) {
    try {
      await durationChanges.firstWhere((d) => d > Duration.zero).timeout(readyTimeout);
    } catch (_) {
      return false; // never became seekable
    }
  }
  for (var i = 0; i < attempts; i++) {
    if (cancelled()) return false;
    await seek(target);
    await Future<void>.delayed(settle);
    if (cancelled()) return false;
    if ((position() - target).abs() <= tolerance) return true;
  }
  return false;
}
