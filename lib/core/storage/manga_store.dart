part of 'app_db.dart';

/// Manga storage: series, cached chapter lists, reading state, the Updates
/// feed, categories and offline chapters.
extension MangaStore on AppDb {
  static const _categoriesKey = 'manga:categories';

  // ---- series -----------------------------------------------------------------
  MangaRecord? manga(String key) {
    final m = _manga.get(key);
    return m == null ? null : MangaRecord.fromMap(m as Map);
  }

  List<MangaRecord> allManga() => _manga.values.map((m) => MangaRecord.fromMap(m as Map)).toList();

  List<MangaRecord> libraryManga() => allManga().where((m) => m.inLibrary).toList();

  Future<void> putManga(MangaRecord m) => _manga.put(m.key, m.toMap());

  Future<void> setInLibrary(String key, bool inLibrary, {int? now}) async {
    final m = manga(key);
    if (m == null || m.inLibrary == inLibrary) return;
    await putManga(m.copyWith(
      inLibrary: inLibrary,
      addedAt: inLibrary ? (now ?? DateTime.now().millisecondsSinceEpoch) : m.addedAt,
    ));
  }

  Stream<List<MangaRecord>> watchManga() => _watch(_manga, allManga);

  // ---- chapters ---------------------------------------------------------------
  /// Cached chapters of a series, oldest first.
  List<ChapterRecord> chapters(String key) {
    final l = _mangaChapters.get(key);
    if (l is! List) return const [];
    return l.map((e) => ChapterRecord.fromMap(e as Map)).toList();
  }

  /// Saves a freshly fetched chapter list (oldest first) and returns the
  /// chapters that were not known before. The first fetch of a series returns
  /// nothing new. New chapters of library series go to the Updates feed.
  Future<List<ChapterRecord>> mergeChapters(String key, List<ChapterInfo> fetched, {int? now}) async {
    final at = now ?? DateTime.now().millisecondsSinceEpoch;
    final existing = {for (final c in chapters(key)) c.id: c};
    final firstFetch = existing.isEmpty;
    final merged = [
      for (final c in fetched) ChapterRecord.fromInfo(c, firstSeen: existing[c.id]?.firstSeen ?? at),
    ];
    final fresh = firstFetch ? const <ChapterRecord>[] : merged.where((c) => !existing.containsKey(c.id)).toList();
    await _mangaChapters.put(key, merged.map((c) => c.toMap()).toList());
    final m = manga(key);
    if (m != null) await putManga(m.copyWith(lastChecked: at));
    if (fresh.isNotEmpty && (m?.inLibrary ?? false)) {
      await _mangaUpdates.putAll({
        for (final c in fresh)
          ChapterState.keyOf(key, c.id): MangaUpdate(mangaKey: key, chapterId: c.id, foundAt: at).toMap(),
      });
    }
    return fresh;
  }

  Stream<int> watchChapterLists() => _watch(_mangaChapters, () => _mangaChapters.length);

  // ---- reading state ------------------------------------------------------------
  ChapterState? chapterState(String key, String chapterId) {
    final m = _mangaState.get(ChapterState.keyOf(key, chapterId));
    return m == null ? null : ChapterState.fromMap(m as Map);
  }

  /// Reading state of every chapter of a series, by chapter id.
  Map<String, ChapterState> chapterStates(String key) {
    final prefix = '$key|';
    return {
      for (final k in _mangaState.keys)
        if ((k as String).startsWith(prefix)) k.substring(prefix.length): ChapterState.fromMap(_mangaState.get(k) as Map),
    };
  }

  List<ChapterState> allChapterStates() => _mangaState.values.map((m) => ChapterState.fromMap(m as Map)).toList();

  Future<void> putChapterState(ChapterState s) => _mangaState.put(s.key, s.toMap());

  ChapterState _stateOrNew(String key, String chapterId) =>
      chapterState(key, chapterId) ?? ChapterState(mangaKey: key, chapterId: chapterId);

  Future<void> setRead(String key, Iterable<String> chapterIds, bool read, {int? now}) {
    final at = now ?? DateTime.now().millisecondsSinceEpoch;
    return _mangaState.putAll({
      for (final id in chapterIds)
        ChapterState.keyOf(key, id): _stateOrNew(key, id)
            .copyWith(read: read, page: read ? null : 0, offset: read ? null : 0, updatedAt: at)
            .toMap(),
    });
  }

