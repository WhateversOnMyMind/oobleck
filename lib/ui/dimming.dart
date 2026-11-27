import 'dart:async';

import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';

import 'layout.dart';

/// One brightness scale for the player and the reader, from [darkest] up to 1.
///
/// 0..1 is the screen's own backlight. Below 0 the backlight stays at its
/// lowest and a black layer darkens the picture further, so the screen gets
/// much darker than the phone's own minimum but never goes black: at
/// [darkest] a tenth of the picture still shows.
abstract final class Dimming {
  static const double darkest = -0.9;

  /// Only phones change the backlight; desktops keep their own.
  static bool get supported => isMobile;

  static double clamp(double level) => level.clamp(darkest, 1.0);

  /// Backlight for [level], 0..1.
  static double backlight(double level) => level.clamp(0.0, 1.0);

  /// Opacity of the black layer for [level], 0..0.9.
  static double shade(double level) => level < 0 ? -clamp(level) : 0.0;

  /// 1 % at the darkest, 100 % at full brightness.
  static int percent(double level) => ((clamp(level) - darkest) / (1 - darkest) * 99 + 1).round();

  static IconData icon(double level) => level < 0
      ? Icons.brightness_low_rounded
      : level < 0.5
          ? Icons.brightness_medium_rounded
          : Icons.brightness_high_rounded;

  /// Sets the backlight part of [level] for this app only.
  static Future<void> apply(double level) =>
      ScreenBrightness.instance.setApplicationScreenBrightness(backlight(level)).catchError((_) {});

  /// Gives the backlight back to the phone.
  static Future<void> reset() => ScreenBrightness.instance.resetApplicationScreenBrightness().catchError((_) {});

  /// The app's current backlight, 0..1 (0.5 when the phone does not say).
  static Future<double> current() async {
    try {
      return await ScreenBrightness.instance.application;
    } catch (_) {
      return 0.5;
    }
  }
}

/// The black layer for levels below 0. Lets touches through.
class DimShade extends StatelessWidget {
  const DimShade({super.key, required this.level});
  final double level;

  @override
  Widget build(BuildContext context) {
    final a = Dimming.shade(level);
    if (a <= 0) return const SizedBox.shrink();
    return IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: a)));
  }
}
