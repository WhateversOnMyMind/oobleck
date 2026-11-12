import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/app/providers.dart';
import 'package:oobleck/app/shell.dart';
import 'package:oobleck/app/strings.dart';
import 'package:oobleck/app/theme.dart';
import 'package:oobleck/core/models.dart';
import 'package:oobleck/core/storage/app_db.dart';
import 'package:oobleck/core/sync/sync_api.dart';
import 'package:oobleck/features/home/home_screen.dart';
import 'package:oobleck/features/library/library_screen.dart';
import 'package:oobleck/features/settings/language_screen.dart';
import 'package:oobleck/features/settings/settings_screen.dart';

/// Mirrors OobleckApp's MaterialApp (locale + first-launch picker) without
/// starting downloads or sync.
class _TestApp extends ConsumerWidget {
  const _TestApp({this.home});
  final Widget? home;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(settingsProvider.select((s) => s.language));
    return MaterialApp(
      theme: buildTheme(),
      locale: Strings.forCode(language).locale,
      supportedLocales: const [Locale('en'), Locale('ko')],
      localizationsDelegates: const [
        StringsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: language == null ? const LanguageScreen() : (home ?? const Scaffold(body: LibraryScreen())),
    );
  }
}

// Home shows animated skeletons while loading, so it never "settles".
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Taps something that saves a setting. The tap runs in real time so Hive's
/// file write completes normally (a write started under the test's fake clock
/// never finishes and would hang closing the database).
Future<void> tapAndSave(WidgetTester tester, Finder f) async {
  await tester.runAsync(() async {
    await tester.tap(f);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await settle(tester);
}

void main() {
  late AppDb db;
  late Directory dir;

  Future<void> open(WidgetTester tester) async {
    await tester.runAsync(() async {
      dir = Directory.systemTemp.createTempSync('oobleck_lang');
      db = await AppDb.open(dir.path);
    });
  }

  // Inside the test body: unmount (stops DB watchers), then close for real.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });
  }

  Future<void> pump(WidgetTester tester, {Widget? home}) async {
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        dbProvider.overrideWithValue(db),
        supportDirProvider.overrideWithValue(dir.path),
        // No network in tests.
        homeProvider.overrideWith((ref) async => const <String, List<ShowSummary>>{}),
      ],
      child: _TestApp(home: home),
    ));
    await settle(tester);
  }

  testWidgets('first launch asks for the language once and remembers it', (tester) async {
    await open(tester);
    await pump(tester);
    expect(find.byType(LanguageScreen), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('한국어'), findsOneWidget);

    await tester.tap(find.text('한국어'));
    await settle(tester);
    // The screen previews the highlighted language.
    expect(find.text('언어를 선택하세요'), findsOneWidget);
    await tapAndSave(tester, find.text('계속'));

    expect(find.byType(LanguageScreen), findsNothing);
    expect(find.text('아직 다운로드한 작품이 없어요'), findsOneWidget);
    expect(db.setting<String>('language'), 'ko');

    // Next launch: straight to the app, still in Korean.
    await pump(tester);
    expect(find.byType(LanguageScreen), findsNothing);
    expect(find.text('아직 다운로드한 작품이 없어요'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('Korean UI: navigation, Home and Settings, and switching back to English in Settings', (tester) async {
    await open(tester);
    await tester.runAsync(() => db.setSetting('language', 'ko'));
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pump(tester, home: const Shell());
    for (final label in ['홈', '검색', '다운로드', '설정']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('로그인'), findsOneWidget); // top-right sign in

    await tester.tap(find.text('설정').first);
    await settle(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('앱 언어'), findsOneWidget);
    expect(find.text('기본 오디오'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('앱 언어'));
    await settle(tester);
    // The picker offers both languages.
    expect(find.text('English'), findsOneWidget);
    expect(find.text('한국어'), findsWidgets);
    Navigator.of(tester.element(find.text('English'))).pop();
    await settle(tester);
    // Same call the picker makes, run in real time so the write completes.
    final container = ProviderScope.containerOf(tester.element(find.byType(SettingsScreen)));
    await tester.runAsync(() => container.read(settingsProvider.notifier).set('language', 'en'));
    await settle(tester);
    expect(find.text('App language'), findsOneWidget);
    expect(find.text('Settings'), findsWidgets);
    expect(db.setting<String>('language'), 'en');
    await finish(tester);
  });

  testWidgets('Korean UI fits on a narrow phone (bottom navigation, Home bar)', (tester) async {
    await open(tester);
    await tester.runAsync(() => db.setSetting('language', 'ko'));
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pump(tester, home: const Shell());
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  test('strings: both languages, plurals and sync errors', () {
    expect(Strings.en.episode('3'), 'Episode 3');
    expect(Strings.ko.episode('3'), '3화');
    expect(Strings.en.episodeCount(1), '1 episode');
    expect(Strings.en.episodeCount(2), '2 episodes');
    expect(Strings.ko.libraryLine(2, 5, '1.2 GB'), '작품 2개 · 5화 · 1.2 GB 사용');
    expect(Strings.ko.section('Latest Episode'), '최신 에피소드');
    expect(Strings.ko.section('Something new'), 'Something new');
    expect(Strings.ko.syncError(SyncException('x', kind: SyncError.wrongPassword)), '아이디 또는 비밀번호가 틀렸어요');
    expect(Strings.en.syncError(SyncException('x', kind: SyncError.taken)), 'That user ID is taken');
    expect(Strings.forCode(null), Strings.en);
    expect(Strings.forCode('ko'), Strings.ko);
  });
}
