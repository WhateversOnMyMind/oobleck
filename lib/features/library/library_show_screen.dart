import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/strings_ui.dart';
import '../../app/theme.dart';
import '../../core/downloads/download_manager.dart';
import '../../core/models.dart';
import '../../core/storage/records.dart';
import '../../ui/feedback.dart';
import '../../ui/layout.dart';
import '../../ui/poster_app_bar.dart';
import '../../ui/widgets.dart';
import '../player/open_player.dart';
import '../player/play_request.dart';
import '../show/progress_actions.dart';

/// Episodes of one downloaded show. One tap plays in the in-app player.
class LibraryShowScreen extends ConsumerWidget {
  const LibraryShowScreen({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider).where((s) => s.show.slug == slug).firstOrNull;
    final tr = Strings.of(context);
    final history = {
      for (final h in ref.watch(historyProvider).value ?? const <HistoryEntry>[])
        if (h.slug == slug) h.episode: h
    };
    if (lib == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(icon: Icons.folder_off_outlined, title: tr.nothingDownloadedShow, message: tr.allRemoved),
      );
    }
    final show = lib.show;
    final t = Theme.of(context).textTheme;
    final eps = lib.episodes;
    final wide = MediaQuery.sizeOf(context).width >= 700;

    // Continue where you left off, or start at the first unwatched episode.
    final partial = eps.where((e) => history[e.episode]?.isPartial ?? false).toList()
      ..sort((a, b) => history[b.episode]!.updatedAt.compareTo(history[a.episode]!.updatedAt));
    final next = partial.firstOrNull ?? eps.where((e) => !(history[e.episode]?.isFinished ?? false)).firstOrNull ?? eps.first;
    final nextPartial = history[next.episode]?.isPartial ?? false;
    final playButton = FilledButton.icon(
      icon: const Icon(Icons.play_arrow_rounded),
      label: Text(nextPartial ? tr.resumeEpisode(next.episode) : tr.playEpisode(next.episode), maxLines: 1, overflow: TextOverflow.ellipsis),
      onPressed: () => _play(context, show.title, next),
    );
    final moreButton = OutlinedButton.icon(
      icon: const Icon(Icons.download_rounded),
      label: Text(tr.getMore),
      onPressed: () => _downloadNext(context, ref, lib),
    );

