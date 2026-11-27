import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'upscale_plan.dart';
import 'upscaler.dart';

/// Where [UpscaledRawImage] reads from and draws to.
class UpscaleLayout {
  const UpscaleLayout(this.src, this.dst);

  /// Region of the image, in image pixels.
  final Rect src;

  /// Where it lands inside the box, in logical pixels.
  final Rect dst;

  /// Same placement as `paintImage` / `RawImage` for [fit] and [alignment].
  static UpscaleLayout resolve({
    required Size image,
    required Rect box,
    BoxFit fit = BoxFit.contain,
    Alignment alignment = Alignment.center,
  }) {
    final fitted = applyBoxFit(fit, image, box.size);
    return UpscaleLayout(
      alignment.inscribe(fitted.source, Offset.zero & image),
      alignment.inscribe(fitted.destination, box),
    );
  }

  /// The span of [dst] (top, bottom, in its own coordinates) that lies within
  /// [margin] of a viewport covering 0..[viewportHeight] in global
  /// coordinates, given where the top and bottom edges of [dst] are globally.
  ///
  /// Returns null when the image is entirely outside that span, and the
  /// whole of [dst] when the global positions are unusable.
  static (double, double)? visibleSpan({
    required Rect dst,
    required double globalTop,
    required double globalBottom,
    required double viewportHeight,
    double margin = 0,
  }) {
    final extent = globalBottom - globalTop;
    if (!extent.isFinite || extent <= 0 || !viewportHeight.isFinite || viewportHeight <= 0) {
      return (dst.top, dst.bottom);
    }
    final k = dst.height / extent;
    final top = dst.top + (-margin - globalTop) * k;
    final bottom = dst.top + (viewportHeight + margin - globalTop) * k;
    if (bottom <= dst.top || top >= dst.bottom) return null;
    return (top.clamp(dst.top, dst.bottom), bottom.clamp(dst.top, dst.bottom));
  }
}

/// Shows [image] like [RawImage], but sharpens it with the GPU upscaler when
/// it is drawn larger than its native size.
///
/// Upscaling runs only when [enabled], the shaders loaded, and the image
/// covers more than about 1.1 times its own pixels on screen. In every other
/// case, and on any error, it draws exactly like `RawImage` with
/// [fallbackQuality].
///
/// The image may be far taller than the screen (a webtoon strip): it is
/// upscaled in bands and only around the visible part. The widget does not
/// take ownership of [image].
class UpscaledRawImage extends StatefulWidget {
  const UpscaledRawImage({
    super.key,
    required this.image,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.enabled = true,
    this.sharpness = 0.5,
    this.fallbackQuality = FilterQuality.medium,
  });

  final ui.Image image;
  final BoxFit fit;
  final Alignment alignment;
  final bool enabled;

  /// 0 (edge-adaptive scaling only) to 1 (strongest sharpening).
  final double sharpness;
  final FilterQuality fallbackQuality;

  @override
  State<UpscaledRawImage> createState() => _UpscaledRawImageState();
}

class _UpscaledRawImageState extends State<UpscaledRawImage> with WidgetsBindingObserver {
  Upscaler? _upscaler = Upscaler.loaded;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_upscaler == null && widget.enabled) _load();
  }

  @override
  void didUpdateWidget(UpscaledRawImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.image, widget.image)) _upscaler?.evict(oldWidget.image);
    if (_upscaler == null && widget.enabled) _load();
  }

  void _load() {
    Upscaler.load().then((upscaler) {
      if (mounted && upscaler != null && _upscaler == null) setState(() => _upscaler = upscaler);
    });
  }

  @override
  void didHaveMemoryPressure() => _upscaler?.clearCache();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _upscaler?.evict(widget.image);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _UpscaledImageBox(
      image: widget.image,
      fit: widget.fit,
      alignment: widget.alignment,
      upscaler: widget.enabled ? _upscaler : null,
      sharpness: widget.sharpness,
      fallbackQuality: widget.fallbackQuality,
      devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? View.of(context).devicePixelRatio,
      scroll: Scrollable.maybeOf(context)?.position,
    );
  }
}

class _UpscaledImageBox extends LeafRenderObjectWidget {
  const _UpscaledImageBox({
    required this.image,
    required this.fit,
    required this.alignment,
    required this.upscaler,
    required this.sharpness,
    required this.fallbackQuality,
    required this.devicePixelRatio,
    required this.scroll,
  });

  final ui.Image image;
  final BoxFit fit;
  final Alignment alignment;
  final Upscaler? upscaler;
  final double sharpness;
  final FilterQuality fallbackQuality;
  final double devicePixelRatio;
  final Listenable? scroll;

  @override
  RenderUpscaledImage createRenderObject(BuildContext context) => RenderUpscaledImage(
    image: image,
    fit: fit,
    alignment: alignment,
    upscaler: upscaler,
    sharpness: sharpness,
    fallbackQuality: fallbackQuality,
    devicePixelRatio: devicePixelRatio,
    scroll: scroll,
  );

  @override
  void updateRenderObject(BuildContext context, RenderUpscaledImage renderObject) {
    renderObject
      ..image = image
      ..fit = fit
      ..alignment = alignment
      ..upscaler = upscaler
      ..sharpness = sharpness
      ..fallbackQuality = fallbackQuality
      ..devicePixelRatio = devicePixelRatio
      ..scroll = scroll;
  }
}

