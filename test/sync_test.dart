import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:oobleck/core/storage/app_db.dart';
import 'package:oobleck/core/storage/records.dart';
import 'package:oobleck/core/sync/sync_api.dart';
import 'package:oobleck/core/sync/sync_crypto.dart';
import 'package:oobleck/core/sync/sync_engine.dart';
import 'package:oobleck/core/sync/sync_merge.dart';
import 'package:oobleck/features/sync/sync_section.dart';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

HistoryEntry h(String slug, String ep, int pos, int at, {int dur = 1440000}) =>
    HistoryEntry(slug: slug, episode: ep, positionMs: pos, durationMs: dur, updatedAt: at);

void main() {
  group('PBKDF2', () {
    test('RFC 7914 / RFC 6070-style SHA-256 vectors', () {
      final p = utf8.encode('password');
      final s = utf8.encode('salt');
      expect(hex(pbkdf2Sha256(p, s, 1)), '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
      expect(hex(pbkdf2Sha256(p, s, 2)), 'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
      expect(hex(pbkdf2Sha256(p, s, 4096)), 'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a');
    });

    test('login key matches Node crypto.pbkdf2Sync and ignores user ID case', () async {
      // node -e "crypto.pbkdf2Sync('hunter2-evangelion','oobleck-sync:asuka',100000,32,'sha256')"
      const expected = '264eef3cd1646a3834b6ea41df2985f8d8f9d8cceb600f412effb6dcde0ed63d';
      expect(await deriveLoginKey(' Asuka ', 'hunter2-evangelion'), expected);
    });
  });

  group('mergeRemote', () {
    test('newer remote wins, older is ignored', () {
      final local = {for (final e in [h('eva', '1', 100, 10), h('eva', '2', 100, 50)]) e.key: e};
      final r = mergeRemote(local: local, remote: [h('eva', '1', 900, 20), h('eva', '2', 1, 40), h('eva', '3', 5, 60)], deletions: const []);
      expect(r.put.map((e) => '${e.episode}:${e.positionMs}'), ['1:900', '3:5']);
      expect(r.remove, isEmpty);
    });

    test('a clear removes what was watched before it, keeps what came after', () {
      final local = {for (final e in [h('eva', '1', 1, 10), h('eva', '2', 1, 300), h('frieren', '1', 1, 10)]) e.key: e};
      final r = mergeRemote(local: local, remote: [h('eva', '5', 1, 100)], deletions: [SyncDeletion('eva', 200)]);
      expect(r.remove, ['eva|1']);
      expect(r.put, isEmpty); // eva 5 was cleared too
      final all = mergeRemote(local: local, remote: const [], deletions: [SyncDeletion('*', 400)]);
      expect(all.remove.toSet(), {'eva|1', 'eva|2', 'frieren|1'});
    });
  });

  test('sign-in form checks', () {
    String? v({String user = 'asuka', String pw = 'longenough', String? confirm, bool create = false, String server = 'https://x.workers.dev'}) =>
        validateSyncForm(user: user, password: pw, confirm: confirm, create: create, server: server);
    expect(v(), isNull);
    expect(v(user: 'Asuka_02'), isNull);
    expect(v(user: 'as'), isNotNull);
    expect(v(user: 'has space'), isNotNull);
    expect(v(pw: 'short'), isNotNull);
    expect(v(create: true, confirm: 'other-one'), "Passwords don't match.");
    expect(v(create: true, confirm: 'longenough'), isNull);
    expect(v(server: ''), isNotNull);
    expect(v(server: 'oobleck.workers.dev'), isNotNull);
    expect(syncedAgo(null, DateTime(2026)), 'Not synced yet');
    expect(syncedAgo(DateTime(2026, 1, 1, 10), DateTime(2026, 1, 1, 10, 5)), 'Synced 5 min ago');
  });

  group('end to end against the Worker (node server/test/dev_server.js)', () {
    Process? server;
    late String url;
    final dirs = <Directory>[];

    setUpAll(() async {
      try {
        server = await Process.start('node', ['--no-warnings', 'server/test/dev_server.js', '0']);
      } on ProcessException {
        return; // no Node: skipped below
      }
      final ready = Completer<String>();
      server!.stdout.transform(utf8.decoder).listen((l) {
        final m = RegExp(r'listening (\d+)').firstMatch(l);
        if (m != null && !ready.isCompleted) ready.complete(m.group(1));
      });
      final err = StringBuffer();
      server!.stderr.transform(utf8.decoder).listen(err.write);
      unawaited(server!.exitCode.then((_) {
        if (!ready.isCompleted) ready.completeError(err.toString());
      }));
      try {
        url = 'http://127.0.0.1:${await ready.future.timeout(const Duration(seconds: 20))}';
      } catch (_) {
        server!.kill();
        server = null; // Node without node:sqlite (< 22.5)
      }
    });

    tearDownAll(() async {
      server?.kill();
      await Hive.close();
      for (final d in dirs) {
        try {
          d.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    Future<AppDb> device(String name) async {
      final d = Directory.systemTemp.createTempSync('sync_$name');
      dirs.add(d);
      // One device at a time: Hive is process-wide, so each step closes it.
      return AppDb.open('${d.path}/db');
    }

    test('two devices share progress, shows and clears', () async {
      if (server == null) return markTestSkipped('needs Node 22.5+ on PATH');
      final api = SyncApi(Dio(), url);
      final key = await deriveLoginKey('shinji', 'get-in-the-robot');
      final acc = await api.register('Shinji', key);
      expect(acc.username, 'shinji');
      await expectLater(api.register('shinji', key), throwsA(isA<SyncException>().having((e) => e.message, 'msg', 'That user ID is taken')));
      await expectLater(api.login('shinji', await deriveLoginKey('shinji', 'wrong-password')), throwsA(isA<SyncException>()));
      final acc2 = await api.login('SHINJI', key);

      // Device A (one Hive at a time: sync, close, then device B).
      var db = await device('a');
      await db.putShow(ShowRecord(slug: 'eva', title: 'Neon Genesis Evangelion', poster: 'https://p/eva.jpg', malId: '30'));
      await db.saveProgress('eva', '1', 1440000, 1440000, now: 1000);
      await db.saveProgress('eva', '2', 600000, 1440000, now: 2000);
      await db.setMisc(AppDb.syncTokenKey, acc.token);
      var t = 0; // same clock as the saveProgress times below
      await SyncEngine(db, api, clock: () => t++).run(acc.token);
      await Hive.close();

      // Device B gets them, keeps watching episode 2.
      db = await device('b');
      await db.setMisc(AppDb.syncTokenKey, acc2.token);
      await SyncEngine(db, api, clock: () => t++).run(acc2.token);
      expect(db.show('eva')?.title, 'Neon Genesis Evangelion');
      expect(db.historyFor('eva', '2')?.positionMs, 600000);
      await db.saveProgress('eva', '2', 900000, 1440000, now: 3000);
      await db.saveProgress('frieren', '1', 60000, 1440000, now: 3100);
      await SyncEngine(db, api, clock: () => t++).run(acc2.token);
      // Then clears Evangelion.
      await db.clearShowHistory('eva', now: 4000);
      await SyncEngine(db, api, clock: () => t++).run(acc2.token);
      expect(db.misc<List>(AppDb.syncPendingDeletionsKey), isNull);
      await Hive.close();

      // Back on A: Evangelion is gone (both episodes), Frieren arrived.
      db = await AppDb.open('${dirs.first.path}/db');
      await SyncEngine(db, api, clock: () => t++).run(acc.token);
      expect(db.historyFor('eva', '1'), isNull);
      expect(db.historyFor('eva', '2'), isNull);
      expect(db.historyFor('frieren', '1')?.positionMs, 60000);

      // Signed out elsewhere: the engine reports it.
      await api.logout(acc.token);
      await expectLater(
        SyncEngine(db, api).run(acc.token),
        throwsA(isA<SyncException>().having((e) => e.signedOut, 'signedOut', isTrue)),
      );
      await Hive.close();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
