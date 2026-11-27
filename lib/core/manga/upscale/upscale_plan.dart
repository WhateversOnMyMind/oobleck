import 'dart:math' as math;
import 'dart:ui' show Rect, Size;

/// Size limits for upscaled textures.
class UpscaleLimits {
  const UpscaleLimits({
    this.maxDimension = 4096,
    this.maxBandPixels = 4096 * 2048,
    this.minFactor = 1.1,
  }) : assert(maxDimension > 0),
       assert(maxBandPixels > 0);

  /// Longest side of one upscaled texture. 4096 is safe on every GPU the app
  /// targets (GLES 3 phones guarantee at least this much).
  final int maxDimension;

  /// Largest area of one band, which bounds the memory of a single texture
  /// (4 bytes per pixel, so the default is 32 MB).
  final int maxBandPixels;

  /// Upscaling only runs when the image is drawn more than this many times
  /// larger than its source. Below it plain filtering looks the same.
  final double minFactor;
}

/// A horizontal slice of the upscaled output, in output pixels.
class UpscaleBand {
  const UpscaleBand(this.index, this.top, this.height);

  final int index;
  final int top;
  final int height;

  int get bottom => top + height;

  @override
  String toString() => 'UpscaleBand($index, $top..$bottom)';
}

/// How one image is upscaled: the output size in physical pixels and the
/// bands it is split into so that no texture exceeds [UpscaleLimits].
class UpscalePlan {
  const UpscalePlan._(this.width, this.height, this.bandHeight);

  /// Output size in pixels.
  final int width;
  final int height;

  /// Height of every band except possibly the last one.
  final int bandHeight;

  int get bandCount => (height / bandHeight).ceil();

  /// Bytes of one cached band with [rows] rows.
  int bytesFor(int rows) => width * rows * 4;

  UpscaleBand band(int index) {
    assert(index >= 0 && index < bandCount);
    final top = index * bandHeight;
    return UpscaleBand(index, top, math.min(bandHeight, height - top));
  }

  /// Indices (first, last) of the bands that overlap the output rows from
  /// [top] to [bottom], or null when nothing overlaps.
  (int, int)? bandsBetween(double top, double bottom) {
    if (!(bottom > top) || bottom <= 0 || top >= height) return null;
    final first = (math.max(top, 0) / bandHeight).floor();
    final last = ((math.min(bottom, height.toDouble()) / bandHeight).ceil() - 1);
    return (first.clamp(0, bandCount - 1), last.clamp(first, bandCount - 1));
  }

  /// The part of [whole] (source or destination rectangle) that corresponds
  /// to the output rows from [top] to [bottom].
  Rect slice(Rect whole, int top, int bottom) {
    final k = whole.height / height;
    return Rect.fromLTRB(whole.left, whole.top + top * k, whole.right, whole.top + bottom * k);
  }

  /// Plans the upscale of a [source] region (in source pixels) drawn into a
  /// [destination] of logical pixels on a screen with [devicePixelRatio].
  ///
  /// Returns null when upscaling is not worth it: the image is not enlarged
  /// by more than [UpscaleLimits.minFactor], is shrunk on either axis, or a
  /// size is empty.
  static UpscalePlan? compute({
    required Size source,
    required Size destination,
    required double devicePixelRatio,
    UpscaleLimits limits = const UpscaleLimits(),
  }) {
    if (!_usable(source.width) || !_usable(source.height)) return null;
    if (!_usable(destination.width) || !_usable(destination.height)) return null;
    if (!_usable(devicePixelRatio)) return null;

    double w = destination.width * devicePixelRatio;
    double h = destination.height * devicePixelRatio;
    // Too wide for one texture: upscale to the widest allowed size and let
    // the final draw stretch the rest.
    if (w > limits.maxDimension) {
      h *= limits.maxDimension / w;
      w = limits.maxDimension.toDouble();
    }
    final width = w.round();
    final height = h.round();
    if (width < 1 || height < 1) return null;

    final fx = width / source.width;
    final fy = height / source.height;
    if (math.min(fx, fy) < 1.0 || math.max(fx, fy) <= limits.minFactor) return null;

    final maxRows = math.max(1, math.min(limits.maxDimension, limits.maxBandPixels ~/ width));
    // Even bands instead of full ones plus a thin remainder.
    final count = (height / maxRows).ceil();
    return UpscalePlan._(width, height, (height / count).ceil());
  }

  static bool _usable(double v) => v.isFinite && v > 0;
}
