import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/app/providers.dart';
import 'package:oobleck/app/theme.dart';
import 'package:oobleck/core/manga/manga_models.dart';
import 'package:oobleck/core/manga/page_cache.dart';
import 'package:oobleck/core/sources/manga_source.dart';
import 'package:oobleck/core/storage/app_db.dart';
import 'package:oobleck/core/storage/manga_records.dart';
import 'package:oobleck/features/manga/manga_detail_screen.dart';
import 'package:oobleck/features/manga/manga_providers.dart';
import 'package:oobleck/features/manga/manga_tab.dart';
import 'package:oobleck/features/reader/reader_controller.dart';
import 'package:oobleck/features/reader/reader_screen.dart';
import 'package:oobleck/features/reader/reader_settings.dart';

class FakeMangaSource implements MangaSource {
  int fetches = 0;

  @override
  String get id => 'toon11';
  @override
  String get name => 'Fake';
  @override
  Map<String, String> get imageHeaders => const {};
  @override
  List<MangaCatalog> get catalogs => const [MangaCatalog('latest', 'Latest', '최신', supportsGenres: true)];
  @override
  List<MangaGenre> get genres => const [MangaGenre('액션', '액션')];

  @override
  Future<MangaListing> browse(String catalogId, {int page = 1, Set<String> genres = const {}}) async =>
      MangaListing(page == 1 ? const [MangaSummary(id: '7', title: 'Solo Story'), MangaSummary(id: '8', title: 'Other One')] : const []);

  @override
  Future<MangaListing> search(String query, {int page = 1}) async =>
      MangaListing([MangaSummary(id: '9', title: 'Found $query')]);

  @override
  Future<MangaBundle> fetch(String mangaId) async {
    fetches++;
    return MangaBundle(
      MangaDetail(id: mangaId, title: 'Solo Story', author: 'Kim', genres: const ['액션'], status: MangaStatus.ongoing, description: 'A story.'),
      [for (var i = 1; i <= 3; i++) ChapterInfo(id: '$i', mangaId: mangaId, title: '$i화', number: i.toDouble())],
    );
  }

  @override
  Future<List<MangaPage>> pages(ChapterInfo chapter) async =>
      [for (var i = 0; i < 4; i++) MangaPage(i, 'https://img.test/${chapter.id}/$i.png')];

  @override
  String mangaUrl(String mangaId) => 'https://site.test/$mangaId';
}

class FakePageCache extends PageCache {
  FakePageCache() : super(dio: Dio(), dir: Directory.systemTemp.path);
  final requested = <String>[];
  @override
  Future<Uint8List> bytes(MangaPage page, {Map<String, String> headers = const {}, CancelToken? cancel}) async {
    requested.add(page.url);
    return Uint8List(0);
  }
}

