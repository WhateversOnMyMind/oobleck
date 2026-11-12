import 'dart:async';

import 'package:hive_ce/hive.dart';

import 'records.dart';

/// Local database (Hive CE, JSON-ish maps). Decision recorded in DECISIONS.md.
class AppDb {
  AppDb._(this._shows, this._episodes, this._history, this._downloads, this._settings, this._misc);

  final Box<dynamic> _shows;
  final Box<dynamic> _episodes;
  final Box<dynamic> _history;
  final Box<dynamic> _downloads;
  final Box<dynamic> _settings;
  final Box<dynamic> _misc;

  static Future<AppDb> open(String dir) async {
    Hive.init(dir);
    return AppDb._(
      await Hive.openBox<dynamic>('shows'),
      await Hive.openBox<dynamic>('episodes'),
      await Hive.openBox<dynamic>('history'),
      await Hive.openBox<dynamic>('downloads'),
      await Hive.openBox<dynamic>('settings'),
      await Hive.openBox<dynamic>('misc'),
    );
  }

  Future<void> close() => Hive.close();

  // ---- generic change streams -------------------------------------------
  Stream<T> _watch<T>(Box<dynamic> box, T Function() read) async* {
    yield read();
    await for (final _ in box.watch()) {
      yield read();
    }
  }

  // ---- shows --------------------------------------------------------------
  ShowRecord? show(String slug) {
    final m = _shows.get(slug);
    return m == null ? null : ShowRecord.fromMap(m as Map);
  }

  Future<void> putShow(ShowRecord s) => _shows.put(s.slug, s.toMap());

  List<ShowRecord> allShows() => _shows.values.map((m) => ShowRecord.fromMap(m as Map)).toList();

  Future<void> deleteShow(String slug) => _shows.delete(slug);

  // ---- cached episode lists ---------------------------------------------
  List<EpisodeRecord> episodes(String slug) {
    final l = _episodes.get(slug);
    if (l is! List) return const [];
    return l.map((e) => EpisodeRecord.fromMap(e as Map)).toList();
  }

  Future<void> putEpisodes(String slug, List<EpisodeRecord> eps) =>
      _episodes.put(slug, eps.map((e) => e.toMap()).toList());

  // ---- history ----------------------------------------------------------
  HistoryEntry? historyFor(String slug, String episode) {
    final m = _history.get(HistoryEntry.keyOf(slug, episode));
    return m == null ? null : HistoryEntry.fromMap(m as Map);
  }

  List<HistoryEntry> allHistory() =>
      _history.values.map((m) => HistoryEntry.fromMap(m as Map)).toList();

  Future<void> saveProgress(String slug, String episode, int positionMs, int durationMs, {int? now}) {
    final e = HistoryEntry(
      slug: slug,
      episode: episode,
      positionMs: positionMs,
      durationMs: durationMs,
      updatedAt: now ?? DateTime.now().millisecondsSinceEpoch,
    );
    return _history.put(e.key, e.toMap());
  }

  Future<void> markWatched(String slug, String episode, {int durationMs = 1}) =>
      saveProgress(slug, episode, durationMs, durationMs);

  Future<void> clearHistory({int? now}) async {
    await _history.clear();
    await _queueSyncDeletion('*', now);
  }

  Future<void> clearShowHistory(String slug, {int? now}) async {
    final keys = _history.keys.where((k) => (k as String).startsWith('$slug|')).toList();
    await _history.deleteAll(keys);
    await _queueSyncDeletion(slug, now);
  }

  /// Writes history that came from the sync server (keeps its `updatedAt`).
  Future<void> putHistory(Iterable<HistoryEntry> entries) =>
      _history.putAll({for (final e in entries) e.key: e.toMap()});

  Future<void> deleteHistory(Iterable<String> keys) => _history.deleteAll(keys);

  /// When signed in to sync, a clear is sent to the server so other devices
  /// drop the same entries (see `core/sync`).
  static const syncTokenKey = 'sync:token';
  static const syncPendingDeletionsKey = 'sync:pendingDeletions';

  Future<void> _queueSyncDeletion(String slug, int? now) async {
    if (_misc.get(syncTokenKey) == null) return;
    final at = now ?? DateTime.now().millisecondsSinceEpoch;
    final list = [...((_misc.get(syncPendingDeletionsKey) as List?) ?? const [])];
    list.add({'slug': slug, 'at': at});
    await _misc.put(syncPendingDeletionsKey, list);
  }

  Stream<List<HistoryEntry>> watchHistory() => _watch(_history, allHistory);

  // ---- downloads ----------------------------------------------------------
  DownloadRecord? download(String key) {
    final m = _downloads.get(key);
    return m == null ? null : DownloadRecord.fromMap(m as Map);
  }

  List<DownloadRecord> allDownloads() =>
      _downloads.values.map((m) => DownloadRecord.fromMap(m as Map)).toList();

  Future<void> putDownload(DownloadRecord d) => _downloads.put(d.key, d.toMap());

  Future<void> deleteDownload(String key) => _downloads.delete(key);

  Stream<List<DownloadRecord>> watchDownloads() => _watch(_downloads, allDownloads);

  // ---- settings & misc ---------------------------------------------------------
  T? setting<T>(String key) => _settings.get(key) as T?;
  Future<void> setSetting(String key, Object? value) =>
      value == null ? _settings.delete(key) : _settings.put(key, value);
  Stream<int> watchSettings() => _watch(_settings, () => _settings.length + DateTime.now().microsecondsSinceEpoch);

  T? misc<T>(String key) => _misc.get(key) as T?;
  Future<void> setMisc(String key, Object? value) =>
      value == null ? _misc.delete(key) : _misc.put(key, value);
}

/// Pure logic for the home "Continue watching" row.
class ContinueItem {
  ContinueItem({required this.show, required this.episode, required this.entry, required this.resumeFraction});
  final ShowRecord show;

  /// Episode to play (the next one when the last was finished).
  final String episode;

  /// Progress entry for [episode], if any.
  final HistoryEntry? entry;
  final double resumeFraction;
}

List<ContinueItem> buildContinueWatching({
  required List<HistoryEntry> history,
  required Map<String, ShowRecord> shows,
  required Map<String, List<String>> knownEpisodes,
  int limit = 20,
}) {
  final bySlug = <String, HistoryEntry>{};
  for (final h in history) {
    final cur = bySlug[h.slug];
    if (cur == null || h.updatedAt > cur.updatedAt) bySlug[h.slug] = h;
  }
  final sorted = bySlug.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  final out = <ContinueItem>[];
  for (final h in sorted) {
    final show = shows[h.slug];
    if (show == null) continue;
    if (!h.isFinished) {
      if (h.positionMs <= 0) continue;
      out.add(ContinueItem(show: show, episode: h.episode, entry: h, resumeFraction: h.fraction));
    } else {
      final nums = (knownEpisodes[h.slug] ?? const <String>[])
          .where((e) => (double.tryParse(e) ?? 0) > (double.tryParse(h.episode) ?? 0))
          .toList()
        ..sort((a, b) => (double.tryParse(a) ?? 0).compareTo(double.tryParse(b) ?? 0));
      if (nums.isEmpty) continue;
      final next = nums.first;
      final nextEntry = history.where((x) => x.slug == h.slug && x.episode == next).firstOrNull;
      out.add(ContinueItem(
        show: show,
        episode: next,
        entry: nextEntry,
        resumeFraction: nextEntry == null || nextEntry.isFinished ? 0 : nextEntry.fraction,
      ));
    }
    if (out.length >= limit) break;
  }
  return out;
}
