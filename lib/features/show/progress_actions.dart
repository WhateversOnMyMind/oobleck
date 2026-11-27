import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/storage/app_db.dart';
import '../../core/storage/records.dart';
import '../sync/sync_controller.dart';

/// Removes every watched mark and resume position of [slug] and returns what
/// was removed, so the caller can offer Undo.
Future<List<HistoryEntry>> clearShowProgress(AppDb db, String slug) async {
  final removed = db.allHistory().where((h) => h.slug == slug).toList();
  await db.clearShowHistory(slug);
  return removed;
}

/// Puts [entries] back. They are written with fresh timestamps (in their old
/// order) so a clear already queued for sync does not delete them again.
Future<void> restoreProgress(AppDb db, List<HistoryEntry> entries, {int? now}) async {
  final sorted = [...entries]..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
  final base = now ?? DateTime.now().millisecondsSinceEpoch;
  for (var i = 0; i < sorted.length; i++) {
    final e = sorted[i];
    await db.saveProgress(e.slug, e.episode, e.positionMs, e.durationMs, now: base + i);
  }
}

/// Marks [episodes] (number -> known duration in ms, 0 if unknown) of [slug]
/// watched or unwatched. Returns the previous entries for Undo.
Future<List<HistoryEntry>> setEpisodesWatched(AppDb db, String slug, Map<String, int> episodes, {required bool watched}) async {
  final before = <HistoryEntry>[];
  for (final e in episodes.entries) {
    final prev = db.historyFor(slug, e.key);
    // An episode with no entry is restored as "not started".
    before.add(prev ?? HistoryEntry(slug: slug, episode: e.key, positionMs: 0, durationMs: e.value, updatedAt: 0));
    final duration = prev != null && prev.durationMs > 0 ? prev.durationMs : (e.value > 0 ? e.value : 1);
    if (watched) {
      await db.markWatched(slug, e.key, durationMs: duration);
    } else {
      await db.saveProgress(slug, e.key, 0, duration);
    }
  }
  return before;
}

/// [clearShowProgress] for widgets: also syncs, and returns the Undo action.
Future<VoidCallback> removeShowProgress(WidgetRef ref, String slug) async {
  final db = ref.read(dbProvider);
  final sync = ref.read(syncProvider.notifier);
  final removed = await clearShowProgress(db, slug);
  sync.syncSoon();
  return () async {
    await restoreProgress(db, removed);
    sync.syncSoon();
  };
}

/// [setEpisodesWatched] for widgets: also syncs, and returns the Undo action.
Future<VoidCallback> markEpisodes(WidgetRef ref, String slug, Map<String, int> episodes, {required bool watched}) async {
  final db = ref.read(dbProvider);
  final sync = ref.read(syncProvider.notifier);
  final before = await setEpisodesWatched(db, slug, episodes, watched: watched);
  sync.syncSoon();
  return () async {
    await restoreProgress(db, before);
    sync.syncSoon();
  };
}
