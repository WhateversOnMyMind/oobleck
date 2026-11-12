import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../core/downloads/download_manager.dart';
import '../../core/storage/records.dart';
import '../../ui/widgets.dart';
import 'library_show_screen.dart';

/// Offline library: downloaded shows as poster cards. Everything here is
/// served from the local database and files, so it works with no internet.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shows = ref.watch(libraryProvider);
    final downloads = ref.watch(downloadsProvider).value ?? const <DownloadRecord>[];
    final pending = downloads.where((d) => !d.isDone).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final total = shows.fold<int>(0, (a, s) => a + s.totalBytes);
    final count = shows.fold<int>(0, (a, s) => a + s.episodes.length);
    final tr = Strings.of(context);

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          title: Text(tr.downloadedTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            if (pending.isNotEmpty)
              IconButton(
                tooltip: tr.pauseAll,
                icon: const Icon(Icons.pause_circle_outline_rounded),
                onPressed: () => ref.read(downloadManagerProvider).pauseAll(),
              ),
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
                child: Text(
                  tr.libraryLine(shows.length, count, formatBytes(total)),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white60),
                ),
              ),
            ),
          if (pending.isNotEmpty) ...[
            SliverToBoxAdapter(child: SectionHeader(tr.downloadingCount(pending.length))),
            SliverList.builder(
              itemCount: pending.length,
              itemBuilder: (context, i) => _QueueTile(record: pending[i]),
            ),
          ],
          if (shows.isNotEmpty) ...[
            if (pending.isNotEmpty) SliverToBoxAdapter(child: SectionHeader(tr.downloaded)),
            SliverPadding(
              padding: const EdgeInsets.all(Gap.m),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 170,
                  childAspectRatio: 0.52,
                  crossAxisSpacing: Gap.m,
                  mainAxisSpacing: Gap.m,
                ),
                itemCount: shows.length,
                itemBuilder: (context, i) {
                  final s = shows[i];
                  final n = s.episodes.length;
                  return PosterCard(
                    title: s.show.title,
                    url: s.show.poster,
                    localPath: s.show.posterPath,
                    subtitle: '${tr.episodeCount(n)} · ${formatBytes(s.totalBytes)}',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => LibraryShowScreen(slug: s.show.slug)),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
        const SliverToBoxAdapter(child: SizedBox(height: Gap.xl)),
      ],
    );
  }
}

class _QueueTile extends ConsumerWidget {
  const _QueueTile({required this.record});
  final DownloadRecord record;

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
        Text(status, style: t.bodySmall?.copyWith(color: r.status == DownloadStatus.failed ? Colors.redAccent : Colors.white60)),
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
        IconButton(tooltip: tr.cancel, icon: const Icon(Icons.close_rounded), onPressed: () => mgr.cancel(r.key)),
      ]),
    );
  }
}
