import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/app/providers.dart';
import 'package:oobleck/app/theme.dart';
import 'package:oobleck/core/storage/app_db.dart';
import 'package:oobleck/features/library/library_screen.dart';

void main() {
  testWidgets('empty library shows a friendly empty state', (tester) async {
    late AppDb db;
    late Directory dir;
    await tester.runAsync(() async {
      dir = Directory.systemTemp.createTempSync('oobleck_w');
      db = await AppDb.open(dir.path);
    });
    await tester.pumpWidget(ProviderScope(
      overrides: [dbProvider.overrideWithValue(db), supportDirProvider.overrideWithValue(dir.path)],
      child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: LibraryScreen())),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Your library is empty'), findsOneWidget);
    await tester.runAsync(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });
  });
}
