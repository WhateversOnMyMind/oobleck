import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/ui/dimming.dart';

void main() {
  test('brightness scale goes below the backlight but never to black', () {
    expect(Dimming.percent(1), 100);
    expect(Dimming.percent(Dimming.darkest), 1);
    expect(Dimming.percent(-5), 1, reason: 'clamped at the darkest level');
    expect(Dimming.backlight(0.4), 0.4);
    expect(Dimming.backlight(-0.5), 0, reason: 'below 0 the backlight stays at its lowest');
    expect(Dimming.shade(0.3), 0);
    expect(Dimming.shade(-0.5), closeTo(0.5, 1e-9));
    expect(Dimming.shade(-5), closeTo(0.9, 1e-9), reason: 'a tenth of the picture always shows');
  });

  testWidgets('the shade lets touches through and only shows below 0', (tester) async {
    var taps = 0;
    Widget app(double level) => MaterialApp(
          home: Stack(children: [
            GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => taps++, child: const SizedBox.expand()),
            DimShade(level: level),
          ]),
        );
    final inShade = find.descendant(of: find.byType(DimShade), matching: find.byType(ColoredBox));
    await tester.pumpWidget(app(0.5));
    expect(inShade, findsNothing);
    await tester.pumpWidget(app(-0.6));
    final box = tester.widget<ColoredBox>(inShade);
    expect(box.color.a, closeTo(0.6, 0.01));
    await tester.tapAt(const Offset(10, 10));
    expect(taps, 1);
  });
}
