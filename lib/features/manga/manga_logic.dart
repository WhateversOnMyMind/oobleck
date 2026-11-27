import '../../core/manga/manga_models.dart';
import '../../core/storage/manga_records.dart';

/// Which chapter "Continue" should open, given chapters oldest first.
/// - the chapter opened last, when it is not finished;
/// - otherwise the first unread chapter after it;
/// - with no history, the first unread chapter (or the first chapter).
/// Null when every chapter is read and there is nothing after the last one.
ChapterRecord? nextToRead(List<ChapterRecord> chapters, Map<String, ChapterState> states) {
  if (chapters.isEmpty) return null;
  ChapterState? last;
  for (final s in states.values) {
    if (s.readAt == null) continue;
    if (last == null || s.readAt! > last.readAt!) last = s;
  }
  final lastIndex = last == null ? -1 : chapters.indexWhere((c) => c.id == last!.chapterId);
  if (lastIndex >= 0) {
    if (!(states[chapters[lastIndex].id]?.read ?? false)) return chapters[lastIndex];
    for (var i = lastIndex + 1; i < chapters.length; i++) {
      if (!(states[chapters[i].id]?.read ?? false)) return chapters[i];
    }
    return null;
  }
  for (final c in chapters) {
    if (!(states[c.id]?.read ?? false)) return c;
  }
  return null;
}

int unreadCount(List<ChapterRecord> chapters, Map<String, ChapterState> states) =>
    chapters.where((c) => !(states[c.id]?.read ?? false)).length;

/// Chapters to mark read with "Mark previous as read": everything before
/// [chapterId] in reading order (oldest first list).
List<String> previousChapterIds(List<ChapterRecord> chapters, String chapterId) {
  final i = chapters.indexWhere((c) => c.id == chapterId);
  return i <= 0 ? const [] : [for (final c in chapters.take(i)) c.id];
}

/// The chapter before / after [chapterId] in reading order.
(ChapterRecord?, ChapterRecord?) neighbours(List<ChapterRecord> chapters, String chapterId) {
  final i = chapters.indexWhere((c) => c.id == chapterId);
  if (i < 0) return (null, null);
  return (i > 0 ? chapters[i - 1] : null, i + 1 < chapters.length ? chapters[i + 1] : null);
}

/// One series in the library with what the grid needs to draw it.
class LibraryEntry {
  LibraryEntry({
    required this.manga,
    required this.total,
    required this.unread,
    required this.downloaded,
    required this.lastReadAt,
    required this.latestChapterAt,
    required this.next,
  });

  final MangaRecord manga;
  final int total;
  final int unread;
  final int downloaded;
  final int lastReadAt;

  /// When the newest chapter appeared (upload date, or when we first saw it).
  final int latestChapterAt;
  final ChapterRecord? next;

  bool get started => lastReadAt > 0;
}

LibraryEntry libraryEntryFor(
  MangaRecord m,
  List<ChapterRecord> chapters,
  Map<String, ChapterState> states,
  Set<String> downloadedIds,
) {
  var lastRead = 0;
  for (final s in states.values) {
    if ((s.readAt ?? 0) > lastRead) lastRead = s.readAt!;
  }
  var latest = 0;
  for (final c in chapters) {
    final t = c.uploaded ?? c.firstSeen;
    if (t > latest) latest = t;
  }
  return LibraryEntry(
    manga: m,
    total: chapters.length,
    unread: unreadCount(chapters, states),
    downloaded: chapters.where((c) => downloadedIds.contains(c.id)).length,
    lastReadAt: lastRead,
    latestChapterAt: latest,
    next: nextToRead(chapters, states),
  );
}

enum LibrarySort {
  lastRead,
  lastUpdate,
  title,
  unread,
  added;

  static LibrarySort parse(String? s) => values.asNameMap()[s] ?? lastRead;
}

class LibraryFilter {
  const LibraryFilter({this.unread = false, this.started = false, this.downloaded = false, this.completed = false});
  final bool unread;
  final bool started;
  final bool downloaded;
  final bool completed;

  bool get any => unread || started || downloaded || completed;

  bool accepts(LibraryEntry e) =>
      (!unread || e.unread > 0) &&
      (!started || e.started) &&
      (!downloaded || e.downloaded > 0) &&
      (!completed || e.manga.status == MangaStatus.completed);
}

List<LibraryEntry> arrangeLibrary(
  List<LibraryEntry> all, {
  LibrarySort sort = LibrarySort.lastRead,
  bool descending = true,
  LibraryFilter filter = const LibraryFilter(),
  String? category,
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  final out = all
      .where((e) => category == null || e.manga.categories.contains(category))
      .where(filter.accepts)
      .where((e) => q.isEmpty || e.manga.title.toLowerCase().contains(q) || e.manga.author.toLowerCase().contains(q))
      .toList();
  int cmp(LibraryEntry a, LibraryEntry b) => switch (sort) {
        LibrarySort.lastRead => a.lastReadAt.compareTo(b.lastReadAt),
        LibrarySort.lastUpdate => a.latestChapterAt.compareTo(b.latestChapterAt),
        LibrarySort.title => a.manga.title.toLowerCase().compareTo(b.manga.title.toLowerCase()),
        LibrarySort.unread => a.unread.compareTo(b.unread),
        LibrarySort.added => a.manga.addedAt.compareTo(b.manga.addedAt),
      };
  out.sort((a, b) {
    final c = descending ? cmp(b, a) : cmp(a, b);
    return c != 0 ? c : a.manga.title.toLowerCase().compareTo(b.manga.title.toLowerCase());
  });
  return out;
}

/// Groups items by calendar day (local time), newest day first.
List<(DateTime, List<T>)> groupByDay<T>(List<T> items, int Function(T) millis) {
  final groups = <DateTime, List<T>>{};
  for (final it in items) {
    final t = DateTime.fromMillisecondsSinceEpoch(millis(it));
    groups.putIfAbsent(DateTime(t.year, t.month, t.day), () => []).add(it);
  }
  final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final d in days) (d, groups[d]!)];
}

/// Chapter list as shown on the detail screen.
List<ChapterRecord> visibleChapters(
  List<ChapterRecord> chapters,
  Map<String, ChapterState> states,
  Set<String> downloadedIds, {
  required bool newestFirst,
  String filter = 'all',
}) {
  final out = chapters.where((c) {
    final s = states[c.id];
    return switch (filter) {
      'unread' => !(s?.read ?? false),
      'downloaded' => downloadedIds.contains(c.id),
      'bookmarked' => s?.bookmarked ?? false,
      _ => true,
    };
  }).toList();
  return newestFirst ? out.reversed.toList() : out;
}
