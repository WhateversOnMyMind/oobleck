import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/core/manga/upscale/upscaled_image.dart';
import 'package:oobleck/core/manga/upscale/upscaler.dart';

import '../helpers/test_images.dart';

/// Red channel of row [y] of a [width] wide RGBA buffer.
List<int> rowOf(Uint8List px, int width, int y) => [for (int x = 0; x < width; x++) px[(y * width + x) * 4]];

/// Number of pixels that are neither (nearly) black nor (nearly) white.
int transitionWidth(List<int> row) => row.where((v) => v > 8 && v < 247).length;

void expectMonotonic(List<int> row) {
  for (int x = 1; x < row.length; x++) {
    expect(row[x], greaterThanOrEqualTo(row[x - 1]), reason: 'ringing at x=$x in $row');
  }
}

/// A deterministic busy pattern: stripes, a diagonal and some noise.
int pattern(int x, int y) {
  final noise = ((x * 73856093) ^ (y * 19349663)) & 0x3f;
  final stripe = (x ~/ 3 + y ~/ 5).isEven ? 40 : 200;
  final v = x == y ~/ 2 ? 0 : stripe + noise - 32;
  return (v.clamp(0, 255) << 16) | ((255 - v).clamp(0, 255) << 8) | ((v * 2) & 0xff);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shaders', () {
    late Upscaler upscaler;

    setUpAll(() async {
      final loaded = await Upscaler.load();
      expect(loaded, isNotNull, reason: 'fragment shaders did not load');
      upscaler = loaded!;
    });

    tearDown(() {
      upscaler
        ..clearCache()
        ..limits = const UpscaleLimits()
        ..maxRendersPerFrame = 2
        ..debugNextFrame();
    });

    test('load is cached', () async {
      expect(await Upscaler.load(), same(upscaler));
      expect(Upscaler.loaded, same(upscaler));
    });

    test('output has the requested size and keeps flat colours', () async {
      final src = await imageFromPixels(12, 20, (x, y) => 0x336699);
      final out = upscaler.upscale(src, target: const ui.Size(30, 50))!;
      expect(out.width, 30);
      expect(out.height, 50);
      final px = await pixelsOf(out);
      for (int i = 0; i < px.length; i += 4) {
        expect(px[i], closeTo(0x33, 1));
        expect(px[i + 1], closeTo(0x66, 1));
        expect(px[i + 2], closeTo(0x99, 1));
        expect(px[i + 3], 255);
      }
    });

    test('refuses targets that are not an enlargement or too large', () async {
      final src = await imageFromPixels(16, 16, (x, y) => 0);
      expect(upscaler.upscale(src, target: const ui.Size(16, 16)), isNull);
      expect(upscaler.upscale(src, target: const ui.Size(8, 8)), isNull);
      expect(upscaler.upscale(src, target: const ui.Size(5000, 5000)), isNull);
    });

    test('a black/white edge stays sharp and does not ring', () async {
      final src = await imageFromPixels(16, 16, (x, y) => grey(x < 8 ? 0 : 255));
      final widths = <double, int>{};
      for (final sharpness in [0.0, 0.5, 1.0]) {
        final out = upscaler.upscale(src, target: const ui.Size(64, 64), sharpness: sharpness)!;
        final px = await pixelsOf(out);
        for (final y in [0, 17, 32, 63]) {
          final row = rowOf(px, 64, y);
          expectMonotonic(row);
          expect(row.sublist(0, 29), everyElement(0), reason: 'dark side at sharpness $sharpness');
          expect(row.sublist(35), everyElement(255), reason: 'light side at sharpness $sharpness');
          // Bilinear filtering smears this edge over four pixels.
          expect(transitionWidth(row), lessThanOrEqualTo(3));
        }
        final mid = rowOf(px, 64, 32);
        widths[sharpness] = mid[32] - mid[31];
      }
      // More sharpening makes the step across the edge steeper.
      expect(widths[0.5], greaterThan(widths[0.0]!));
      expect(widths[1.0], greaterThan(widths[0.5]!));
    });

    test('a diagonal line is smoothed instead of stair-stepped', () async {
      final src = await imageFromPixels(16, 16, (x, y) => grey(x < y ? 0 : 255));
      final out = upscaler.upscale(src, target: const ui.Size(48, 48))!;
      final px = await pixelsOf(out);
      // Each output row crosses the edge one pixel further right. Nearest or
      // bilinear scaling would repeat the same position for three rows.
      int crossing(int y) => rowOf(px, 48, y).indexWhere((v) => v >= 128);
      for (int y = 10; y < 38; y++) {
        expect(crossing(y + 1) - crossing(y), 1, reason: 'row $y');
      }
    });

    test('sharpening never leaves the range of a soft edge', () async {
      final src = await imageFromPixels(16, 16, (x, y) => grey((64 + (x - 4) * 16).clamp(64, 192)));
      final out = upscaler.upscale(src, target: const ui.Size(40, 40), sharpness: 1)!;
      final px = await pixelsOf(out);
      for (int i = 0; i < px.length; i += 4) {
        expect(px[i], inInclusiveRange(63, 193));
      }
      expectMonotonic(rowOf(px, 40, 20));
    });

    test('banded painting matches a single pass exactly', () async {
      final src = await imageFromPixels(24, 40, pattern);
      final whole = await pixelsOf(upscaler.upscale(src, target: const ui.Size(60, 100), sharpness: 0.8)!);

      upscaler
        ..limits = const UpscaleLimits(maxBandPixels: 60 * 16)
        ..maxRendersPerFrame = 100;
      final recorder = ui.PictureRecorder();
      final result = upscaler.paint(
        ui.Canvas(recorder),
        image: src,
        src: const ui.Rect.fromLTWH(0, 0, 24, 40),
        dst: const ui.Rect.fromLTWH(0, 0, 60, 100),
        devicePixelRatio: 1,
        sharpness: 0.8,
      );
      expect(result, UpscalePaintResult.upscaled);
      expect(upscaler.cacheBytes, 60 * 100 * 4);
      final banded = await pixelsOf(recorder.endRecording().toImageSync(60, 100));

      int worst = 0;
      for (int i = 0; i < whole.length; i++) {
        final d = (whole[i] - banded[i]).abs();
        if (d > worst) worst = d;
      }
      expect(worst, lessThanOrEqualTo(1), reason: 'seam between bands');
    });

    test('only bands in view are rendered, a few per frame', () async {
      final src = await imageFromPixels(20, 200, pattern);
      upscaler.limits = const UpscaleLimits(maxBandPixels: 40 * 50);
      UpscalePaintResult paint(double top, double bottom) => upscaler.paint(
        ui.Canvas(ui.PictureRecorder()),
        image: src,
        src: const ui.Rect.fromLTWH(0, 0, 20, 200),
        dst: const ui.Rect.fromLTWH(0, 0, 40, 400),
        devicePixelRatio: 1,
        visibleTop: top,
        visibleBottom: bottom,
      );
      const band = 40 * 50 * 4;

      expect(paint(60, 90), UpscalePaintResult.upscaled);
      expect(upscaler.cacheBytes, band);
      // Same band again: served from the cache.
      expect(paint(55, 95), UpscalePaintResult.upscaled);
      expect(upscaler.cacheBytes, band);

      // Four more bands come into view but only two may render per frame.
      upscaler.debugNextFrame();
      expect(paint(100, 300), UpscalePaintResult.pending);
      expect(upscaler.cacheBytes, 3 * band);
      upscaler.debugNextFrame();
      expect(paint(100, 300), UpscalePaintResult.upscaled);
      expect(upscaler.cacheBytes, 5 * band);

      // Nothing in view: plain drawing, nothing new rendered.
      expect(paint(0, 0), UpscalePaintResult.plain);
      expect(upscaler.cacheBytes, 5 * band);

      upscaler.evict(src);
      expect(upscaler.cacheBytes, 0);
    });

    test('the cache budget bounds memory and falls back when full', () async {
      final src = await imageFromPixels(20, 200, pattern);
      const band = 40 * 50 * 4;
      final previous = upscaler.cacheMaxBytes;
      addTearDown(() => upscaler.cacheMaxBytes = previous);
      upscaler
        ..limits = const UpscaleLimits(maxBandPixels: 40 * 50)
        ..maxRendersPerFrame = 100
        ..cacheMaxBytes = 2 * band;
      UpscalePaintResult paint(double top, double bottom) => upscaler.paint(
        ui.Canvas(ui.PictureRecorder()),
        image: src,
        src: const ui.Rect.fromLTWH(0, 0, 20, 200),
        dst: const ui.Rect.fromLTWH(0, 0, 40, 400),
        devicePixelRatio: 1,
        visibleTop: top,
        visibleBottom: bottom,
      );
      // Three bands in view but room for two: the third is drawn plain.
      expect(paint(0, 150), UpscalePaintResult.upscaled);
      expect(upscaler.cacheBytes, 2 * band);
      // Later frames elsewhere evict the old bands.
      upscaler.debugNextFrame();
      expect(paint(300, 400), UpscalePaintResult.upscaled);
      expect(upscaler.cacheBytes, 2 * band);
    });
  });

  group('UpscaledRawImage', () {
    late Upscaler upscaler;

    Future<ui.Image> makeImage(WidgetTester tester, int w, int h, int Function(int, int) rgb) async =>
        (await tester.runAsync(() => imageFromPixels(w, h, rgb)))!;

    Future<void> ensureLoaded(WidgetTester tester) async {
      upscaler = (await tester.runAsync<Upscaler?>(Upscaler.load))!;
      addTearDown(() {
        upscaler
          ..clearCache()
          ..limits = const UpscaleLimits()
          ..maxRendersPerFrame = 2;
      });
    }

    /// An 800x600 window at one physical pixel per logical pixel.
    void useSmallView(WidgetTester tester) {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(800, 600);
      addTearDown(tester.view.reset);
    }

    RenderUpscaledImage renderOf(WidgetTester tester) =>
        tester.renderObject<RenderUpscaledImage>(find.byType(UpscaledRawImage));

    Widget app(Widget child) => Directionality(textDirection: TextDirection.ltr, child: child);

    testWidgets('lays out like RawImage', (tester) async {
      await ensureLoaded(tester);
      useSmallView(tester);
      final image = await makeImage(tester, 50, 100, (x, y) => 0);
      for (final wrap in <Widget Function(Widget)>[
        (w) => Center(child: w),
        (w) => SizedBox(width: 300, height: 300, child: w),
        (w) => SingleChildScrollView(child: w),
        (w) => Align(alignment: Alignment.topLeft, child: SizedBox(width: 20, child: w)),
        (w) => Center(child: IntrinsicWidth(child: w)),
      ]) {
        await tester.pumpWidget(app(wrap(RawImage(image: image, fit: BoxFit.contain))));
        final expected = tester.getSize(find.byType(RawImage));
        await tester.pumpWidget(app(wrap(UpscaledRawImage(image: image))));
        expect(tester.getSize(find.byType(UpscaledRawImage)), expected);
      }
    });

    testWidgets('upscales only when enlarged and enabled', (tester) async {
      await ensureLoaded(tester);
      useSmallView(tester);
      final image = await makeImage(tester, 50, 50, (x, y) => grey(x < 25 ? 0 : 255));

      Widget sized(double side, {bool enabled = true}) => app(
        Center(
          child: SizedBox(
            width: side,
            height: side,
            child: UpscaledRawImage(image: image, enabled: enabled),
          ),
        ),
      );

      await tester.pumpWidget(sized(200));
      expect(renderOf(tester).lastResult, UpscalePaintResult.upscaled);
      expect(upscaler.cacheBytes, 200 * 200 * 4);

      await tester.pumpWidget(sized(200, enabled: false));
      expect(renderOf(tester).lastResult, UpscalePaintResult.plain);

      await tester.pumpWidget(sized(52));
      expect(renderOf(tester).lastResult, UpscalePaintResult.plain);

      // A denser screen turns the same layout into an enlargement.
      tester.view.devicePixelRatio = 3;
      await tester.pumpWidget(sized(52));
      await tester.pump();
      expect(renderOf(tester).lastResult, UpscalePaintResult.upscaled);

      // Removing the widget releases its bands.
      await tester.pumpWidget(app(const SizedBox()));
      expect(upscaler.cacheBytes, 0);
    });

    testWidgets('draws the upscaled pixels where RawImage would', (tester) async {
      await ensureLoaded(tester);
      useSmallView(tester);
      final image = await makeImage(tester, 16, 16, (x, y) => grey(x < 8 ? 0 : 255));
      final key = GlobalKey();

      Future<List<int>> middleRow(Widget child) async {
        await tester.pumpWidget(
          app(
            Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(width: 64, height: 64, child: child),
              ),
            ),
          ),
        );
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final px = (await tester.runAsync(() async => pixelsOf(await boundary.toImage())))!;
        return rowOf(px, 64, 32);
      }

      final plain = await middleRow(RawImage(image: image, fit: BoxFit.contain, filterQuality: FilterQuality.medium));
      final sharp = await middleRow(UpscaledRawImage(image: image));
      expect(renderOf(tester).lastResult, UpscalePaintResult.upscaled);
      expectMonotonic(sharp);
      expect(sharp.first, 0);
      expect(sharp.last, 255);
      expect(transitionWidth(sharp), lessThan(transitionWidth(plain)));
      expect(transitionWidth(sharp), lessThanOrEqualTo(2));
    });

    testWidgets('a long strip is upscaled around the viewport as it scrolls', (tester) async {
      await ensureLoaded(tester);
      useSmallView(tester);
      // 800x600 viewport; the strip is drawn 400 wide and 12000 tall.
      final image = await makeImage(tester, 100, 3000, pattern);
      upscaler.limits = const UpscaleLimits(maxBandPixels: 400 * 500);
      const band = 400 * 500 * 4;
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        app(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              child: SingleChildScrollView(controller: controller, child: UpscaledRawImage(image: image)),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(UpscaledRawImage)), const Size(400, 12000));
      // Rows 0..900 (viewport plus half a viewport ahead): two bands.
      expect(renderOf(tester).lastResult, UpscalePaintResult.upscaled);
      expect(upscaler.cacheBytes, 2 * band);

      // Rows 4700..5900 touch three new bands; two render per frame.
      controller.jumpTo(5000);
      await tester.pump();
      expect(renderOf(tester).lastResult, UpscalePaintResult.pending);
      expect(upscaler.cacheBytes, 4 * band);
      await tester.pump();
      expect(renderOf(tester).lastResult, UpscalePaintResult.upscaled);
      expect(upscaler.cacheBytes, 5 * band);

      // Settled: further frames render nothing new.
      await tester.pump();
      expect(upscaler.cacheBytes, 5 * band);
    });
  });
}
