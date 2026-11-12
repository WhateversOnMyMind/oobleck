import '../storage/records.dart';
import 'sync_api.dart';

class MergeResult {
  MergeResult(this.put, this.remove);

  /// Entries to write locally (remote copies that are newer).
  final List<HistoryEntry> put;

  /// Local keys to delete because another device cleared them.
  final List<String> remove;
}

/// Applies what the server sent to the local history: a remote entry wins
/// when its `updatedAt` is newer; a clear removes local entries watched before
/// it (anything watched later on this device is kept).
MergeResult mergeRemote({
  required Map<String, HistoryEntry> local,
  required List<HistoryEntry> remote,
  required List<SyncDeletion> deletions,
}) {
  final result = Map<String, HistoryEntry>.of(local);
  final remove = <String>{};
  for (final d in deletions) {
    for (final e in result.values) {
      if ((d.slug == '*' || e.slug == d.slug) && e.updatedAt <= d.at) remove.add(e.key);
    }
  }
  result.removeWhere((k, _) => remove.contains(k));
  final put = <HistoryEntry>[];
  for (final r in remote) {
    final cleared = deletions.any((d) => (d.slug == '*' || d.slug == r.slug) && r.updatedAt <= d.at);
    if (cleared) continue;
    final cur = result[r.key];
    if (cur == null || r.updatedAt > cur.updatedAt) {
      result[r.key] = r;
      put.add(r);
      remove.remove(r.key);
    }
  }
  return MergeResult(put, remove.toList());
}
