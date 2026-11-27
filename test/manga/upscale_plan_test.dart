import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/core/manga/upscale/upscale_cache.dart';
import 'package:oobleck/core/manga/upscale/upscale_plan.dart';
import 'package:oobleck/core/manga/upscale/upscaled_image.dart';

void main() {
  group('UpscalePlan.compute', () {
    test('uses physical pixels of the destination', () {
      final plan = UpscalePlan.compute(
        source: const Size(690, 1000),
        destination: const Size(480, 695.65),
        devicePixelRatio: 3,
      )!;
      expect(plan.width, 1440);
      expect(plan.height, 2087);
      expect(plan.bandCount, 1);
    });

    test('skips images that are not enlarged enough', () {
      UpscalePlan? at(Size destination, {double dpr = 1}) =>
          UpscalePlan.compute(source: const Size(1000, 1500), destination: destination, devicePixelRatio: dpr);
      expect(at(const Size(1000, 1500)), isNull);
      expect(at(const Size(1090, 1635)), isNull);
      expect(at(const Size(1200, 1800)), isNotNull);
      expect(at(const Size(500, 750)), isNull);
      // Half the logical size on a 3x screen is still a 1.5x enlargement.
      expect(at(const Size(500, 750), dpr: 3), isNotNull);
      // Stretched one way but shrunk the other.
      expect(at(const Size(2000, 1400)), isNull);
    });

    test('rejects empty and non-finite sizes', () {
      UpscalePlan? p(Size s, Size d, double dpr) =>
          UpscalePlan.compute(source: s, destination: d, devicePixelRatio: dpr);
      expect(p(Size.zero, const Size(10, 10), 1), isNull);
      expect(p(const Size(10, 10), Size.zero, 1), isNull);
      expect(p(const Size(10, 10), const Size(double.infinity, 10), 1), isNull);
      expect(p(const Size(10, 10), const Size(100, 100), 0), isNull);
      expect(p(const Size(10, 10), const Size(100, 100), double.nan), isNull);
    });

    test('splits a webtoon strip into even bands within the limits', () {
      const limits = UpscaleLimits();
      final plan = UpscalePlan.compute(
        source: const Size(690, 15000),
        destination: const Size(1440, 31304),
        devicePixelRatio: 1,
      )!;
      expect(plan.width, 1440);
      expect(plan.height, 31304);
      expect(plan.bandCount, greaterThan(1));
      int next = 0;
      for (int i = 0; i < plan.bandCount; i++) {
        final band = plan.band(i);
        expect(band.top, next, reason: 'bands must tile without gaps');
        expect(band.height, greaterThan(0));
        expect(band.height, lessThanOrEqualTo(limits.maxDimension));
        expect(plan.width * band.height, lessThanOrEqualTo(limits.maxBandPixels));
        next = band.bottom;
      }
      expect(next, plan.height);
      // No thin leftover band at the end.
      expect(plan.band(plan.bandCount - 1).height, greaterThan(plan.bandHeight ~/ 2));
    });

    test('caps the width and keeps the aspect ratio', () {
      final plan = UpscalePlan.compute(
        source: const Size(1000, 500),
        destination: const Size(6000, 3000),
        devicePixelRatio: 1,
        limits: const UpscaleLimits(maxDimension: 2048),
      )!;
      expect(plan.width, 2048);
      expect(plan.height, 1024);
    });

    test('gives up when the width cap leaves nothing to gain', () {
      expect(
        UpscalePlan.compute(
          source: const Size(2000, 1000),
          destination: const Size(6000, 3000),
          devicePixelRatio: 1,
          limits: const UpscaleLimits(maxDimension: 2048),
        ),
        isNull,
      );
    });
  });

  group('UpscalePlan bands', () {
    final plan = UpscalePlan.compute(
      source: const Size(100, 1000),
      destination: const Size(200, 2000),
      devicePixelRatio: 1,
      limits: const UpscaleLimits(maxBandPixels: 200 * 500),
    )!;

    test('bandsBetween picks the overlapping bands', () {
      expect(plan.bandCount, 4);
      expect(plan.bandsBetween(0, 2000), (0, 3));
      expect(plan.bandsBetween(0, 500), (0, 0));
      expect(plan.bandsBetween(499, 501), (0, 1));
      expect(plan.bandsBetween(500, 1000), (1, 1));
      expect(plan.bandsBetween(-300, 20), (0, 0));
      expect(plan.bandsBetween(1990, 5000), (3, 3));
    });

    test('bandsBetween returns null outside the image', () {
      expect(plan.bandsBetween(-50, 0), isNull);
      expect(plan.bandsBetween(2000, 2500), isNull);
      expect(plan.bandsBetween(700, 700), isNull);
      expect(plan.bandsBetween(double.nan, 100), isNull);
    });

    test('slice maps rows to source and destination', () {
      expect(plan.slice(const Rect.fromLTWH(0, 0, 100, 1000), 500, 1000), const Rect.fromLTWH(0, 250, 100, 250));
      expect(plan.slice(const Rect.fromLTWH(10, 20, 400, 4000), 0, 500), const Rect.fromLTWH(10, 20, 400, 1000));
    });
  });

  group('UpscaleLayout', () {
    test('contain centres the whole image', () {
      final l = UpscaleLayout.resolve(image: const Size(100, 200), box: const Rect.fromLTWH(0, 0, 300, 300));
      expect(l.src, const Rect.fromLTWH(0, 0, 100, 200));
      expect(l.dst, const Rect.fromLTWH(75, 0, 150, 300));
    });

    test('cover crops the source by the alignment', () {
      final l = UpscaleLayout.resolve(
        image: const Size(100, 200),
        box: const Rect.fromLTWH(10, 10, 300, 300),
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
      );
      expect(l.src, const Rect.fromLTWH(0, 0, 100, 100));
      expect(l.dst, const Rect.fromLTWH(10, 10, 300, 300));
    });

    test('visibleSpan maps the viewport into the destination', () {
      const dst = Rect.fromLTWH(0, 0, 400, 8000);
      // Scrolled 3000 down in a 600 tall viewport.
      expect(UpscaleLayout.visibleSpan(dst: dst, globalTop: -3000, globalBottom: 5000, viewportHeight: 600), (
        3000.0,
        3600.0,
      ));
      expect(
        UpscaleLayout.visibleSpan(dst: dst, globalTop: -3000, globalBottom: 5000, viewportHeight: 600, margin: 300),
        (2700.0, 3900.0),
      );
      // Clamped at the ends.
      expect(
        UpscaleLayout.visibleSpan(dst: dst, globalTop: 100, globalBottom: 8100, viewportHeight: 600, margin: 300),
        (0.0, 800.0),
      );
    });

    test('visibleSpan accounts for an ancestor scale and an offset rect', () {
      const dst = Rect.fromLTWH(0, 50, 400, 1000);
      // Drawn at twice the size: 2000 global pixels tall.
      expect(UpscaleLayout.visibleSpan(dst: dst, globalTop: -1000, globalBottom: 1000, viewportHeight: 600), (
        550.0,
        850.0,
      ));
    });

    test('visibleSpan is null off screen and everything when unknown', () {
      const dst = Rect.fromLTWH(0, 0, 400, 800);
      expect(UpscaleLayout.visibleSpan(dst: dst, globalTop: 700, globalBottom: 1500, viewportHeight: 600), isNull);
      expect(UpscaleLayout.visibleSpan(dst: dst, globalTop: -900, globalBottom: -100, viewportHeight: 600), isNull);
      expect(UpscaleLayout.visibleSpan(dst: dst, globalTop: double.nan, globalBottom: 10, viewportHeight: 600), (
        0.0,
        800.0,
      ));
      expect(UpscaleLayout.visibleSpan(dst: dst, globalTop: 5, globalBottom: 5, viewportHeight: 600), (0.0, 800.0));
    });
  });

  group('LruByteCache', () {
    late List<String> evicted;
    late LruByteCache<String, String> cache;

    setUp(() {
      evicted = [];
      cache = LruByteCache<String, String>(maxBytes: 100, onEvict: evicted.add);
    });

    test('evicts the least recently used entry first', () {
      cache.put('a', 'A', 40);
      cache.put('b', 'B', 40);
      cache.tick++;
      expect(cache.get('a'), 'A');
      cache.tick++;
      expect(cache.put('c', 'C', 40), isTrue);
      expect(evicted, ['B']);
      expect(cache.bytes, 80);
      expect(cache.containsKey('a'), isTrue);
    });

    test('never evicts entries used in the current tick', () {
      cache.put('a', 'A', 60);
      expect(cache.put('b', 'B', 60), isFalse);
      expect(evicted, isEmpty);
      expect(cache.get('a'), 'A');
      expect(cache.bytes, 60);
      cache.tick++;
      expect(cache.put('b', 'B', 60), isTrue);
      expect(evicted, ['A']);
    });

    test('a failed reservation evicts nothing', () {
      cache.put('a', 'A', 30);
      cache.tick++;
      cache.put('b', 'B', 60);
      // Only "a" is evictable, which is not enough for 50 more bytes.
      expect(cache.reserve(50), isFalse);
      expect(evicted, isEmpty);
      expect(cache.length, 2);
    });

    test('rejects values larger than the whole budget', () {
      expect(cache.put('big', 'BIG', 101), isFalse);
      expect(cache.length, 0);
    });

    test('replacing a key releases the old value', () {
      cache.put('a', 'A1', 30);
      cache.put('a', 'A2', 50);
      expect(evicted, ['A1']);
      expect(cache.bytes, 50);
    });

    test('removeWhere, clear and shrinking the budget release values', () {
      cache.put('a1', 'A1', 10);
      cache.put('a2', 'A2', 10);
      cache.put('b', 'B', 10);
      cache.put('c', 'C', 10);
      cache.removeWhere((k) => k.startsWith('a'));
      expect(evicted, ['A1', 'A2']);
      cache.tick++;
      cache.maxBytes = 10;
      expect(evicted, ['A1', 'A2', 'B']);
      cache.clear();
      expect(evicted, ['A1', 'A2', 'B', 'C']);
      expect(cache.bytes, 0);
    });
  });
}
