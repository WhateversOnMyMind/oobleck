import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/core/manga/manga_models.dart';
import 'package:oobleck/core/storage/app_db.dart';
import 'package:oobleck/core/storage/manga_records.dart';
import 'package:oobleck/features/manga/manga_logic.dart';
import 'package:oobleck/features/reader/reader_controller.dart';
import 'package:oobleck/features/reader/reader_settings.dart';

ChapterRecord ch(String id, {int? up, int seen = 0}) => ChapterRecord(id: id, title: '$id화', number: double.tryParse(id), uploaded: up, firstSeen: seen);
ChapterState st(String id, {bool read = false, int? at, int page = 0, int count = 10}) =>
    ChapterState(mangaKey: 'toon11:1', chapterId: id, read: read, readAt: at, page: page, pageCount: count);
ChapterInfo info(String id) => ChapterInfo(id: id, mangaId: '1', title: '$id화', number: double.parse(id));

void main() {
  group('nextToRead', () {
    final chapters = [ch('1'), ch('2'), ch('3')];
    test('no history: first unread chapter', () {
      expect(nextToRead(chapters, {})!.id, '1');
      expect(nextToRead(chapters, {'1': st('1', read: true)})!.id, '2');
    });
    test('last opened and unfinished: resume it', () {
      expect(nextToRead(chapters, {'1': st('1', read: true, at: 1), '2': st('2', at: 5, page: 3)})!.id, '2');
    });
    test('last opened is finished: the next unread after it', () {
      final states = {'1': st('1', read: true, at: 9), '2': st('2', read: true, at: 2)};
      // Chapter 1 was opened last and is done; 2 is read too, so 3 is next.
      expect(nextToRead(chapters, states)!.id, '3');
    });
    test('everything read: nothing', () {
      expect(nextToRead(chapters, {for (final c in chapters) c.id: st(c.id, read: true, at: 1)}), isNull);
    });
  });

  test('unread count, previous chapters and neighbours', () {
    final chapters = [ch('1'), ch('2'), ch('3')];
    expect(unreadCount(chapters, {'2': st('2', read: true)}), 2);
    expect(previousChapterIds(chapters, '3'), ['1', '2']);
    expect(previousChapterIds(chapters, '1'), isEmpty);
    final (prev, next) = neighbours(chapters, '2');
    expect([prev?.id, next?.id], ['1', '3']);
    expect(neighbours(chapters, '3').$2, isNull);
  });

  test('library: filter, search, sort', () {
    MangaRecord m(String id, String title, {int added = 0, MangaStatus status = MangaStatus.ongoing}) =>
        MangaRecord(sourceId: 'toon11', mangaId: id, title: title, inLibrary: true, addedAt: added, status: status);
    final a = libraryEntryFor(m('1', 'Beta', added: 2), [ch('1', up: 10), ch('2', up: 50)], {'1': st('1', read: true, at: 100)}, {});
    final b = libraryEntryFor(m('2', 'alpha', added: 1, status: MangaStatus.completed), [ch('1', up: 90)], {}, {'1'});
    expect(a.unread, 1);
    expect(a.latestChapterAt, 50);
    expect(b.downloaded, 1);
    expect(arrangeLibrary([a, b], sort: LibrarySort.title, descending: false).map((e) => e.manga.title), ['alpha', 'Beta']);
    expect(arrangeLibrary([a, b], sort: LibrarySort.lastUpdate).first.manga.title, 'alpha');
    expect(arrangeLibrary([a, b], sort: LibrarySort.lastRead).first.manga.title, 'Beta');
    expect(arrangeLibrary([a, b], filter: const LibraryFilter(completed: true)).single.manga.title, 'alpha');
    expect(arrangeLibrary([a, b], filter: const LibraryFilter(started: true)).single.manga.title, 'Beta');
    expect(arrangeLibrary([a, b], query: 'ALP').single.manga.title, 'alpha');
  });

  test('chapter list filter and order', () {
    final chapters = [ch('1'), ch('2'), ch('3')];
    final states = {'2': st('2', read: true), '3': ChapterState(mangaKey: 'k', chapterId: '3', bookmarked: true)};
    expect(visibleChapters(chapters, states, {}, newestFirst: true).map((c) => c.id), ['3', '2', '1']);
    expect(visibleChapters(chapters, states, {}, newestFirst: false, filter: 'unread').map((c) => c.id), ['1', '3']);
    expect(visibleChapters(chapters, states, {'1'}, newestFirst: false, filter: 'downloaded').map((c) => c.id), ['1']);
    expect(visibleChapters(chapters, states, {}, newestFirst: false, filter: 'bookmarked').map((c) => c.id), ['3']);
  });

  test('groupByDay groups by local calendar day, newest first', () {
    final d1 = DateTime(2026, 11, 26, 23, 50).millisecondsSinceEpoch;
    final d2 = DateTime(2026, 11, 27, 0, 10).millisecondsSinceEpoch;
    final g = groupByDay([d1, d2, d2 + 1], (x) => x);
    expect(g.map((e) => e.$1.day), [27, 26]);
    expect(g.first.$2, hasLength(2));
  });

  group('tap zones', () {
    test('L shape: top and left go back, right and bottom go forward, centre is the menu', () {
      expect(tapActionAt(TapLayout.lShape, 0.5, 0.5), TapAction.menu);
      expect(tapActionAt(TapLayout.lShape, 0.5, 0.1), TapAction.previous);
      expect(tapActionAt(TapLayout.lShape, 0.1, 0.5), TapAction.previous);
      expect(tapActionAt(TapLayout.lShape, 0.9, 0.5), TapAction.next);
      expect(tapActionAt(TapLayout.lShape, 0.5, 0.9), TapAction.next);
      expect(tapActionAt(TapLayout.lShape, 0.1, 0.9), TapAction.next);
    });
    test('left/right flips for right-to-left books and with invert', () {
      expect(tapActionAt(TapLayout.leftRight, 0.2, 0.5), TapAction.previous);
      expect(tapActionAt(TapLayout.leftRight, 0.2, 0.5, rtl: true), TapAction.next);
      expect(tapActionAt(TapLayout.leftRight, 0.2, 0.5, invert: true), TapAction.next);
      expect(tapActionAt(TapLayout.leftRight, 0.2, 0.5, invert: true, rtl: true), TapAction.previous);
    });
    test('edges and off', () {
      expect(tapActionAt(TapLayout.edges, 0.5, 0.5), TapAction.menu);
      expect(tapActionAt(TapLayout.edges, 0.9, 0.5), TapAction.next);
      expect(tapActionAt(TapLayout.off, 0.9, 0.5), TapAction.menu);
    });
  });

  test('automatic mode: tall strips scroll, book pages turn', () {
    expect(autoModeFor(690, 4000), ReaderMode.webtoon);
    expect(autoModeFor(1403, 2048), ReaderMode.rtl);
  });

  group('storage', () {
    late Directory dir;
    late AppDb db;
    const key = 'toon11:1';
    setUp(() async {
      dir = Directory.systemTemp.createTempSync('manga_store');
      db = await AppDb.open(dir.path);
      await db.putManga(MangaRecord(sourceId: 'toon11', mangaId: '1', title: 'One'));
    });
    tearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });

    test('first fetch finds nothing new; later fetches feed Updates for library series only', () async {
      expect(await db.mergeChapters(key, [info('1'), info('2')], now: 10), isEmpty);
      expect(await db.mergeChapters(key, [info('1'), info('2'), info('3')], now: 20), hasLength(1));
      expect(db.mangaUpdates(), isEmpty, reason: 'not in the library');
      await db.setInLibrary(key, true, now: 30);
      final fresh = await db.mergeChapters(key, [info('1'), info('2'), info('3'), info('4')], now: 40);
      expect(fresh.single.id, '4');
      expect(db.mangaUpdates().single.chapterId, '4');
      expect(db.chapters(key).firstWhere((c) => c.id == '1').firstSeen, 10, reason: 'first seen is kept');
      expect(db.manga(key)!.lastChecked, 40);
      expect(db.manga(key)!.addedAt, 30);
    });

    test('reading progress, finishing, incognito and history', () async {
      await db.saveReading(key, '1', page: 3, pageCount: 10, now: 100);
      expect(db.chapterState(key, '1')!.started, isTrue);
      await db.saveReading(key, '1', page: 9, pageCount: 10, finished: true, now: 200);
      await db.saveReading(key, '1', page: 0, pageCount: 10, now: 300);
      expect(db.chapterState(key, '1')!.read, isTrue, reason: 'stays read when reopened');
      await db.saveReading(key, '2', page: 1, pageCount: 10, incognito: true, now: 400);
      expect(db.chapterState(key, '2')!.readAt, isNull);
      expect(db.mangaHistory().single.$2.chapterId, '1');
      await db.removeMangaHistory(key);
      expect(db.mangaHistory(), isEmpty);
      expect(db.chapterState(key, '1')!.read, isTrue, reason: 'read marks stay');
      await db.setRead(key, ['1'], false);
      expect(db.chapterState(key, '1')!.page, 0);
      await db.setBookmarked(key, ['1', '2'], true);
      expect(db.chapterStates(key).values.where((s) => s.bookmarked), hasLength(2));
    });
  });
}
