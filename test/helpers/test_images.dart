import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Builds an opaque image from a per-pixel 0xRRGGBB value.
Future<ui.Image> imageFromPixels(int width, int height, int Function(int x, int y) rgb) {
  final bytes = Uint8List(width * height * 4);
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      final v = rgb(x, y);
      final o = (y * width + x) * 4;
      bytes[o] = (v >> 16) & 0xff;
      bytes[o + 1] = (v >> 8) & 0xff;
      bytes[o + 2] = v & 0xff;
      bytes[o + 3] = 0xff;
    }
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(bytes, width, height, ui.PixelFormat.rgba8888, done.complete);
  return done.future;
}

/// The same level (0..255) on all three channels.
int grey(int level) => (level << 16) | (level << 8) | level;

/// Raw RGBA bytes of [image].
Future<Uint8List> pixelsOf(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
}
