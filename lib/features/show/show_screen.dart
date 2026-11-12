import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../core/downloads/download_manager.dart';
import '../../core/models.dart';
import '../../core/storage/records.dart';
import '../../ui/widgets.dart';
import '../player/open_player.dart';
import '../player/play_request.dart';

class ShowScreen extends ConsumerStatefulWidget {
  const ShowScreen({super.key, required this.slug});
  final String slug;
  @override
  ConsumerState<ShowScreen> createState() => _ShowScreenState();
}

class _ShowScreenState extends ConsumerState<ShowScreen> {
  AudioType? _type;
  final Set<String> _selected = {};
  bool _expanded = false;

  /// Cached copy used when the network is unavailable.
  ShowBundle? _cached() {
    final db = ref.read(dbProvider);
    final rec = db.show(widget.slug);
    final eps = db.episodes(widget.slug);
    if (rec == null) return null;
    return ShowBundle(
      ShowDetail(
        slug: rec.slug,
        siteId: rec.siteId,
        title: rec.title,
        url: rec.url,
        poster: rec.poster,
        synopsis: rec.synopsis,
        malId: rec.malId,
      ),
      eps.map((e) => e.toInfo()).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(showProvider(widget.slug));
    return Scaffold(
      body: async.when(
        loading: () => const _ShowSkeleton(),
        error: (e, _) {
          final c = _cached();
          if (c == null) {
            return Scaffold(
              appBar: AppBar(),
              body: ErrorState(error: e, onRetry: () => ref.invalidate(showProvider(widget.slug))),
            );
          }
          return _content(c, offline: true);
        },
        data: (b) => _content(b),
      ),
    );
  }

  Widget _content(ShowBundle b, {bool offline = false}) {
    final settings = ref.watch(settingsProvider);
    final type = _type ?? settings.audio;
    final history = {for (final h in ref.watch(historyProvider).value ?? const <HistoryEntry>[]) if (h.slug == widget.slug) h.episode: h};
    final downloads = {
      for (final d in ref.watch(downloadsProvider).value ?? const <DownloadRecord>[])
        if (d.slug == widget.slug) d.episode: d
    };
    final eps = b.episodes;
    final hasDub = eps.any((e) => e.hasDub);
    final t = Theme.of(context).textTheme;
    final tr = Strings.of(context);

    // Resume target: most recently watched unfinished episode, else the first unwatched.
    EpisodeInfo? target;
    if (eps.isNotEmpty) {
      final partial = history.values.where((h) => h.isPartial).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (partial.isNotEmpty) {
        target = eps.where((e) => e.number == partial.first.episode).firstOrNull;
      }
      target ??= eps.where((e) => !(history[e.number]?.isFinished ?? false)).firstOrNull ?? eps.first;
    }
    final targetHist = target == null ? null : history[target.number];

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 280,
          leading: BackButton(onPressed: () => _selected.isNotEmpty ? setState(_selected.clear) : Navigator.of(context).pop()),
          title: _selected.isNotEmpty ? Text(tr.selectedCount(_selected.length)) : null,
          actions: [
            if (_selected.isNotEmpty)
              TextButton.icon(
                onPressed: () => _downloadSelected(b, type),
                icon: const Icon(Icons.download_rounded),
                label: Text(tr.download),
              )
            else if (!offline && eps.isNotEmpty)
              IconButton(
                tooltip: tr.downloadEpisodes,
                icon: const Icon(Icons.download_rounded),
                onPressed: () => _showBatchSheet(b, type),
              ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(fit: StackFit.expand, children: [
              PosterImage(url: b.detail.poster, localPath: ref.read(dbProvider).show(widget.slug)?.posterPath),
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
              Text(b.detail.title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: Gap.s),
              if (offline)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.s),
                  child: Row(children: [
                    const Icon(Icons.cloud_off_rounded, size: 16, color: Colors.white54),
                    const SizedBox(width: 6),
                    Text(tr.offlineSavedInfo, style: t.bodySmall?.copyWith(color: Colors.white54)),
                  ]),
                ),
              if (b.detail.synopsis.isNotEmpty)
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.topCenter,
                    child: Text(
                      b.detail.synopsis,
                      maxLines: _expanded ? null : 3,
                      overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                      style: t.bodyMedium?.copyWith(color: Colors.white70, height: 1.4),
                    ),
                  ),
                ),
              const SizedBox(height: Gap.m),
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: target == null
                        ? null
                        : () => _play(b, target!.number, type),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(target == null
                        ? tr.noEpisodes
                        : (targetHist?.isPartial ?? false)
                            ? tr.resumeEpisode(target.number)
                            : tr.playEpisode(target.number)),
                  ),
                ),
                if (hasDub) ...[
                  const SizedBox(width: Gap.m),
                  SegmentedButton<AudioType>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: AudioType.sub, label: Text(tr.sub)),
                      ButtonSegment(value: AudioType.dub, label: Text(tr.dub)),
                    ],
                    selected: {type},
                    onSelectionChanged: (s) => setState(() => _type = s.first),
                  ),
                ],
              ]),
              const SizedBox(height: Gap.m),
              Text(tr.episodesHeader(eps.length), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: Gap.s),
            ]),
          ),
        ),
        if (eps.isEmpty)
          SliverToBoxAdapter(
            child: SizedBox(height: 220, child: EmptyState(icon: Icons.movie_filter_outlined, title: tr.noEpisodesYet, message: tr.checkBackLater)),
          )
        else
          SliverList.builder(
            itemCount: eps.length,
            itemBuilder: (context, i) => _EpisodeTile(
              episode: eps[i],
              history: history[eps[i].number],
              download: downloads[eps[i].number],
              dubUnavailable: type == AudioType.dub && !eps[i].hasDub,
              selected: _selected.contains(eps[i].number),
              selecting: _selected.isNotEmpty,
              onTap: () {
                if (_selected.isNotEmpty) {
                  setState(() => _toggle(eps[i].number));
                } else {
                  _play(b, eps[i].number, type);
                }
              },
              onLongPress: () => setState(() => _toggle(eps[i].number)),
              onDownload: offline ? null : () => _download(b, [eps[i]], type),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: Gap.xl)),
      ],
    );
  }

  void _toggle(String n) {
    if (!_selected.remove(n)) _selected.add(n);
  }

  void _play(ShowBundle b, String episode, AudioType type) {
    openPlayer(context, PlayRequest(slug: b.detail.slug, showTitle: b.detail.title, episode: episode, type: type));
  }

  Future<void> _downloadSelected(ShowBundle b, AudioType type) async {
    final eps = b.episodes.where((e) => _selected.contains(e.number)).toList();
    setState(_selected.clear);
    await _download(b, eps, type);
  }

  Future<void> _download(ShowBundle b, List<EpisodeInfo> eps, AudioType type, {String? quality}) async {
    final settings = ref.read(settingsProvider);
    await ref.read(downloadManagerProvider).enqueue(b.detail, eps, type, quality ?? settings.quality);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(Strings.of(context).addedEpisodes([for (final e in eps) e.number])),
    ));
  }

  Future<void> _showBatchSheet(ShowBundle b, AudioType type) async {
    final eps = b.episodes;
    final nums = eps.map((e) => e.numeric).toList()..sort();
    final settings = ref.read(settingsProvider);
    var from = nums.first.toInt();
    var to = nums.last.toInt();
    var audio = type;
    var quality = settings.quality;
    final tr = Strings.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, MediaQuery.of(ctx).viewInsets.bottom + Gap.l),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr.downloadEpisodes, style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: Gap.m),
            Wrap(spacing: 8, children: [
              ActionChip(label: Text(tr.wholeSeason), onPressed: () => setSheet(() {
                    from = nums.first.toInt();
                    to = nums.last.toInt();
                  })),
              ActionChip(label: Text(tr.unwatched), onPressed: () {
                final h = {for (final x in ref.read(historyProvider).value ?? const <HistoryEntry>[]) if (x.slug == widget.slug) x.episode: x};
                final un = eps.where((e) => !(h[e.number]?.isFinished ?? false)).toList();
                Navigator.pop(ctx);
                _download(b, un, audio, quality: quality);
              }),
            ]),
            const SizedBox(height: Gap.m),
            Row(children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('from$from'),
                  initialValue: '$from',
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: tr.fromEpisode),
                  onChanged: (v) => from = int.tryParse(v) ?? from,
                ),
              ),
              const SizedBox(width: Gap.m),
              Expanded(
                child: TextFormField(
                  key: ValueKey('to$to'),
                  initialValue: '$to',
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: tr.toEpisode),
                  onChanged: (v) => to = int.tryParse(v) ?? to,
                ),
              ),
            ]),
            const SizedBox(height: Gap.m),
            Row(children: [
              SegmentedButton<AudioType>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: AudioType.sub, label: Text(tr.sub)),
                  ButtonSegment(value: AudioType.dub, label: Text(tr.dub)),
                ],
                selected: {audio},
                onSelectionChanged: (s) => setSheet(() => audio = s.first),
              ),
              const SizedBox(width: Gap.m),
              DropdownButton<String>(
                value: quality,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(value: 'best', child: Text(tr.bestQuality)),
                  const DropdownMenuItem(value: '1080', child: Text('1080p')),
                  const DropdownMenuItem(value: '720', child: Text('720p')),
                  const DropdownMenuItem(value: '480', child: Text('480p')),
                  const DropdownMenuItem(value: '360', child: Text('360p')),
                ],
                onChanged: (v) => setSheet(() => quality = v ?? quality),
              ),
            ]),
            const SizedBox(height: Gap.m),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.download_rounded),
                label: Text(tr.addToDownloads),
                onPressed: () {
                  final chosen = eps.where((e) => e.numeric >= from && e.numeric <= to).toList();
                  Navigator.pop(ctx);
                  _download(b, chosen, audio, quality: quality);
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.history,
    required this.download,
    required this.dubUnavailable,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onDownload,
  });

  final EpisodeInfo episode;
  final HistoryEntry? history;
  final DownloadRecord? download;
  final bool dubUnavailable;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onDownload;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tr = Strings.of(context);
    final watched = history?.isFinished ?? false;
    final partial = history?.isPartial ?? false;
    return Opacity(
      opacity: dubUnavailable ? 0.45 : 1,
      child: Material(
        color: selected ? kAccent.withValues(alpha: 0.18) : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: 10),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(12)),
                child: selecting
                    ? Icon(selected ? Icons.check_circle_rounded : Icons.circle_outlined, color: kAccent)
                    : Text(episode.number, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: Gap.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(episode.title.isEmpty ? tr.episode(episode.number) : episode.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: watched ? Colors.white54 : Colors.white)),
                  const SizedBox(height: 2),
                  Row(children: [
                    if (episode.isFiller) _tag(context, tr.filler, Colors.orangeAccent),
                    if (dubUnavailable) _tag(context, tr.noDub, Colors.white38),
                    if (download != null && download!.isDone) _tag(context, tr.downloaded, kAccent),
                    if (download != null && !download!.isDone) _tag(context, _dlLabel(download!, tr), Colors.white54),
                  ]),
                  if (partial)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(value: history!.fraction, minHeight: 3, backgroundColor: Colors.white12),
                      ),
                    ),
                ]),
              ),
              if (watched) const Icon(Icons.check_circle_rounded, color: kAccent, size: 20),
              if (!selecting && onDownload != null && download == null)
                IconButton(
                  tooltip: tr.download,
                  icon: const Icon(Icons.download_rounded, size: 22),
                  onPressed: onDownload,
                ),
            ]),
          ),
        ),
      ),
    );
  }

  String _dlLabel(DownloadRecord d, Strings tr) => switch (d.status) {
        DownloadStatus.queued => tr.queued,
        DownloadStatus.downloading => tr.downloadingPct((d.progress * 100).round()),
        DownloadStatus.paused => tr.paused,
        DownloadStatus.failed => tr.failed,
        DownloadStatus.done => tr.downloaded,
      };

  Widget _tag(BuildContext context, String text, Color color) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
      );
}

class _ShowSkeleton extends StatelessWidget {
  const _ShowSkeleton();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.all(Gap.m), children: [
        const Skeleton(height: 200),
        const SizedBox(height: Gap.m),
        const Skeleton(height: 24, width: 220),
        const SizedBox(height: Gap.s),
        const Skeleton(height: 14),
        const SizedBox(height: 6),
        const Skeleton(height: 14),
        const SizedBox(height: Gap.l),
        for (var i = 0; i < 6; i++) const Padding(padding: EdgeInsets.only(bottom: 12), child: Skeleton(height: 44)),
      ]),
    );
  }
}
