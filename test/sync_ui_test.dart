import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/app/providers.dart';
import 'package:oobleck/app/theme.dart';
import 'package:oobleck/core/storage/app_db.dart';
import 'package:oobleck/features/sync/sync_section.dart';

void main() {
  late AppDb db;
  late Directory dir;

  Future<void> pump(WidgetTester tester, {Size size = const Size(400, 800)}) async {
    await tester.runAsync(() async {
      dir = Directory.systemTemp.createTempSync('oobleck_sync_ui');
      db = await AppDb.open(dir.path);
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db), supportDirProvider.overrideWithValue(dir.path)],
      child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: SingleChildScrollView(child: SyncSettingsSection()))),
    ));
    await tester.pump();
  }

  Future<void> cleanUp(WidgetTester tester) => tester.runAsync(() async {
        await db.close();
        dir.deleteSync(recursive: true);
      });

  testWidgets('signed out: Sign in opens the form; mistakes are explained before anything is sent', (tester) async {
    await pump(tester);
    expect(find.text('Sync watch history'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'User ID'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password again'), findsNothing);
    // No server compiled in for tests, so the address field is shown.
    expect(find.widgetWithText(TextField, 'Sync server'), findsOneWidget);

    await tester.tap(find.text('Create account').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Password again'), findsOneWidget);
    expect(find.textContaining('no password reset'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Sync server'), 'https://oobleck-sync.example.workers.dev');
    await tester.enterText(find.widgetWithText(TextField, 'User ID'), 'asuka');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'longenough');
    await tester.enterText(find.widgetWithText(TextField, 'Password again'), 'different!');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text("Passwords don't match."), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await cleanUp(tester);
  });

  testWidgets('signed in: shows the account, Sync now and Sign out without overflow on a narrow phone', (tester) async {
    await tester.runAsync(() async {
      final d = Directory.systemTemp.createTempSync('oobleck_sync_ui_pre');
      final pre = await AppDb.open(d.path);
      await pre.setMisc(AppDb.syncTokenKey, 'f' * 64);
      await pre.setMisc('sync:user', 'shinji');
      await pre.close();
      dir = d;
    });
    await tester.runAsync(() async => db = await AppDb.open(dir.path));
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db), supportDirProvider.overrideWithValue(dir.path)],
      child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: SingleChildScrollView(child: SyncSettingsSection()))),
    ));
    await tester.pump();
    expect(find.text('Signed in as shinji'), findsOneWidget);
    expect(find.text('Not synced yet'), findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await cleanUp(tester);
  });
}
