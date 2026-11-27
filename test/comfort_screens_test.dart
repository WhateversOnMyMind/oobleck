import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/app/providers.dart';
import 'package:oobleck/app/theme.dart';
import 'package:oobleck/core/models.dart';
import 'package:oobleck/core/storage/app_db.dart';
import 'package:oobleck/core/storage/records.dart';
import 'package:oobleck/features/library/library_screen.dart';
import 'package:oobleck/features/library/library_show_screen.dart';
import 'package:oobleck/features/search/search_screen.dart';
import 'package:oobleck/features/show/show_screen.dart';
import 'package:oobleck/ui/poster_app_bar.dart';
import 'package:oobleck/ui/widgets.dart';

void main() {
  late AppDb db;
  late Directory dir;

  Future<void> open(WidgetTester tester, {Size size = const Size(360, 760)}) async {
    await tester.runAsync(() async {
      dir = Directory.systemTemp.createTempSync('oobleck_comfort');
      db = await AppDb.open(dir.path);
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  // Unmount first (stops the database watchers), then close for real.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });
  }

  // Skeletons animate forever, so pump a fixed time instead of settling.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Runs something that writes to the database in real time, so Hive's file
  /// write completes (under the test's fake clock it never would).
  Future<void> saving(WidgetTester tester, Future<void> Function() action) async {
    await tester.runAsync(() async {
      await action();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await settle(tester);
    // Callbacks registered during the real-time part (a snackbar closing)
    // only run in real time too; let them finish while the app is mounted.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  /// Taps in real time. A menu opened this way delivers its choice in real
  /// time as well, which the database write behind it needs.
  Future<void> tapReal(WidgetTester tester, Finder f) async {
    await tester.runAsync(() => tester.tap(f));
    await settle(tester);
  }

  final bundle = ShowBundle(
    const ShowDetail(slug: 'frieren', siteId: '1', title: 'Frieren', url: '', synopsis: 'An elf mage outlives her party.'),
    [for (var i = 1; i <= 40; i++) EpisodeInfo(number: '$i', serverKey: 'k$i')],
  );

  Future<void> pump(WidgetTester tester, Widget home, {double textScale = 1}) async {
    await tester.pumpWidget(ProviderScope(
      key: UniqueKey(),
      overrides: [
        dbProvider.overrideWithValue(db),
        supportDirProvider.overrideWithValue(dir.path),
        searchProvider.overrideWith((ref, q) async => [
              for (final t in ['Frieren', 'Fruits Basket'])
                if (t.toLowerCase().contains(q.toLowerCase())) ShowSummary(slug: t.toLowerCase(), title: t, url: ''),
            ]),
        showProvider.overrideWith((ref, slug) async => bundle),
      ],
      child: MaterialApp(
        theme: buildTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ));
    await settle(tester);
  }

  testWidgets('search: results as you type, clear button at once, recent searches with undo', (tester) async {
    await open(tester);
    await pump(tester, const Scaffold(body: SearchScreen()));
    expect(find.text('Find something to watch'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'fr');
    await tester.pump();
    expect(find.byTooltip('Clear search'), findsOneWidget); // no wait for the debounce
    await settle(tester);
    expect(find.byType(PosterCard), findsNWidgets(2));

    await tester.enterText(find.byType(TextField), 'fri');
    await settle(tester);
    expect(find.byType(PosterCard), findsOneWidget);

    // Submitting remembers the search; clearing the field shows it again.
    await saving(tester, () => tester.testTextInput.receiveAction(TextInputAction.search));
    await tester.tap(find.byTooltip('Clear search'));
    await settle(tester);
    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('fri'), findsOneWidget);

    await saving(tester, () => tester.tap(find.text('fri')));
    expect(find.byType(PosterCard), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'fri');

    await tester.tap(find.byTooltip('Clear search'));
    await settle(tester);
    await saving(tester, () => tester.tap(find.text('Clear all')));
    expect(find.text('Recent searches'), findsNothing);
    await saving(tester, () => tester.tap(find.text('Undo')));
    expect(find.text('fri'), findsOneWidget);
    expect(db.misc<List<dynamic>>('ui:recentSearches'), ['fri']);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('search: the query and results survive a visit to another tab', (tester) async {
    await open(tester, size: const Size(1100, 800));
    final onSearch = ValueNotifier(true);
    addTearDown(onSearch.dispose);
    await pump(
      tester,
      Scaffold(
        body: ValueListenableBuilder<bool>(
          valueListenable: onSearch,
          builder: (_, v, _) => v ? const SearchScreen() : const Text('other tab'),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'fruits');
    await settle(tester);
    expect(find.text('Fruits Basket'), findsOneWidget);

    onSearch.value = false;
    await settle(tester);
    expect(find.byType(SearchScreen), findsNothing);
    onSearch.value = true;
    await settle(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'fruits');
    expect(find.text('Fruits Basket'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('show page on a phone: Play stays in the bottom bar; long press selects a span to download', (tester) async {
    await open(tester);
    await tester.runAsync(() => db.saveProgress('frieren', '2', 600000, 1400000));
    await pump(tester, const ShowScreen(slug: 'frieren'));

    final bar = find.byType(StickyActionBar);
    expect(find.descendant(of: bar, matching: find.text('Resume episode 2')), findsOneWidget);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await settle(tester);
    expect(find.descendant(of: bar, matching: find.text('Resume episode 2')), findsOneWidget);
    // The title has moved into the pinned bar.
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Frieren')), findsOneWidget);

    final shown = tester.widgetList<Text>(find.textContaining(RegExp(r'^Episode \d+$'))).map((t) => t.data!).toList();
    final mid = shown.length ~/ 2;
    await tester.longPress(find.text(shown[mid]));
    await settle(tester);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('Download 1 episode'), findsOneWidget);
    await tester.longPress(find.text(shown[mid + 2]));
    await settle(tester);
    expect(find.text('3 selected'), findsOneWidget);
    expect(find.descendant(of: bar, matching: find.text('Download 3 episodes')), findsOneWidget);

    // Back leaves selection mode instead of the page.
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('3 selected'), findsNothing);
    expect(find.byType(ShowScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('show page: jump to an episode, newest first, and no overflow at large text', (tester) async {
    await open(tester);
    await pump(tester, const ShowScreen(slug: 'frieren'), textScale: 1.6);
    expect(tester.takeException(), isNull);
    expect(find.text('Episode 33'), findsNothing);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await settle(tester);
    await saving(tester, () => tester.tap(find.byTooltip('Oldest first')));
    expect(find.byTooltip('Newest first'), findsOneWidget);
    expect(db.misc<bool>('ui:episodesNewestFirst'), isTrue);
    expect(tester.widgetList<Text>(find.textContaining(RegExp(r'^Episode \d+$'))).first.data, 'Episode 40');

    await tester.tap(find.byTooltip('Jump to episode'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '7');
    await tester.tap(find.text('Go'));
    await settle(tester);
    expect(find.text('Episode 7'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  Future<void> seedLibrary(WidgetTester tester) => tester.runAsync(() async {
        var at = 1000;
        for (final (slug, title, eps, bytes) in [('akira', 'Akira', 1, 900), ('bleach', 'Bleach', 3, 100), ('chobits', 'Chobits', 2, 500)]) {
          await db.putShow(ShowRecord(slug: slug, title: title));
          for (var e = 1; e <= eps; e++) {
            await db.putDownload(DownloadRecord(
              slug: slug,
              episode: '$e',
              type: AudioType.sub,
              status: DownloadStatus.done,
              filePath: 'x.ts',
              totalBytes: bytes * 1024 * 1024,
              durationMs: 1400000,
              createdAt: slug == 'bleach' ? 9000 + e : at++,
            ));
          }
        }
      });

  List<String> cardTitles(WidgetTester tester) => tester.widgetList<PosterCard>(find.byType(PosterCard)).map((c) => c.title).toList();

  testWidgets('Downloaded: storage summary, sorting is remembered, long press asks before deleting', (tester) async {
    await open(tester);
    await seedLibrary(tester);
    await pump(tester, const Scaffold(body: LibraryScreen()));
    expect(find.textContaining('used on this device'), findsOneWidget);
    expect(find.text('3 shows · 6 episodes'), findsOneWidget);
    expect(cardTitles(tester), ['Akira', 'Bleach', 'Chobits']);

    await tapReal(tester, find.byTooltip('Sort by'));
    await saving(tester, () => tester.tap(find.text('Size'), warnIfMissed: false));
    expect(cardTitles(tester), ['Chobits', 'Akira', 'Bleach']);
    expect(db.misc<String>('ui:librarySort'), 'size');

    await tapReal(tester, find.byTooltip('Sort by'));
    await saving(tester, () => tester.tap(find.text('Recently downloaded'), warnIfMissed: false));
    expect(cardTitles(tester).first, 'Bleach');

    await tester.longPress(find.text('Akira'));
    await settle(tester);
    await tester.tap(find.text('Delete show'));
    await settle(tester);
    // Still there until confirmed.
    expect(find.textContaining('Delete'), findsWidgets);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(cardTitles(tester), contains('Akira'));
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('Downloaded show on a phone: Play in the bottom bar, watched toggle with undo, swipe asks first', (tester) async {
    await open(tester);
    await seedLibrary(tester);
    await pump(tester, const LibraryShowScreen(slug: 'bleach'), textScale: 1.3);
    final bar = find.byType(StickyActionBar);
    expect(find.descendant(of: bar, matching: find.text('Play episode 1')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tapReal(tester, find.byTooltip('More').at(1));
    await saving(tester, () => tester.tap(find.text('Mark as watched')));
    expect(db.historyFor('bleach', '1')!.isFinished, isTrue);
    expect(find.descendant(of: bar, matching: find.text('Play episode 2')), findsOneWidget);
    await saving(tester, () => tester.tap(find.text('Undo')));
    expect(db.historyFor('bleach', '1')!.isFinished, isFalse);

    await tester.drag(find.text('Episode 2'), const Offset(-320, 0));
    await settle(tester);
    expect(find.text('Delete episode 2?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.text('Episode 2'), findsOneWidget);
    expect(db.allDownloads().where((d) => d.slug == 'bleach').length, 3);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
}
