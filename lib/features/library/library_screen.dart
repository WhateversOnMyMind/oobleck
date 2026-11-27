import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/strings_ui.dart';
import '../../app/theme.dart';
import '../../core/downloads/download_manager.dart';
import '../../core/storage/records.dart';
import '../../ui/feedback.dart';
import '../../ui/layout.dart';
import '../../ui/widgets.dart';
import 'library_show_screen.dart';
import 'library_sort.dart';

/// Offline library: downloaded shows as poster cards. Everything here is
/// served from the local database and files, so it works with no internet.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(librarySortProvider);
    final shows = sortLibrary(ref.watch(libraryProvider), sort);
    final downloads = ref.watch(downloadsProvider).value ?? const <DownloadRecord>[];
    final pending = downloads.where((d) => !d.isDone).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final running = pending.any((d) => d.status == DownloadStatus.downloading || d.status == DownloadStatus.queued);
    final total = shows.fold<int>(0, (a, s) => a + s.totalBytes);
    final count = shows.fold<int>(0, (a, s) => a + s.episodes.length);
    final tr = Strings.of(context);
    final mgr = ref.read(downloadManagerProvider);

    return CustomScrollView(
      key: const PageStorageKey<String>('downloaded'),
      slivers: [
        SliverAppBar(
          floating: true,
          title: Text(tr.downloadedTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            if (shows.length > 1)
              PopupMenuButton<LibrarySort>(
                tooltip: tr.sortBy,
                icon: const Icon(Icons.sort_rounded),
                initialValue: sort,
                onSelected: ref.read(librarySortProvider.notifier).set,
                itemBuilder: (_) => [
                  for (final e in {LibrarySort.title: tr.sortTitle, LibrarySort.recent: tr.sortRecent, LibrarySort.size: tr.sortSize}.entries)
                    CheckedPopupMenuItem(value: e.key, checked: e.key == sort, child: Text(e.value)),
                ],
              ),
            const SizedBox(width: Gap.xs),
          ],
        ),
        if (shows.isEmpty && pending.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.download_for_offline_outlined,
              title: tr.nothingDownloaded,
              message: tr.nothingDownloadedHint,
            ),
          )
        else ...[
          if (shows.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, Gap.s),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: _StorageSummary(line: '${tr.showCount(shows.length)} · ${tr.episodeCount(count)}', bytes: formatBytes(total)),
                  ),
                ),
              ),
            ),
          if (pending.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                tr.downloadingCount(pending.length),
                trailing: TextButton.icon(
                  icon: Icon(running ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  label: Text(running ? tr.pauseAll : tr.resumeAll),
                  onPressed: running ? mgr.pauseAll : mgr.resumeAll,
                ),
              ),
            ),
            SliverMaxWidth(
              maxWidth: 900,
              sliver: SliverList.builder(
                itemCount: pending.length,
                itemBuilder: (context, i) => _QueueTile(record: pending[i]),
              ),
            ),
          ],
          if (shows.isNotEmpty) ...[
            if (pending.isNotEmpty) SliverToBoxAdapter(child: SectionHeader(tr.downloaded)),
            SliverPadding(
              padding: const EdgeInsets.all(Gap.m),
              sliver: SliverLayoutBuilder(
                builder: (context, c) => SliverGrid.builder(
                  gridDelegate: posterGridDelegate(context, c.crossAxisExtent + Gap.m * 2, subtitle: true),
                  itemCount: shows.length,
                  itemBuilder: (context, i) {
                    final s = shows[i];
                    void open() => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => LibraryShowScreen(slug: s.show.slug)),
                        );
                    return PosterCard(
                      title: s.show.title,
                      url: s.show.poster,
                      localPath: s.show.posterPath,
                      subtitle: '${tr.episodeCount(s.episodes.length)} · ${formatBytes(s.totalBytes)}',
                      onTap: open,
                      onLongPress: () => _showActions(context, ref, s, open),
                    );
                  },
                ),
              ),
            ),
          ],
        ],
        const SliverToBoxAdapter(child: SizedBox(height: Gap.xl)),
      ],
    );
  }

  Future<void> _showActions(BuildContext context, WidgetRef ref, LibraryShow s, VoidCallback open) async {
    hapticTick();
    final tr = Strings.of(context);
    final picked = await showActionSheet<String>(context, title: s.show.title, actions: [
      SheetAction(value: 'open', icon: Icons.format_list_bulleted_rounded, label: tr.openEpisodes),
      SheetAction(value: 'delete', icon: Icons.delete_outline_rounded, label: tr.deleteShow, destructive: true),
    ]);
    if (picked == null || !context.mounted) return;
    if (picked == 'open') {
      open();
      return;
    }
    final ok = await confirmAction(context, title: tr.deleteShowTitle(s.show.title), message: tr.deleteShowBody(s.episodes.length));
    if (!ok) return;
    await ref.read(downloadManagerProvider).deleteShow(s.show.slug);
    if (context.mounted) showAppSnackBar(context, tr.deletedShow(s.show.title));
  }
}

