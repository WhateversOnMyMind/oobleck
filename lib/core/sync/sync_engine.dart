import '../storage/app_db.dart';
import '../storage/records.dart';
import 'sync_api.dart';
import 'sync_merge.dart';

/// One sync round: push what changed here, pull what changed elsewhere.
///
/// Bookkeeping lives in the misc box: `sync:since` (server clock of the last
/// pull), `sync:pushedAt` (local clock of the last push) and the queue of
/// "clear history" actions written by [AppDb.clearHistory].
class SyncEngine {
  SyncEngine(this.db, this.api, {int Function()? clock}) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);
  final AppDb db;
  final SyncApi api;
  final int Function() _clock;

  static const sinceKey = 'sync:since';
  static const pushedAtKey = 'sync:pushedAt';
  static const lastSyncKey = 'sync:lastSync';

  /// The server accepts up to 5000 items per list per request.
  static const chunk = 4000;

  Future<void> run(String token) async {
    final since = db.misc<int>(sinceKey) ?? 0;
    final pushedAt = db.misc<int>(pushedAtKey) ?? 0;
    final start = _clock();
    final pending = [
      for (final d in (db.misc<List>(AppDb.syncPendingDeletionsKey) ?? const [])) SyncDeletion.fromJson(d as Map),
    ];
    final changed = db.allHistory().where((h) => h.updatedAt >= pushedAt).toList();
    final shows = <SyncShow>[
      for (final slug in changed.map((h) => h.slug).toSet())
        if (db.show(slug) case final s? when s.title.isNotEmpty) SyncShow.fromRecord(s),
    ];

    SyncPull? pull;
    var i = 0;
    do {
      pull = await api.sync(
        token,
        since: since,
        history: changed.skip(i).take(chunk).toList(),
        shows: shows.skip(i).take(chunk).toList(),
        deletions: i == 0 ? pending : const [],
      );
      i += chunk;
    } while (i < changed.length || i < shows.length);

    // Shows first: Continue watching redraws on the history write and needs them.
    for (final s in pull.shows) {
      if (db.show(s.slug) == null) {
        await db.putShow(ShowRecord(
          slug: s.slug,
          title: s.title,
          poster: s.poster,
          url: s.url ?? '',
          siteId: s.siteId ?? '',
          malId: s.malId,
        ));
      }
    }
    final local = {for (final e in db.allHistory()) e.key: e};
    final merged = mergeRemote(local: local, remote: pull.history, deletions: pull.deletions);
    if (merged.remove.isNotEmpty) await db.deleteHistory(merged.remove);
    if (merged.put.isNotEmpty) await db.putHistory(merged.put);

    // Clears queued while this round was in flight stay queued.
    final now = db.misc<List>(AppDb.syncPendingDeletionsKey) ?? const [];
    await db.setMisc(AppDb.syncPendingDeletionsKey, now.length > pending.length ? now.sublist(pending.length) : null);
    await db.setMisc(sinceKey, pull.now);
    await db.setMisc(pushedAtKey, start);
    await db.setMisc(lastSyncKey, _clock());
  }

  /// Forget sync bookkeeping (on sign in / sign out) so the next round pushes
  /// everything and pulls everything.
  Future<void> reset() async {
    for (final k in [sinceKey, pushedAtKey, lastSyncKey, AppDb.syncPendingDeletionsKey]) {
      await db.setMisc(k, null);
    }
  }
}
