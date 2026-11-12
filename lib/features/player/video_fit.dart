import 'package:flutter/material.dart';

/// How the picture fills the screen. Old 4:3 shows (Evangelion, 1440x1080)
/// get bars on a wide phone with [fit]; [fill] crops top and bottom instead.
enum VideoFit {
  fit('Fit', Icons.fit_screen_rounded, BoxFit.contain),
  fill('Zoom to fill', Icons.zoom_out_map_rounded, BoxFit.cover),
  stretch('Stretch', Icons.aspect_ratio_rounded, BoxFit.fill);

  const VideoFit(this.label, this.icon, this.boxFit);
  final String label;
  final IconData icon;
  final BoxFit boxFit;

  VideoFit get next => values[(index + 1) % values.length];

  static VideoFit parse(String? name) => values.firstWhere((v) => v.name == name, orElse: () => fit);
}

/// Text scale for subtitles drawn by Flutter (Android).
///
/// media_kit's default is sqrt(area / 1920x1080), which comes out around 0.4
/// on a phone in landscape, so text was ~10 dp. This follows mpv/libass on
/// desktop instead: the size setting is in pixels of a 720-pixel-high screen,
/// so subtitles take the same share of the screen height everywhere and do not
/// depend on the video's aspect ratio.
double subtitleTextScale(Size screen) {
  if (screen.height <= 0) return 1;
  return (screen.height / 720 * 0.75).clamp(0.3, 2.0);
}
