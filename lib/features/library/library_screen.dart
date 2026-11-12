import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
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

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          title: const Text('Downloaded', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            if (pending.isNotEmpty)
              IconButton(
                tooltip: 'Pause all',
                icon: const Icon(Icons.pause_circle_outline_rounded),
                onPressed: () => ref.read(downloadManagerProvider).pauseAll(),
              ),
          ],
        ),
        if (shows.isEmpty && pending.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.download_for_offline_outlined,
              title: 'Nothing downloaded yet',
              message: 'Download episodes from any show page and they will appear here, ready to watch offline.',
            ),
          )
        else ...[
          if (shows.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, Gap.s),
                child: Text(
                  '${shows.length} ${shows.length == 1 ? 'show' : 'shows'} · $count ${count == 1 ? 'episode' : 'episodes'} · ${formatBytes(total)} used',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white60),
                ),
              ),
            ),
          if (pending.isNotEmpty) ...[
            SliverToBoxAdapter(child: SectionHeader('Downloading · ${pending.length}')),
            SliverList.builder(
              itemCount: pending.length,
              itemBuilder: (context, i) => _QueueTile(record: pending[i]),
            ),
          ],
          if (shows.isNotEmpty) ...[
            if (pending.isNotEmpty) const SliverToBoxAdapter(child: SectionHeader('Downloaded')),
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
                    subtitle: '$n ${n == 1 ? 'episode' : 'episodes'} · ${formatBytes(s.totalBytes)}',
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
    final status = switch (r.status) {
      DownloadStatus.queued => 'Waiting…',
      DownloadStatus.downloading =>
        '${(r.progress * 100).round()}%${r.speedBps > 0 ? ' · ${formatBytes(r.speedBps)}/s' : ''}',
      DownloadStatus.paused => 'Paused · ${(r.progress * 100).round()}%',
      DownloadStatus.failed => r.error ?? 'Failed',
      DownloadStatus.done => 'Done',
    };
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(width: 40, height: 56, child: PosterImage(url: show?.poster, localPath: show?.posterPath)),
      ),
      title: Text('${show?.title ?? r.slug} · Episode ${r.episode}', maxLines: 1, overflow: TextOverflow.ellipsis),
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
          IconButton(tooltip: 'Pause', icon: const Icon(Icons.pause_rounded), onPressed: () => mgr.pause(r.key))
        else
          IconButton(
            tooltip: r.status == DownloadStatus.failed ? 'Retry' : 'Resume',
            icon: Icon(r.status == DownloadStatus.failed ? Icons.refresh_rounded : Icons.play_arrow_rounded),
            onPressed: () => mgr.resume(r.key),
          ),
        IconButton(tooltip: 'Cancel', icon: const Icon(Icons.close_rounded), onPressed: () => mgr.cancel(r.key)),
      ]),
    );
  }
}
