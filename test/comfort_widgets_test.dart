import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/app/theme.dart';
import 'package:oobleck/ui/back_shortcuts.dart';
import 'package:oobleck/ui/feedback.dart';
import 'package:oobleck/ui/h_scroll_row.dart';
import 'package:oobleck/ui/layout.dart';
import 'package:oobleck/ui/widgets.dart';

void main() {
  Widget row() => MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: HScrollRow(
              height: 120,
              itemCount: 30,
              itemBuilder: (_, i) => SizedBox(width: 100, child: Center(child: Text('item $i'))),
            ),
          ),
        ),
      );

  ScrollPosition position(WidgetTester tester) => tester.state<ScrollableState>(find.byType(Scrollable)).position;

  testWidgets('horizontal row: arrows appear on mouse hover and page the row', (tester) async {
    await tester.pumpWidget(row());
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(400, 60));
    addTearDown(mouse.removePointer);
    await tester.pump();
    // At the start there is only somewhere to go forward.
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(position(tester).pixels, greaterThan(300));
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
    expect(position(tester).pixels, 0);
  });

  testWidgets('horizontal row: can be dragged with the mouse', (tester) async {
    await tester.pumpWidget(row());
    await tester.drag(find.text('item 3'), const Offset(-250, 0), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(position(tester).pixels, greaterThan(200));
  });

  testWidgets('poster card fits its computed height at very large text', (tester) async {
    for (final scale in [1.0, 1.5, 2.0, 3.0]) {
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Builder(
              builder: (context) => Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  height: posterCardHeight(context, 130, subtitle: true),
                  child: const PosterCard(width: 130, title: 'Frieren: Beyond Journey\'s End and then some more title', subtitle: '12 episodes · 3.4 GB'),
                ),
              ),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull, reason: 'text scale $scale');
    }
  });

  testWidgets('confirm dialog: returns the choice; Enter never confirms a destructive action', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await confirmAction(context, title: 'Delete it?', message: 'Gone for good.'),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Delete it?'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result, isFalse); // focus starts on Cancel

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('undo snackbar runs the undo action', (tester) async {
    var undone = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppSnackBar(context, 'Removed', onUndo: () => undone++),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Removed'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    expect(undone, 1);
  });

  testWidgets('Esc, Alt+Left and the mouse back button go back; nothing happens on the first screen', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      builder: (context, child) => BackShortcuts(navigatorKey: nav, child: child!),
      home: const Scaffold(body: Text('first')),
    ));

    Future<void> push() async {
      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('second'))));
      await tester.pumpAndSettle();
      expect(find.text('second'), findsOneWidget);
    }

    await push();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('second'), findsNothing);

    await push();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.text('second'), findsNothing);

    await push();
    final mouse = await tester.startGesture(const Offset(200, 200), kind: PointerDeviceKind.mouse, buttons: kBackMouseButton);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(find.text('second'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);
  });
}
