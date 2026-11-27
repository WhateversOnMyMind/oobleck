import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/app/providers.dart';
import 'package:oobleck/app/strings.dart';
import 'package:oobleck/app/strings_ui.dart';
import 'package:oobleck/core/models.dart';
import 'package:oobleck/core/storage/app_db.dart';
import 'package:oobleck/core/storage/records.dart';
import 'package:oobleck/features/library/library_sort.dart';
import 'package:oobleck/features/search/search_state.dart';
import 'package:oobleck/features/show/episode_selection.dart';
import 'package:oobleck/features/show/progress_actions.dart';
import 'package:oobleck/ui/layout.dart';

void main() {
  test('poster grid: three covers on a phone, more on wide windows, never tiny', () {
    expect(posterColumns(360), 3);
    expect(posterColumns(412), 3);
    expect(posterColumns(320), 2);
    expect(posterColumns(800), 5);
    expect(posterColumns(1200), 7);
    for (final w in [300.0, 360.0, 480.0, 599.0, 600.0, 900.0, 1920.0]) {
      final tile = posterTileWidth(w);
      expect(tile, greaterThanOrEqualTo(96), reason: 'width $w');
      expect(tile, lessThanOrEqualTo(180), reason: 'width $w');
    }
  });

  test('recent searches: newest first, no duplicates, capped', () {
    var list = <String>[];
    list = addRecentSearch(list, ' frieren ');
    list = addRecentSearch(list, 'bleach');
    list = addRecentSearch(list, 'Frieren');
    expect(list, ['Frieren', 'bleach']);
    expect(addRecentSearch(list, '   '), list);
    for (var i = 0; i < 20; i++) {
      list = addRecentSearch(list, 'q$i');
    }
    expect(list.length, 8);
    expect(list.first, 'q19');
  });

  group('episode selection', () {
    final eps = [for (final n in ['1', '2', '3', '4', '5', '5.5', '7']) EpisodeInfo(number: n, serverKey: 'k$n')];
    final order = [for (final e in eps) e.number];

    test('span between two long presses, in either direction', () {
      expect(episodeSpan(order, '2', '4'), ['2', '3', '4']);
      expect(episodeSpan(order, '5.5', '3'), ['3', '4', '5', '5.5']);
      expect(episodeSpan(order, '3', '3'), ['3']);
      expect(episodeSpan(order, '3', '99'), isEmpty);
    });

    test('typed range accepts reversed bounds and half episodes', () {
      expect([for (final e in episodesBetween(eps, 2, 4)) e.number], ['2', '3', '4']);
      expect([for (final e in episodesBetween(eps, 6, 5)) e.number], ['5', '5.5']);
      expect(episodesBetween(eps, 8, 20), isEmpty);
    });

    test('jump lands on the episode, or the next one when a number is skipped', () {
      expect(episodeIndexFor(eps, '5.5'), 5);
      expect(episodeIndexFor(eps, ' 3 '), 2);
      expect(episodeIndexFor(eps, '6'), 6); // there is no 6: go to 7
      expect(episodeIndexFor(eps, '8'), -1);
      expect(episodeIndexFor(eps, 'abc'), -1);
      // Newest-first lists work too.
      expect(episodeIndexFor(eps.reversed.toList(), '6'), 0);
    });
  });

  test('Downloaded sort: title, recent, size', () {
    LibraryShow show(String title, int bytes, int createdAt) => LibraryShow(
          ShowRecord(slug: title.toLowerCase(), title: title),
          [DownloadRecord(slug: title.toLowerCase(), episode: '1', type: AudioType.sub, totalBytes: bytes, createdAt: createdAt)],
        );
    final shows = [show('bleach', 300, 10), show('Akira', 100, 30), show('Chobits', 200, 20)];
    List<String> titles(LibrarySort s) => [for (final x in sortLibrary(shows, s)) x.show.title];
    expect(titles(LibrarySort.title), ['Akira', 'bleach', 'Chobits']);
    expect(titles(LibrarySort.recent), ['Akira', 'Chobits', 'bleach']);
    expect(titles(LibrarySort.size), ['bleach', 'Chobits', 'Akira']);
  });

  test('new UI strings exist in both languages', () {
    expect(Strings.en.undo, 'Undo');
    expect(Strings.ko.undo, '실행 취소');
    expect(Strings.en.episodesToDownload(1), 'Download 1 episode');
    expect(Strings.en.episodesToDownload(12), 'Download 12 episodes');
    expect(Strings.ko.episodesToDownload(12), '12화 다운로드');
  });

  group('watch progress actions', () {
    late Directory dir;
    late AppDb db;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('oobleck_progress');
      db = await AppDb.open(dir.path);
    });
    tearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });

    test('clearing a show can be undone and leaves other shows alone', () async {
      await db.saveProgress('a', '1', 1400000, 1400000, now: 100);
      await db.saveProgress('a', '2', 600000, 1400000, now: 200);
      await db.saveProgress('b', '1', 600000, 1400000, now: 300);

      final removed = await clearShowProgress(db, 'a');
      expect(removed.length, 2);
      expect(db.historyFor('a', '1'), isNull);
      expect(db.historyFor('b', '1'), isNotNull);

      await restoreProgress(db, removed, now: 5000);
      expect(db.historyFor('a', '1')!.isFinished, isTrue);
      expect(db.historyFor('a', '2')!.positionMs, 600000);
      // Restored with fresh timestamps, oldest first, so their order is kept.
      expect(db.historyFor('a', '1')!.updatedAt, 5000);
      expect(db.historyFor('a', '2')!.updatedAt, 5001);
    });

    test('mark watched / unwatched keeps the known duration and can be undone', () async {
      await db.saveProgress('a', '1', 600000, 1400000);
      final before = await setEpisodesWatched(db, 'a', {'1': 0, '2': 1300000}, watched: true);
      expect(db.historyFor('a', '1')!.isFinished, isTrue);
      expect(db.historyFor('a', '1')!.durationMs, 1400000);
      expect(db.historyFor('a', '2')!.isFinished, isTrue);
      expect(db.historyFor('a', '2')!.durationMs, 1300000);

      await restoreProgress(db, before);
      expect(db.historyFor('a', '1')!.positionMs, 600000);
      expect(db.historyFor('a', '1')!.isPartial, isTrue);
      expect(db.historyFor('a', '2')!.positionMs, 0);

      await setEpisodesWatched(db, 'a', {'1': 0}, watched: false);
      expect(db.historyFor('a', '1')!.positionMs, 0);
      expect(db.historyFor('a', '1')!.durationMs, 1400000);
    });
  });
}
