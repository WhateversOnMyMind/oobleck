/// GPU upscaling for manga and webtoon pages.
///
/// How the reader uses it:
///
/// * Decode the page to a [ui.Image] as usual and show it with
///   `UpscaledRawImage(image: page)` (see `upscaled_image.dart`) wherever it
///   would have used `RawImage`. The widget lays out exactly like `RawImage`,
///   loads the shaders on first use, and draws a plain image until they are
///   ready, when the page is not enlarged, or when anything fails. Bind the
///   reader's "upscale" setting to `enabled` and its strength to `sharpness`.
/// * A long webtoon strip can be one widget inside a scroll view: only the
///   bands near the viewport are upscaled and kept in the shared cache.
/// * Call `Upscaler.load()` early (for example when the reader opens) to avoid
///   one frame of plain filtering on the first page. It returns null when
///   fragment shaders are unavailable; nothing else needs to check for that.
/// * A reader that paints pages itself can call [Upscaler.paint] from its own
///   painter, or [Upscaler.upscale] to get a standalone image.
/// * Call [Upscaler.evict] when a page image is disposed, and
///   [Upscaler.clearCache] when leaving the reader.
///
/// The work is two fragment shader passes (`shaders/manga_upscale.frag`, then
/// `shaders/manga_sharpen.frag`) rendered once into a texture per band; after
/// that a frame costs one textured quad per visible band.
library;

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'fsr_license.dart';
import 'upscale_cache.dart';
import 'upscale_plan.dart';

export 'upscale_plan.dart' show UpscaleLimits;

/// What [Upscaler.paint] drew.
enum UpscalePaintResult {
  /// The image was drawn with ordinary filtering only.
  plain,

  /// Every band in view was drawn upscaled (or could not be, for good).
  upscaled,

  /// Some bands in view were drawn plain because this frame's render budget
  /// was used up. Paint again next frame to finish.
  pending,
}

/// Asset keys of the two passes, as registered under `flutter: shaders:`.
const String kUpscaleShaderAsset = 'shaders/manga_upscale.frag';
const String kSharpenShaderAsset = 'shaders/manga_sharpen.frag';

class Upscaler {
  Upscaler._(this._upscale, this._sharpen, {required this.limits, required int cacheBytes})
    : _cache = LruByteCache<_BandKey, ui.Image>(
        maxBytes: cacheBytes,
        onEvict: (image) => image.dispose(),
      );

  /// Budget for cached bands. Enough for a 4K viewport plus a band of
  /// scroll-ahead on either side.
  static const int defaultCacheBytes = 192 * 1024 * 1024;

  static Future<Upscaler?>? _instance;
  static Upscaler? _loaded;

  /// Loads the shader programs once. Completes with null when they cannot be
  /// loaded (no fragment shader support, or the assets are missing).
  static Future<Upscaler?> load() => _instance ??= _load();

  /// The loaded instance, or null while loading or when unavailable.
  static Upscaler? get loaded => _loaded;

  static Future<Upscaler?> _load() async {
    try {
      final programs = await Future.wait([
        ui.FragmentProgram.fromAsset(kUpscaleShaderAsset),
        ui.FragmentProgram.fromAsset(kSharpenShaderAsset),
      ]);
      final upscaler = Upscaler._(
        programs[0].fragmentShader(),
        programs[1].fragmentShader(),
        limits: const UpscaleLimits(),
        cacheBytes: defaultCacheBytes,
      );
      SchedulerBinding.instance.addPersistentFrameCallback((_) => upscaler._nextFrame());
      registerFsrLicense();
      return _loaded = upscaler;
    } catch (e) {
      debugPrint('Upscaler: shaders unavailable, using plain filtering ($e)');
      return null;
    }
  }

  final ui.FragmentShader _upscale;
  final ui.FragmentShader _sharpen;
  final LruByteCache<_BandKey, ui.Image> _cache;

  /// Texture size limits. Change before the first paint.
  UpscaleLimits limits;

  /// At most this many bands are rendered per frame; the rest are drawn plain
  /// and picked up on the following frames, so a fling never stalls on a
  /// burst of shader work.
  int maxRendersPerFrame = 2;