/// Render object behind [UpscaledRawImage]. Sizes itself like `RenderImage`.
class RenderUpscaledImage extends RenderBox {
  RenderUpscaledImage({
    required this._image,
    required this._fit,
    required this._alignment,
    required this._upscaler,
    required this._sharpness,
    required this._fallbackQuality,
    required this._devicePixelRatio,
    this._scroll,
  });

  /// Bands within this fraction of the viewport height beyond its edges are
  /// upscaled ahead of time.
  static const double preloadFraction = 0.5;

  ui.Image _image;
  set image(ui.Image value) {
    if (identical(value, _image)) return;
    final resized = value.width != _image.width || value.height != _image.height;
    _image = value;
    markNeedsPaint();
    if (resized) markNeedsLayout();
  }

  BoxFit _fit;
  set fit(BoxFit value) {
    if (value == _fit) return;
    _fit = value;
    markNeedsPaint();
  }

  Alignment _alignment;
  set alignment(Alignment value) {
    if (value == _alignment) return;
    _alignment = value;
    markNeedsPaint();
  }

  Upscaler? _upscaler;
  set upscaler(Upscaler? value) {
    if (identical(value, _upscaler)) return;
    _upscaler = value;
    _failed = false;
    markNeedsPaint();
  }

  double _sharpness;
  set sharpness(double value) {
    if (value == _sharpness) return;
    _sharpness = value;
    markNeedsPaint();
  }

  FilterQuality _fallbackQuality;
  set fallbackQuality(FilterQuality value) {
    if (value == _fallbackQuality) return;
    _fallbackQuality = value;
    markNeedsPaint();
  }

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  Listenable? _scroll;
  set scroll(Listenable? value) {
    if (identical(value, _scroll)) return;
    if (attached) _scroll?.removeListener(_onScroll);
    _scroll = value;
    if (attached) _scroll?.addListener(_onScroll);
  }

  /// What the last paint drew; exposed for tests.
  UpscalePaintResult lastResult = UpscalePaintResult.plain;

  /// Set after an unexpected error so that it is not retried every frame.
  bool _failed = false;
  bool _repaintScheduled = false;

  /// Whether the last paint found the image enlarged enough to upscale.
  bool _tracksScroll = false;

  // The layer of a scrolled child is moved without repainting it, so the set
  // of bands in view has to be refreshed from the scroll position.
  void _onScroll() {
    if (_tracksScroll) markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scroll?.addListener(_onScroll);
  }

  @override
  void detach() {
    _scroll?.removeListener(_onScroll);
    super.detach();
  }

  Size get _imageSize => Size(_image.width.toDouble(), _image.height.toDouble());

  Size _sizeFor(BoxConstraints constraints) => constraints.constrainSizeAndAttemptToPreserveAspectRatio(_imageSize);

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => _sizeFor(BoxConstraints.tightForFinite(height: height)).width;

  @override
  double computeMinIntrinsicHeight(double width) => 0;

  @override
  double computeMaxIntrinsicHeight(double width) => _sizeFor(BoxConstraints.tightForFinite(width: width)).height;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => _sizeFor(constraints);

  @override
  void performLayout() {
    size = _sizeFor(constraints);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;
    final upscaler = _upscaler;
    if (upscaler != null && !_failed) {
      try {
        lastResult = _paintUpscaled(context.canvas, offset, upscaler);
        if (lastResult == UpscalePaintResult.pending) _repaintNextFrame();
        return;
      } catch (e) {
        // Nothing has been drawn yet when planning throws; band failures are
        // handled inside the upscaler.
        _failed = true;
        debugPrint('UpscaledRawImage: falling back to plain drawing ($e)');
      }
    }
    lastResult = UpscalePaintResult.plain;
    _tracksScroll = false;
    paintImage(
      canvas: context.canvas,
      rect: offset & size,
      image: _image,
      fit: _fit,
      alignment: _alignment,
      filterQuality: _fallbackQuality,
    );
  }

  UpscalePaintResult _paintUpscaled(Canvas canvas, Offset offset, Upscaler upscaler) {
    final layout = UpscaleLayout.resolve(image: _imageSize, box: offset & size, fit: _fit, alignment: _alignment);
    _tracksScroll =
        UpscalePlan.compute(
          source: layout.src.size,
          destination: layout.dst.size,
          devicePixelRatio: _devicePixelRatio,
          limits: upscaler.limits,
        ) !=
        null;
    final local = layout.dst.shift(-offset);
    RenderObject root = this;
    while (root.parent != null) {
      root = root.parent!;
    }
    final viewportHeight = root is RenderView ? root.size.height : root.paintBounds.height;
    final span = UpscaleLayout.visibleSpan(
      dst: layout.dst,
      globalTop: localToGlobal(local.topLeft).dy,
      globalBottom: localToGlobal(local.bottomLeft).dy,
      viewportHeight: viewportHeight,
      margin: viewportHeight * preloadFraction,
    );
    return upscaler.paint(
      canvas,
      image: _image,
      src: layout.src,
      dst: layout.dst,
      devicePixelRatio: _devicePixelRatio,
      sharpness: _sharpness,
      // An empty span keeps everything plain while the image is off screen.
      visibleTop: span?.$1 ?? layout.dst.top,
      visibleBottom: span?.$2 ?? layout.dst.top,
      fallbackQuality: _fallbackQuality,
    );
  }

  void _repaintNextFrame() {
    if (_repaintScheduled) return;
    _repaintScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _repaintScheduled = false;
      if (attached) markNeedsPaint();
    });
  }
}
