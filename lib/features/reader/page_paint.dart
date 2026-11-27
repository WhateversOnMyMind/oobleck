import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/manga/upscale/upscaled_image.dart';

/// Tallest decoded page. Phones often cap GPU textures at 8192 px; desktop
/// GPUs take 16384.
final int maxPageTextureSide = (Platform.isAndroid || Platform.isIOS) ? 8192 : 16384;

/// Draws a decoded page, sharpened and upscaled on the GPU when it is shown
/// larger than its own resolution (see `core/manga/upscale/`).
Widget paintPage(ui.Image image, {BoxFit fit = BoxFit.contain, bool upscale = false, double sharpness = 0.5}) {
  return UpscaledRawImage(
    image: image,
    fit: fit,
    enabled: upscale,
    sharpness: sharpness,
    fallbackQuality: FilterQuality.medium,
  );
}
