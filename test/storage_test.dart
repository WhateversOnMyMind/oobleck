import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/core/models.dart';
import 'package:oobleck/core/storage/app_db.dart';
import 'package:oobleck/core/storage/records.dart';

void main() {
  late Directory dir;
  late AppDb db;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('oobleck_db');
    db = await AppDb.open(dir.path);
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test('progress round trip and finished threshold', () async {
    await db.saveProgress('a', '1', 600000, 1400000);
    final h = db.historyFor('a', '1')!;
    expect(h.isPartial, isTrue);
    expect(h.isFinished, isFalse);
    await db.saveProgress('a', '1', 1300000, 1400000);
    expect(db.historyFor('a', '1')!.isFinished, isTrue);
  });

  test('download record persists', () async {
    final d = DownloadRecord(slug: 'a', episode: '2', type: AudioType.dub, status: DownloadStatus.done, filePath: '/x.ts');
    d.subs = [DownloadedSub(path: '/x.en.vtt', label: 'English', language: 'en')];
    await db.putDownload(d);
    await db.close();
    db = await AppDb.open(dir.path);
    final r = db.download(d.key)!;
    expect(r.isDone, isTrue);
    expect(r.subs.single.language, 'en');
  });

  test('continue watching: partial, finished->next, ordering', () {
    final shows = {
      'a': ShowRecord(slug: 'a', title: 'A'),
      'b': ShowRecord(slug: 'b', title: 'B'),
      'c': ShowRecord(slug: 'c', title: 'C'),
    };
    HistoryEntry h(String s, String e, int p, int t) =>
        HistoryEntry(slug: s, episode: e, positionMs: p, durationMs: 1000, updatedAt: t);
    final items = buildContinueWatching(
      history: [h('a', '1', 1000, 5), h('a', '2', 500, 9), h('b', '3', 990, 7), h('c', '1', 990, 1)],
      shows: shows,
      knownEpisodes: {'a': ['1', '2'], 'b': ['3', '4'], 'c': ['1']},
    );
    expect(items.map((i) => '${i.show.slug}:${i.episode}'), ['a:2', 'b:4']);
    expect(items.first.resumeFraction, 0.5);
  });
}
