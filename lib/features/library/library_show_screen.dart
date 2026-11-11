import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/downloads/download_manager.dart';
import '../../core/storage/records.dart';
import '../../ui/widgets.dart';
import '../player/open_player.dart';
import '../player/play_request.dart';

/// Episodes of one downloaded show. One tap plays in the in-app player.
class LibraryShowScreen extends ConsumerWidget {
  const LibraryShowScreen({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider).where((s) => s.show.slug == slug).firstOrNull;
    final history = {
      for (final h in ref.watch(historyProvider).value ?? const <HistoryEntry>[])
        if (h.slug == slug) h.episode: h
    };
    if (lib == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.folder_off_outlined, title: 'Nothing downloaded', message: 'All episodes of this show were removed.'),
      );
    }
    final show = lib.show;
    final t = Theme.of(context).textTheme;
    final eps = lib.episodes;

    // Continue where you left off, or start at the first unwatched episode.
    DownloadRecord? next;
    final partial = eps.where((e) => history[e.episode]?.isPartial ?? false).toList()
      ..sort((a, b) => history[b.episode]!.updatedAt.compareTo(history[a.episode]!.updatedAt));
    next = partial.firstOrNull ?? eps.where((e) => !(history[e.episode]?.isFinished ?? false)).firstOrNull ?? eps.first;
    final nextPartial = history[next.episode]?.isPartial ?? false;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 260,
            actions: [
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'delete') {
                    final ok = await _confirm(context, 'Delete ${show.title}?', 'All ${eps.length} downloaded episodes will be removed from this device.');
                    if (ok) {
                      await ref.read(downloadManagerProvider).deleteShow(slug);
                      if (context.mounted) Navigator.of(context).pop();
                    }
                  }
                },
                itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete all episodes'))],
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(fit: StackFit.expand, children: [
                PosterImage(url: show.poster, localPath: show.posterPath),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x66000000), Color(0x00000000), kBackground],
                      stops: [0, 0.35, 1],
                    ),
                  ),
                ),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.m),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(show.title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${eps.length} ${eps.length == 1 ? 'episode' : 'episodes'} · ${formatBytes(lib.totalBytes)}',
                    style: t.bodyMedium?.copyWith(color: Colors.white60)),
                if (show.synopsis.isNotEmpty) ...[
                  const SizedBox(height: Gap.s),
                  Text(show.synopsis, maxLines: 4, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: Colors.white70, height: 1.4)),
                ],
                const SizedBox(height: Gap.m),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(nextPartial ? 'Resume episode ${next.episode}' : 'Play episode ${next.episode}'),
                      onPressed: () => _play(context, show.title, next!),
                    ),
                  ),
                  const SizedBox(width: Gap.s),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Get more'),
                    onPressed: () => _downloadNext(context, ref, lib),
                  ),
                ]),
                const SizedBox(height: Gap.m),
              ]),
            ),
          ),
          SliverList.builder(
            itemCount: eps.length,
            itemBuilder: (context, i) {
              final d = eps[i];
              final h = history[d.episode];
              return _EpisodeRow(
                record: d,
                history: h,
                show: show.title,
                posterPath: show.posterPath,
                posterUrl: show.poster,
                onPlay: () => _play(context, show.title, d),
                onDelete: () async {
                  final ok = await _confirm(context, 'Delete episode ${d.episode}?', 'It will be removed from this device.');
                  if (ok) await ref.read(downloadManagerProvider).deleteEpisode(d.key);
                },
                onToggleWatched: () {
                  final db = ref.read(dbProvider);
                  if (h?.isFinished ?? false) {
                    db.saveProgress(slug, d.episode, 0, h!.durationMs);
                  } else {
                    db.markWatched(slug, d.episode, durationMs: d.durationMs > 0 ? d.durationMs : 1);
                  }
                },
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: Gap.xl)),
        ],
      ),
    );
  }

  void _play(BuildContext context, String title, DownloadRecord d) {
    openPlayer(context, PlayRequest(slug: slug, showTitle: title, episode: d.episode, type: d.type));
  }

  Future<void> _downloadNext(BuildContext context, WidgetRef ref, LibraryShow lib) async {
    final count = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(Gap.m), child: Text('Download the next…', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
          for (final n in [1, 3, 5, 10])
            ListTile(title: Text(n == 1 ? 'Next episode' : 'Next $n episodes'), onTap: () => Navigator.pop(ctx, n)),
        ]),
      ),
    );
    if (count == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bundle = await ref.read(showProvider(slug).future);
      final have = lib.episodes.map((e) => e.numeric).fold<double>(0, (a, b) => b > a ? b : a);
      final type = lib.episodes.last.type;
      final next = bundle.episodes.where((e) => e.numeric > have).take(count).toList();
      if (next.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text("You're all caught up.")));
        return;
      }
      await ref.read(downloadManagerProvider).enqueue(bundle.detail, next, type, ref.read(settingsProvider).quality);
      messenger.showSnackBar(SnackBar(content: Text('Added ${next.length} to downloads')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Connect to the internet to download more episodes.')));
    }
  }

  Future<bool> _confirm(BuildContext context, String title, String message) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    return r ?? false;
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    required this.record,
    required this.history,
    required this.show,
    required this.posterPath,
    required this.posterUrl,
    required this.onPlay,
    required this.onDelete,
    required this.onToggleWatched,
  });
  final DownloadRecord record;
  final HistoryEntry? history;
  final String show;
  final String? posterPath;
  final String? posterUrl;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  final VoidCallback onToggleWatched;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final watched = history?.isFinished ?? false;
    final partial = history?.isPartial ?? false;
    final dur = record.durationMs > 0 ? record.durationMs : (history?.durationMs ?? 0);
    final meta = [
      if (dur > 0) formatDuration(Duration(milliseconds: dur)),
      formatBytes(record.totalBytes),
      if (record.quality.isNotEmpty) record.quality,
      record.type.label,
    ].join(' · ');
    return InkWell(
      onTap: onPlay,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: 8),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 120,
              height: 68,
              child: Stack(fit: StackFit.expand, children: [
                PosterImage(url: posterUrl, localPath: posterPath),
                Container(color: Colors.black38),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.play_arrow_rounded, size: 22),
                  ),
                ),
                Positioned(
                  left: 6,
                  top: 4,
                  child: Text('E${record.episode}', style: t.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (partial)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(value: history!.fraction, minHeight: 3, backgroundColor: Colors.black54),
                  ),
              ]),
            ),
          ),
          const SizedBox(width: Gap.m),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(record.episodeTitle.isEmpty ? 'Episode ${record.episode}' : record.episodeTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: watched ? Colors.white54 : Colors.white)),
              const SizedBox(height: 2),
              Text(meta, style: t.bodySmall?.copyWith(color: Colors.white54)),
            ]),
          ),
          if (watched) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.check_circle_rounded, color: kAccent, size: 20)),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'delete' ? onDelete() : onToggleWatched(),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'watched', child: Text(watched ? 'Mark as unwatched' : 'Mark as watched')),
              const PopupMenuItem(value: 'delete', child: Text('Delete episode')),
            ],
          ),
        ]),
      ),
    );
  }
}
