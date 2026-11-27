import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/app/theme.dart';
import 'package:oobleck/features/player/lock_overlay.dart';

void main() {
  testWidgets('player lock: touches only bring up Unlock, and only Unlock unlocks', (tester) async {
    var unlocked = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(body: LockOverlay(onUnlock: () => unlocked++)),
    ));
    // Shown when the lock starts, then it gets out of the way.
    expect(find.text('Unlock'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock'), warnIfMissed: false);
    expect(unlocked, 0);

    await tester.tapAt(const Offset(400, 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unlock'));
    expect(unlocked, 1);
    // Let the hide timer finish.
    await tester.pump(const Duration(seconds: 4));
  });
}