  Future<void> setBookmarked(String key, Iterable<String> chapterIds, bool bookmarked, {int? now}) {
    final at = now ?? DateTime.now().millisecondsSinceEpoch;
    return _mangaState.putAll({
      for (final id in chapterIds)
        ChapterState.keyOf(key, id): _stateOrNew(key, id).copyWith(bookmarked: bookmarked, updatedAt: at).toMap(),
    });
  }

  /// Records where the reader is. A chapter becomes read once [finished] is
  /// true and stays read when it is opened again.
  Future<void> saveReading(
    String key,
    String chapterId, {
    required int page,
    required int pageCount,
    double offset = 0,
    bool finished = false,
    bool incognito = false,
    int? now,
  }) {
    final at = now ?? DateTime.now().millisecondsSinceEpoch;
    final cur = _stateOrNew(key, chapterId);
    final next = cur.copyWith(
      read: cur.read || finished,
      page: page,
      pageCount: pageCount,
      offset: offset.clamp(0.0, 1.0),
      readAt: incognito ? cur.readAt : at,
      updatedAt: at,
    );
    return putChapterState(next);
  }

  Stream<int> watchChapterStates() => _watch(_mangaState, () => _mangaState.length);

  // ---- history ----------------------------------------------------------------
  /// Last chapter opened per series, most recent first.
  List<(MangaRecord, ChapterState)> mangaHistory() {
    final latest = <String, ChapterState>{};
    for (final s in allChapterStates()) {
      if (s.readAt == null) continue;
      final cur = latest[s.mangaKey];
      if (cur == null || s.readAt! > cur.readAt!) latest[s.mangaKey] = s;
    }
    final out = <(MangaRecord, ChapterState)>[];
    for (final s in latest.values) {
      final m = manga(s.mangaKey);
      if (m != null) out.add((m, s));
    }
    out.sort((a, b) => b.$2.readAt!.compareTo(a.$2.readAt!));
    return out;
  }

  /// Removes a series from History; read marks and positions stay.
  Future<void> removeMangaHistory(String key) {
    final states = chapterStates(key).values.where((s) => s.readAt != null);
    return _mangaState.putAll({for (final s in states) s.key: s.copyWith(readAt: null).toMap()});
  }

  Future<void> clearMangaHistory() {
    final states = allChapterStates().where((s) => s.readAt != null);
    return _mangaState.putAll({for (final s in states) s.key: s.copyWith(readAt: null).toMap()});
  }

  // ---- updates feed -------------------------------------------------------------
  /// New chapters found by library refreshes, newest first.
  List<MangaUpdate> mangaUpdates() =>
      _mangaUpdates.values.map((m) => MangaUpdate.fromMap(m as Map)).toList()..sort((a, b) => b.foundAt.compareTo(a.foundAt));

  Future<void> clearMangaUpdates() => _mangaUpdates.clear();

  Stream<List<MangaUpdate>> watchMangaUpdates() => _watch(_mangaUpdates, mangaUpdates);

  // ---- categories -----------------------------------------------------------------
  List<String> mangaCategories() => ((_misc.get(_categoriesKey) as List?) ?? const []).cast<String>();

  Future<void> setMangaCategories(List<String> names) => _misc.put(_categoriesKey, names);

  // ---- offline chapters ---------------------------------------------------------------
  MangaDownloadRecord? mangaDownload(String key) {
    final m = _mangaDownloads.get(key);
    return m == null ? null : MangaDownloadRecord.fromMap(m as Map);
  }

  List<MangaDownloadRecord> allMangaDownloads() =>
      _mangaDownloads.values.map((m) => MangaDownloadRecord.fromMap(m as Map)).toList();

  Future<void> putMangaDownload(MangaDownloadRecord d) => _mangaDownloads.put(d.key, d.toMap());

  Future<void> deleteMangaDownload(String key) => _mangaDownloads.delete(key);

  Stream<List<MangaDownloadRecord>> watchMangaDownloads() => _watch(_mangaDownloads, allMangaDownloads);
}
