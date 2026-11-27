import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/features/player/tap_zones.dart';

void main() {
  test('zones: left 40 % back, right 40 % forward, middle play/pause', () {
    expect(zoneAt(10, 900), TapZone.back);
    expect(zoneAt(359, 900), TapZone.back);
    expect(zoneAt(450, 900), TapZone.middle);
    expect(zoneAt(541, 900), TapZone.forward);
    expect(zoneAt(890, 900), TapZone.forward);
  });

  testWidgets('double tap skips by the side it lands on, even after a single tap on the other side', (tester) async {
    tester.view.physicalSize = const Size(900, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final zones = <TapZone>[];
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TapZones(onTap: () => taps++, onDoubleTap: zones.add)),
    ));

    Future<void> doubleTap(Offset at) async {
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 400));
    }

    // A single tap on the right first (shows the controls), as on the phone.
    await tester.tapAt(const Offset(800, 200));
    // A single tap only counts once the double-tap window (300 ms) has passed.
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 1);

    await doubleTap(const Offset(100, 200));
    await doubleTap(const Offset(800, 200));
    await doubleTap(const Offset(100, 200));
    await doubleTap(const Offset(450, 200));
    expect(zones, [TapZone.back, TapZone.forward, TapZone.back, TapZone.middle]);
    expect(taps, 1, reason: 'double taps are not counted as single taps');
  });

  testWidgets('holding the right half speeds up until released; the left half and taps do not', (tester) async {
    tester.view.physicalSize = const Size(900, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final holds = <bool>[];
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: TapZones(onTap: () => taps++, onDoubleTap: (_) {}, onHoldRight: holds.add)),
    ));

    Future<void> hold(Offset at) async {
      final g = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 700));
      expect(holds.lastOrNull, at.dx > 450 ? isTrue : isNot(true), reason: 'while held at $at');
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await hold(const Offset(800, 200));
    expect(holds, [true, false]);
    await hold(const Offset(100, 200));
    expect(holds.where((h) => h), hasLength(1), reason: 'left half never speeds up');
    expect(holds.last, isFalse);
    expect(taps, 0, reason: 'a hold is not a tap');

    await tester.tapAt(const Offset(800, 200));
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 1);
    expect(holds.where((h) => h), hasLength(1), reason: 'a quick tap does not speed up');
  });
}