/// How much is downloaded and how much space it takes, at a glance.
class _StorageSummary extends StatelessWidget {
  const _StorageSummary({required this.line, required this.bytes});
  final String line;
  final String bytes;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tr = Strings.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: 12),
        child: Row(children: [
          const Icon(Icons.sd_storage_outlined, color: kAccent),
          const SizedBox(width: Gap.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$bytes ${tr.storageUsedOnDevice}', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(line, style: t.bodySmall?.copyWith(color: Colors.white60)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _QueueTile extends ConsumerWidget {
  const _QueueTile({required this.record});
  final DownloadRecord record;

  Future<void> _cancel(BuildContext context, DownloadManager mgr) async {
    final tr = Strings.of(context);
    // Nothing is lost by dropping a download that has not started.
    if (record.progress > 0) {
      final ok = await confirmAction(context, title: tr.cancelDownloadQ, message: tr.cancelDownloadBody, confirmLabel: tr.cancelDownload, cancelLabel: tr.keepDownloading);
      if (!ok) return;
    }
    await mgr.cancel(record.key);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(dbProvider);
    final show = db.show(record.slug);
    final mgr = ref.read(downloadManagerProvider);
    final t = Theme.of(context).textTheme;
    final r = record;
    final tr = Strings.of(context);
    final status = switch (r.status) {
      DownloadStatus.queued => tr.waiting,
      DownloadStatus.downloading =>
        '${(r.progress * 100).round()}%${r.speedBps > 0 ? ' · ${formatBytes(r.speedBps)}/s' : ''}',
      DownloadStatus.paused => tr.pausedAt((r.progress * 100).round()),
      DownloadStatus.failed => r.error ?? tr.failed,
      DownloadStatus.done => tr.done,
    };
    return ListTile(
      contentPadding: const EdgeInsets.only(left: Gap.m, right: Gap.s),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(width: 40, height: 56, child: PosterImage(url: show?.poster, localPath: show?.posterPath)),
      ),
      title: Text('${show?.title ?? r.slug} · ${tr.episode(r.episode)}', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: r.status == DownloadStatus.queued ? null : r.progress,
            minHeight: 4,
            backgroundColor: Colors.white12,
          ),
        ),
        const SizedBox(height: 4),
        Text(status,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall?.copyWith(color: r.status == DownloadStatus.failed ? Colors.redAccent : Colors.white60)),
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (r.status == DownloadStatus.downloading || r.status == DownloadStatus.queued)
          IconButton(tooltip: tr.pause, icon: const Icon(Icons.pause_rounded), onPressed: () => mgr.pause(r.key))
        else
          IconButton(
            tooltip: r.status == DownloadStatus.failed ? tr.retry : tr.resume,
            icon: Icon(r.status == DownloadStatus.failed ? Icons.refresh_rounded : Icons.play_arrow_rounded),
            onPressed: () => mgr.resume(r.key),
          ),
        IconButton(tooltip: tr.cancelDownload, icon: const Icon(Icons.close_rounded), onPressed: () => _cancel(context, mgr)),
      ]),
    );
  }
}
