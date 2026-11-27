import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Draws a decoded page. Upscaling hooks in here.
Widget paintPage(ui.Image image, {BoxFit fit = BoxFit.contain, bool upscale = false, double sharpness = 0.5}) {
  return RawImage(image: image, fit: fit, filterQuality: FilterQuality.medium);
}