    return Scaffold(
      // Phones get the main actions in a bottom bar, within thumb reach.
      bottomNavigationBar: wide
          ? null
          : StickyActionBar(
              child: Row(children: [
                Expanded(child: playButton),
                const SizedBox(width: Gap.s),
                moreButton,
              ]),
            ),
      body: CustomScrollView(
        slivers: [
          PosterSliverAppBar(
            title: show.title,
            posterUrl: show.poster,
            posterPath: show.posterPath,
            expandedHeight: 260,
            actions: [
              PopupMenuButton<String>(
                tooltip: tr.more,
                onSelected: (v) async {
                  if (v != 'delete') return;
                  final ok = await confirmAction(context, title: tr.deleteShowTitle(show.title), message: tr.deleteShowBody(eps.length));
                  if (!ok) return;
                  await ref.read(downloadManagerProvider).deleteShow(slug);
                  if (!context.mounted) return;
                  showAppSnackBar(context, tr.deletedShow(show.title));
                  Navigator.of(context).pop();
                },
                itemBuilder: (_) => [PopupMenuItem(value: 'delete', child: Text(tr.deleteAllEpisodes))],
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.m),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(show.title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('${tr.episodeCount(eps.length)} · ${formatBytes(lib.totalBytes)}',
                    style: t.bodyMedium?.copyWith(color: Colors.white60)),
                if (show.synopsis.isNotEmpty) ...[
                  const SizedBox(height: Gap.s),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Text(show.synopsis, maxLines: 4, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: Colors.white70, height: 1.4)),
                  ),
                ],
                const SizedBox(height: Gap.m),
                if (wide) ...[
                  Row(children: [
                    ConstrainedBox(constraints: const BoxConstraints(minWidth: 240, maxWidth: 360), child: playButton),
                    const SizedBox(width: Gap.s),
                    moreButton,
                  ]),
                  const SizedBox(height: Gap.m),
                ],
              ]),
            ),
          ),
          SliverMaxWidth(
            maxWidth: 900,
            sliver: SliverList.builder(
              itemCount: eps.length,
              itemBuilder: (context, i) {
                final d = eps[i];
                return _EpisodeRow(
                  key: ValueKey(d.key),
                  record: d,
                  history: history[d.episode],
                  posterPath: show.posterPath,
                  posterUrl: show.poster,
                  onPlay: () => _play(context, show.title, d),
                  confirmDelete: () => confirmAction(context, title: tr.deleteEpisodeTitle(d.episode), message: tr.deleteEpisodeBody),
                  onDelete: () async {
                    await ref.read(downloadManagerProvider).deleteEpisode(d.key);
                    if (context.mounted) showAppSnackBar(context, tr.deletedEpisode(d.episode));
                  },
                  onToggleWatched: () async {
                    final watched = !(history[d.episode]?.isFinished ?? false);
                    final undo = await markEpisodes(ref, slug, {d.episode: d.durationMs}, watched: watched);
                    if (context.mounted) showAppSnackBar(context, watched ? tr.markedWatched(1) : tr.markedUnwatched(1), onUndo: undo);
                  },
                );
              },
            ),
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
    final tr = Strings.of(context);
    final count = await showActionSheet<int>(context, title: tr.downloadTheNext, actions: [
      for (final n in [1, 3, 5, 10]) SheetAction(value: n, icon: Icons.download_rounded, label: tr.nextEpisodes(n)),
    ]);
    if (count == null || !context.mounted) return;
    try {
      final bundle = await ref.read(showProvider(slug).future);
      final have = lib.episodes.map((e) => e.numeric).fold<double>(0, (a, b) => b > a ? b : a);
      final type = lib.episodes.last.type;
      final next = bundle.episodes.where((e) => e.numeric > have).take(count).toList();
      if (next.isEmpty) {
        if (context.mounted) showAppSnackBar(context, tr.allCaughtUp);
        return;
      }
      await ref.read(downloadManagerProvider).enqueue(bundle.detail, next, type, ref.read(settingsProvider).quality);
      if (context.mounted) showAppSnackBar(context, tr.addedToDownloads(next.length));
    } catch (_) {
      if (context.mounted) showAppSnackBar(context, tr.connectToDownload);
    }
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({
    super.key,
    required this.record,
    required this.history,
    required this.posterPath,
    required this.posterUrl,
    required this.onPlay,
    required this.confirmDelete,
    required this.onDelete,
    required this.onToggleWatched,
  });
  final DownloadRecord record;
  final HistoryEntry? history;
  final String? posterPath;
  final String? posterUrl;
  final VoidCallback onPlay;
  final Future<bool> Function() confirmDelete;
  final VoidCallback onDelete;
  final VoidCallback onToggleWatched;

  Future<void> _askDelete() async {
    if (await confirmDelete()) onDelete();
  }

  /// Long press / right click: the same actions as the ⋮ menu, in a sheet
  /// that is easier to reach on a phone.
  Future<void> _showActions(BuildContext context, bool watched) async {
    hapticTick();
    final tr = Strings.of(context);
    final picked = await showActionSheet<String>(context, title: tr.episode(record.episode), actions: [
      SheetAction(value: 'play', icon: Icons.play_arrow_rounded, label: tr.play),
      SheetAction(value: 'watched', icon: watched ? Icons.radio_button_unchecked_rounded : Icons.check_circle_outline_rounded, label: tr.markWatched(watched)),
      SheetAction(value: 'delete', icon: Icons.delete_outline_rounded, label: tr.deleteEpisode, destructive: true),
    ]);
    switch (picked) {
      case 'play':
        onPlay();
      case 'watched':
        onToggleWatched();
      case 'delete':
        await _askDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tr = Strings.of(context);
    final watched = history?.isFinished ?? false;
    final partial = history?.isPartial ?? false;
    final dur = record.durationMs > 0 ? record.durationMs : (history?.durationMs ?? 0);
    final meta = [
      if (dur > 0) formatDuration(Duration(milliseconds: dur)),
      formatBytes(record.totalBytes),
      if (record.quality.isNotEmpty) record.quality,
      record.type == AudioType.dub ? tr.dub : tr.sub,
    ].join(' · ');
    final row = InkWell(
      onTap: onPlay,
      onLongPress: () => _showActions(context, watched),
      onSecondaryTap: () => _showActions(context, watched),
      child: Padding(
        padding: const EdgeInsets.only(left: Gap.m, right: Gap.xs, top: Gap.s, bottom: Gap.s),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.small),
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
              Text(record.episodeTitle.isEmpty ? tr.episode(record.episode) : record.episodeTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: watched ? Colors.white54 : Colors.white)),
              const SizedBox(height: 2),
              Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: Colors.white54)),
            ]),
          ),
          if (watched) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.check_circle_rounded, color: kAccent, size: 20)),
          PopupMenuButton<String>(
            tooltip: tr.more,
            onSelected: (v) => v == 'delete' ? _askDelete() : onToggleWatched(),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'watched', child: Text(tr.markWatched(watched))),
              PopupMenuItem(value: 'delete', child: Text(tr.deleteEpisode)),
            ],
          ),
        ]),
      ),
    );
    // Swipe left to delete; it still asks first, because the file is gone for good.
    return Dismissible(
      key: ValueKey('dismiss-${record.key}'),
      direction: DismissDirection.endToStart,
      // The row leaves the list when the download is gone from the database,
      // so the swipe itself never removes it.
      confirmDismiss: (_) async {
        await _askDelete();
        return false;
      },
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: Gap.l),
        child: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.onErrorContainer),
      ),
      child: row,
    );
  }
}