void main() {
  late Directory dir;
  late AppDb db;
  late FakeMangaSource source;

  Widget app(Widget home, {bool fetch = true}) => ProviderScope(
        overrides: [
          // Fetches write to Hive; in widget tests they run before pumping (real time).
          if (!fetch) mangaRefreshProvider.overrideWith((ref, key) async => db.manga(key)!),
          dbProvider.overrideWithValue(db),
          supportDirProvider.overrideWithValue(dir.path),
          mangaSourceProvider.overrideWithValue(source),
          pageCacheProvider.overrideWithValue(FakePageCache()),
        ],
        child: MaterialApp(theme: buildTheme(), home: home),
      );

  Future<void> pumpFor(WidgetTester tester, [int frames = 8]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  setUp(() => source = FakeMangaSource());

  testWidgets('Browse lists the catalog, and an empty library starts on Browse', (tester) async {
    await tester.runAsync(() async {
      dir = Directory.systemTemp.createTempSync('manga_flow');
      db = await AppDb.open(dir.path);
    });
    await tester.pumpWidget(app(const MangaTab()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await pumpFor(tester);
    expect(find.text('Solo Story'), findsOneWidget);
    expect(find.text('Other One'), findsOneWidget);
    expect(find.text('Latest'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });
  });

  testWidgets('series screen loads chapters, offers Start reading and adds to the library', (tester) async {
    await tester.runAsync(() async {
      dir = Directory.systemTemp.createTempSync('manga_flow');
      db = await AppDb.open(dir.path);
      await refreshSeries(db, source, '7');
    });
    await tester.pumpWidget(app(const MangaDetailScreen(mangaKey: 'toon11:7'), fetch: false));
    await pumpFor(tester);
    expect(source.fetches, 1);
    expect(find.text('3 chapters'), findsWidgets);
    expect(find.text('3화'), findsOneWidget, reason: 'newest first');
    expect(find.text('Start reading'), findsOneWidget);
    expect(find.text('Kim · Ongoing'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Add to library'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await pumpFor(tester, 4);
    expect(db.manga('toon11:7')!.inLibrary, isTrue);
    expect(find.text('In library'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await db.close();
      dir.deleteSync(recursive: true);
    });
  });

  testWidgets('leaving the reader disposes cleanly and saves the chapter', (tester) async {
    await tester.runAsync(() async {
      dir = Directory.systemTemp.createTempSync('manga_flow');
      db = await AppDb.open(dir.path);
      await refreshSeries(db, source, '7');
      // No image decoding, shaders or platform plugins in this test.
      await db.setSetting('reader.mode', 'webtoon');
      await db.setSetting('reader.upscale', false);
      await db.setSetting('reader.keepScreenOn', false);
      await db.setSetting('reader.fullscreen', false);
    });
    await tester.pumpWidget(app(const ReaderScreen(mangaKey: 'toon11:7', chapterId: '1')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await pumpFor(tester, 4);
    // Disposing used to read a provider from State.dispose and throw. The
    // save it makes is a real database write, so it runs in real time.
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox());
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      expect(db.chapterState('toon11:7', '1'), isNotNull);
      await db.close();
      dir.deleteSync(recursive: true);
    });
  });

  test('state ticks fire on writes that keep the number of records', () async {
    final tmp = Directory.systemTemp.createTempSync('manga_ticks');
    final store = await AppDb.open(tmp.path);
    await store.saveReading('toon11:7', '1', page: 1, pageCount: 4);
    final ticks = <int>[];
    final sub = store.watchChapterStates().listen(ticks.add);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await store.setRead('toon11:7', ['1'], true);
    await store.setBookmarked('toon11:7', ['1'], true);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(ticks.toSet(), hasLength(ticks.length), reason: 'every value differs');
    expect(ticks.length, greaterThanOrEqualTo(3));
    unawaited(sub.cancel());
    await store.close();
    tmp.deleteSync(recursive: true);
  });

  group('ReaderController', () {
    setUp(() async {
      dir = Directory.systemTemp.createTempSync('manga_reader');
      db = await AppDb.open(dir.path);
      await db.putManga(MangaRecord(sourceId: 'toon11', mangaId: '7', title: 'Solo Story'));
      await db.mergeChapters('toon11:7', (await FakeMangaSource().fetch('7')).chapters);
    });
    tearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });

    ReaderController make(FakePageCache cache, {ReaderSettings settings = const ReaderSettings(mode: ReaderMode.webtoon)}) =>
        ReaderController(db: db, source: FakeMangaSource(), cache: cache, mangaKey: 'toon11:7', settings: () => settings);

    test('opens a chapter, saves progress, resumes there and marks it read at the end', () async {
      final cache = FakePageCache();
      final c = make(cache);
      await c.open('1');
      expect(c.mode, ReaderMode.webtoon);
      expect(c.current!.pages, hasLength(4));
      expect(c.nextChapter?.id, '2');
      expect(c.previousChapter, isNull);

      c.onPosition(0, 2, 0.5);
      expect(cache.requested, contains('https://img.test/1/3.png'), reason: 'pages ahead are preloaded');
      c.flush();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final saved = db.chapterState('toon11:7', '1')!;
      expect([saved.page, saved.pageCount, saved.read], [2, 4, false]);
      c.dispose();

      final again = make(FakePageCache());
      await again.open('1');
      expect(again.page, 2, reason: 'resumes where it was left');
      again.onPosition(0, 3, 1, finished: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(db.chapterState('toon11:7', '1')!.read, isTrue);
      again.dispose();
    });

    test('long strip appends the next chapter; moving into it marks the previous one read', () async {
      final c = make(FakePageCache());
      await c.open('1');
      await c.appendNext();
      expect(c.segments.map((s) => s.chapter.id), ['1', '2']);
      c.onPosition(1, 0, 0);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(db.chapterState('toon11:7', '1')!.read, isTrue);
      expect(c.current!.chapter.id, '2');
      c.dispose();
    });

    test('a series reading mode overrides the app default', () async {
      await db.putManga(db.manga('toon11:7')!.copyWith(readerMode: 'ltr'));
      final c = make(FakePageCache());
      await c.open('2');
      expect(c.mode, ReaderMode.ltr);
      c.dispose();
    });
  });
}
