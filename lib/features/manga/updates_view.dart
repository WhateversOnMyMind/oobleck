import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../core/storage/app_db.dart';
import '../../core/storage/manga_records.dart';
import '../../ui/widgets.dart';
import '../reader/open_reader.dart';
import 'manga_detail_screen.dart';
import 'manga_logic.dart';
import 'manga_providers.dart';
import 'manga_strings.dart';
import 'manga_widgets.dart';

/// New chapters of library series, grouped by the day they were found.
class UpdatesView extends ConsumerWidget {
  const UpdatesView({super.key, required this.onRefresh});
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = Strings.of(context);
    final updates = ref.watch(mangaUpdatesProvider).value ?? const <MangaUpdate>[];
    ref.watch(chapterStateTickProvider);
    ref.watch(mangaRecordsProvider);
    final db = ref.read(dbProvider);
    final headers = ref.watch(mangaSourceProvider).imageHeaders;
    final refreshing = ref.watch(libraryRefresherProvider).running;

    final rows = <(MangaUpdate, MangaRecord, ChapterRecord)>[];
    final chapterCache = <String, Map<String, ChapterRecord>>{};
    for (final u in updates) {
      final m = db.manga(u.mangaKey);
      if (m == null || !m.inLibrary) continue;
      final byId = chapterCache.putIfAbsent(u.mangaKey, () => {for (final c in db.chapters(u.mangaKey)) c.id: c});
      final c = byId[u.chapterId];
      if (c != null) rows.add((u, m, c));
    }

    final body = rows.isEmpty
        ? ListView(children: [
            const SizedBox(height: 60),
            EmptyState(
              icon: Icons.new_releases_outlined,
              title: tr.updatesEmpty,
              message: tr.updatesEmptyHint,
              actionLabel: refreshing ? null : tr.checkForUpdates,
              onAction: refreshing ? null : () => unawaited(onRefresh()),
            ),
          ])
        : _list(context, ref, tr, rows, headers);
    return Column(children: [
      if (refreshing) const LinearProgressIndicator(minHeight: 2),
      Expanded(child: RefreshIndicator(onRefresh: onRefresh, child: body)),
    ]);
  }

  Widget _list(BuildContext context, WidgetRef ref, Strings tr, List<(MangaUpdate, MangaRecord, ChapterRecord)> rows,
      Map<String, String> headers) {
    final db = ref.read(dbProvider);
    final groups = groupByDay(rows, (r) => r.$1.foundAt);
    final now = DateTime.now();
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      for (final (day, items) in groups) ...[
        SectionHeader(dayLabel(tr, day, now)),
        for (final (_, m, c) in items)
          Builder(builder: (context) {
            final st = db.chapterState(m.key, c.id);
            final read = st?.read ?? false;
            return ListTile(
              leading: GestureDetector(
                onTap: () => openMangaDetail(context, m.key),
                child: MangaThumb(m, headers: headers),
              ),
              title: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: read ? Colors.white38 : null)),
              subtitle: Text(c.title, style: TextStyle(color: read ? Colors.white24 : Colors.white70)),
              trailing: IconButton(
                tooltip: read ? tr.markUnread : tr.markRead,
                icon: Icon(read ? Icons.remove_done_rounded : Icons.done_rounded),
                onPressed: () => db.setRead(m.key, [c.id], !read),
              ),
              onTap: () => openReader(context, mangaKey: m.key, chapterId: c.id),
              onLongPress: () => openMangaDetail(context, m.key),
            );
          }),
      ],
    ]);
  }
}

/// Recently read series, most recent first.
class HistoryView extends ConsumerWidget {
  const HistoryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = Strings.of(context);
    final items = ref.watch(mangaHistoryProvider);
    final db = ref.read(dbProvider);
    final headers = ref.watch(mangaSourceProvider).imageHeaders;
    if (items.isEmpty) {
      return Center(child: EmptyState(icon: Icons.history_rounded, title: tr.historyEmpty, message: tr.historyEmptyHint));
    }
    final now = DateTime.now();
    final groups = groupByDay(items, (r) => r.$2.readAt!);
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
      for (final (day, rows) in groups) ...[
        SectionHeader(dayLabel(tr, day, now)),
        for (final (m, st) in rows)
          Builder(builder: (context) {
            final chapters = db.chapters(m.key);
            final chapter = chapters.where((c) => c.id == st.chapterId).firstOrNull;
            final when = relativeTime(DateTime.fromMillisecondsSinceEpoch(st.readAt!), now,
                minutes: tr.agoMinutes, hours: tr.agoHours, yesterday: tr.yesterday, days: tr.daysAgo);
            final progress = st.read ? '' : (st.pageCount > 0 ? ' · ${tr.pageOf(st.page + 1, st.pageCount)}' : '');
            // A finished chapter resumes into the next one.
            final target = st.read ? (nextToRead(chapters, db.chapterStates(m.key)) ?? chapter) : chapter;
            return Dismissible(
              key: ValueKey('h-${m.key}'),
              direction: DismissDirection.endToStart,
              background: Container(
                color: Theme.of(context).colorScheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 24),
                child: const Icon(Icons.delete_outline_rounded),
              ),
              onDismissed: (_) => db.removeMangaHistory(m.key),
              child: ListTile(
                leading: GestureDetector(
                  onTap: () => openMangaDetail(context, m.key),
                  child: MangaThumb(m, headers: headers),
                ),
                title: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${chapter?.title ?? ''}$progress · $when', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: tr.removeFromHistory,
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => db.removeMangaHistory(m.key),
                ),
                onTap: target == null
                    ? () => openMangaDetail(context, m.key)
                    : () => openReader(context, mangaKey: m.key, chapterId: target.id),
              ),
            );
          }),
      ],
    ]);
  }

}

/// "Today", "Yesterday", "3 days ago", then the date.
String dayLabel(Strings tr, DateTime day, DateTime now) {
  final diff = DateTime(now.year, now.month, now.day).difference(day).inDays;
  if (diff == 0) return tr.today;
  if (diff == 1) return tr.yesterday;
  if (diff < 7) return tr.daysAgo(diff);
  return formatDate(day);
}