  int _rendersThisFrame = 0;

  int get cacheBytes => _cache.bytes;
  int get cacheMaxBytes => _cache.maxBytes;
  set cacheMaxBytes(int value) => _cache.maxBytes = value;

  void _nextFrame() {
    _cache.tick++;
    _rendersThisFrame = 0;
  }

  /// Marks the start of a new frame without a real one.
  @visibleForTesting
  void debugNextFrame() => _nextFrame();

  /// Drops every cached band made from [image].
  void evict(ui.Image image) => _cache.removeWhere((k) => identical(k.image, image));

  void clearCache() => _cache.clear();

  /// Upscales the [src] region of [source] (the whole image by default) to
  /// [target] pixels. [sharpness] runs from 0 (edge-adaptive scaling only) to
  /// 1 (strongest sharpening).
  ///
  /// Returns null when [target] is not larger than the source or does not fit
  /// in one texture under [limits]. The caller owns the returned image.
  ui.Image? upscale(ui.Image source, {ui.Rect? src, required ui.Size target, double sharpness = 0.5}) {
    final region = src ?? ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble());
    final plan = UpscalePlan.compute(
      source: region.size,
      destination: target,
      devicePixelRatio: 1,
      limits: limits,
    );
    if (plan == null || plan.bandCount != 1) return null;
    if (plan.width != target.width.round() || plan.height != target.height.round()) return null;
    return _render(source, region, plan, plan.band(0), sharpness);
  }

  /// Paints the [src] region of [image] into [dst] (logical pixels), upscaled
  /// to the physical pixels of a screen with [devicePixelRatio].
  ///
  /// [visibleTop] and [visibleBottom] bound the part of [dst] that is (or is
  /// about to be) on screen, in the same coordinates as [dst]; only bands
  /// inside it are upscaled, the rest are drawn plain with [fallbackQuality].
  /// Without them the whole destination counts as visible.
  ///
  /// Never throws: on any failure the affected part is drawn plain.
  UpscalePaintResult paint(
    ui.Canvas canvas, {
    required ui.Image image,
    required ui.Rect src,
    required ui.Rect dst,
    required double devicePixelRatio,
    double sharpness = 0.5,
    double? visibleTop,
    double? visibleBottom,
    ui.FilterQuality fallbackQuality = ui.FilterQuality.medium,
  }) {
    final plain = ui.Paint()
      ..filterQuality = fallbackQuality
      ..isAntiAlias = false;
    final plan = UpscalePlan.compute(
      source: src.size,
      destination: dst.size,
      devicePixelRatio: devicePixelRatio,
      limits: limits,
    );
    if (plan == null) {
      canvas.drawImageRect(image, src, dst, plain);
      return UpscalePaintResult.plain;
    }

    final rowsPerUnit = plan.height / dst.height;
    final range = plan.bandsBetween(
      ((visibleTop ?? dst.top) - dst.top) * rowsPerUnit,
      ((visibleBottom ?? dst.bottom) - dst.top) * rowsPerUnit,
    );
    final sharp = ui.Paint()
      ..filterQuality = ui.FilterQuality.low
      ..isAntiAlias = false;
    bool pending = false;
    bool any = false;
    // Start row of the run of bands that still has to be drawn plain.
    int plainFrom = 0;
    void flushPlain(int to) {
      if (to <= plainFrom) return;
      canvas.drawImageRect(image, plan.slice(src, plainFrom, to), plan.slice(dst, plainFrom, to), plain);
    }

    if (range != null) {
      for (int i = range.$1; i <= range.$2; i++) {
        final band = plan.band(i);
        final (bandImage, deferred) = _bandFor(image, src, plan, band, sharpness);
        pending |= deferred;
        if (bandImage == null) continue;
        flushPlain(band.top);
        plainFrom = band.bottom;
        canvas.drawImageRect(
          bandImage,
          ui.Rect.fromLTWH(0, 0, plan.width.toDouble(), band.height.toDouble()),
          plan.slice(dst, band.top, band.bottom),
          sharp,
        );
        any = true;
      }
    }
    flushPlain(plan.height);
    if (pending) return UpscalePaintResult.pending;
    return any ? UpscalePaintResult.upscaled : UpscalePaintResult.plain;
  }

  /// The cached or freshly rendered band, and whether it was put off to a
  /// later frame.
  (ui.Image?, bool) _bandFor(ui.Image image, ui.Rect src, UpscalePlan plan, UpscaleBand band, double sharpness) {
    final key = _BandKey(image, src, plan.width, plan.height, band.top, band.height, _quantize(sharpness));
    final cached = _cache.get(key);
    if (cached != null) return (cached, false);
    if (_rendersThisFrame >= maxRendersPerFrame) return (null, true);
    final bytes = plan.bytesFor(band.height);
    if (!_cache.reserve(bytes)) return (null, false);
    try {
      final rendered = _render(image, src, plan, band, key.sharpness / _sharpnessSteps);
      _rendersThisFrame++;
      if (!_cache.put(key, rendered, bytes)) {
        rendered.dispose();
        return (null, false);
      }
      return (rendered, false);
    } catch (e) {
      debugPrint('Upscaler: band render failed ($e)');
      return (null, false);
    }
  }

  static const int _sharpnessSteps = 20;

  static int _quantize(double sharpness) =>
      sharpness.isNaN ? 0 : (sharpness.clamp(0.0, 1.0) * _sharpnessSteps).round();

  /// Runs both passes for one band. The first pass renders one extra row
  /// above and below (where the output continues) so that the sharpening
  /// pass sees real neighbours across band borders and leaves no seam.
  ui.Image _render(ui.Image source, ui.Rect src, UpscalePlan plan, UpscaleBand band, double sharpness) {
    final sharpen = sharpness > 0;
    final padTop = sharpen && band.top > 0 ? 1 : 0;
    final padBottom = sharpen && band.bottom < plan.height ? 1 : 0;
    final rows = band.height + padTop + padBottom;
    // Uniform order follows the declarations in manga_upscale.frag.
    _upscale
      ..setFloat(0, source.width.toDouble())
      ..setFloat(1, source.height.toDouble())
      ..setFloat(2, src.left)
      ..setFloat(3, src.top)
      ..setFloat(4, src.width / plan.width)
      ..setFloat(5, src.height / plan.height)
      ..setFloat(6, 0)
      ..setFloat(7, (band.top - padTop).toDouble())
      ..setImageSampler(0, source);
    final scaled = _draw(_upscale, plan.width, rows);
    if (!sharpen) return scaled;
    try {
      // Uniform order follows the declarations in manga_sharpen.frag.
      _sharpen
        ..setFloat(0, plan.width.toDouble())
        ..setFloat(1, rows.toDouble())
        ..setFloat(2, 0)
        ..setFloat(3, padTop.toDouble())
        ..setFloat(4, sharpness)
        ..setImageSampler(0, scaled);
      return _draw(_sharpen, plan.width, band.height);
    } finally {
      scaled.dispose();
    }
  }

  static ui.Image _draw(ui.FragmentShader shader, int width, int height) {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()
        ..shader = shader
        ..blendMode = ui.BlendMode.src,
    );
    final picture = recorder.endRecording();
    try {
      return picture.toImageSync(width, height);
    } finally {
      picture.dispose();
    }
  }
}

/// Identifies one rendered band. Images compare by identity.
@immutable
class _BandKey {
  const _BandKey(this.image, this.src, this.width, this.height, this.top, this.rows, this.sharpness);

  final ui.Image image;
  final ui.Rect src;
  final int width;
  final int height;
  final int top;
  final int rows;
  final int sharpness;

  @override
  bool operator ==(Object other) =>
      other is _BandKey &&
      identical(other.image, image) &&
      other.src == src &&
      other.width == width &&
      other.height == height &&
      other.top == top &&
      other.rows == rows &&
      other.sharpness == sharpness;

  @override
  int get hashCode => Object.hash(identityHashCode(image), src, width, height, top, rows, sharpness);
}
