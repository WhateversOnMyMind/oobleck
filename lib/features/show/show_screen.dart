import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import '../../ui/skeletons.dart';
import '../../ui/widgets.dart';
import '../player/open_player.dart';
import '../player/play_request.dart';
import 'download_sheet.dart';
import 'episode_selection.dart';
import 'episode_tile.dart';
import 'progress_actions.dart';

class ShowScreen extends ConsumerStatefulWidget {
  const ShowScreen({super.key, required this.slug});
  final String slug;
  @override
  ConsumerState<ShowScreen> createState() => _ShowScreenState();
}

class _ShowScreenState extends ConsumerState<ShowScreen> {
  static const _newestFirstKey = 'ui:episodesNewestFirst';

  final _scroll = ScrollController();
  final _listHeaderKey = GlobalKey();
  AudioType? _type;
  final Set<String> _selected = {};

  /// Selection mode can be on with nothing selected yet (the Select button).
  bool _selecting = false;

  /// Last episode toggled; a long press on another selects the span between.
  String? _anchor;
  bool _expanded = false;
  late bool _newestFirst = ref.read(dbProvider).misc<bool>(_newestFirstKey) ?? false;
  String? _highlight;
  Timer? _highlightTimer;

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

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
    return async.when(
      skipLoadingOnRefresh: true,
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
      data: (b) => _content(b, refreshing: async.isLoading),
    );
  }

  Widget _content(ShowBundle b, {bool offline = false, bool refreshing = false}) {
    final settings = ref.watch(settingsProvider);
    final type = _type ?? settings.audio;
    final history = {for (final h in ref.watch(historyProvider).value ?? const <HistoryEntry>[]) if (h.slug == widget.slug) h.episode: h};
    final downloads = {
      for (final d in ref.watch(downloadsProvider).value ?? const <DownloadRecord>[])
        if (d.slug == widget.slug) d.episode: d
    };
    final eps = _newestFirst ? b.episodes.reversed.toList() : b.episodes;
    final hasDub = eps.any((e) => e.hasDub);
    final t = Theme.of(context).textTheme;
    final tr = Strings.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final selecting = _selecting;

    // Resume target: most recently watched unfinished episode, else the first unwatched.
    EpisodeInfo? target;
    if (b.episodes.isNotEmpty) {
      final partial = history.values.where((h) => h.isPartial).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (partial.isNotEmpty) {
        target = b.episodes.where((e) => e.number == partial.first.episode).firstOrNull;
      }
      target ??= b.episodes.where((e) => !(history[e.number]?.isFinished ?? false)).firstOrNull ?? b.episodes.first;
    }
    final resumes = target != null && (history[target.number]?.isPartial ?? false);
    final playButton = FilledButton.icon(
      onPressed: target == null ? null : () => _play(b, target!.number, type),
      icon: const Icon(Icons.play_arrow_rounded),
      label: Text(
        target == null
            ? tr.noEpisodes
            : resumes
                ? tr.resumeEpisode(target.number)
                : tr.playEpisode(target.number),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    final audioToggle = SegmentedButton<AudioType>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: AudioType.sub, label: Text(tr.sub)),
        ButtonSegment(value: AudioType.dub, label: Text(tr.dub)),
      ],
      selected: {type},
      onSelectionChanged: (s) => setState(() => _type = s.first),
    );

    final scrollView = CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        PosterSliverAppBar(
          title: b.detail.title,
          posterUrl: b.detail.poster,
          posterPath: ref.read(dbProvider).show(widget.slug)?.posterPath,
          barTitle: selecting ? Text(tr.selectedCount(_selected.length)) : null,
          leading: selecting ? IconButton(tooltip: tr.cancelSelection, icon: const Icon(Icons.close_rounded), onPressed: _endSelection) : null,
          actions: selecting ? _selectionActions(b, tr) : _actions(b, type, offline: offline, hasHistory: history.isNotEmpty, tr: tr),
        ),
        SliverToBoxAdapter(
          child: AnimatedOpacity(
            opacity: refreshing ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: const LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent),
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
                    Expanded(child: Text(tr.offlineSavedInfo, style: t.bodySmall?.copyWith(color: Colors.white54))),
                  ]),
                ),
              if (b.detail.synopsis.isNotEmpty) _Synopsis(text: b.detail.synopsis, expanded: _expanded, onToggle: () => setState(() => _expanded = !_expanded)),
              const SizedBox(height: Gap.m),
              // Phones get Play in the bottom bar, within thumb reach.
              if (wide)
                Row(children: [
                  ConstrainedBox(constraints: const BoxConstraints(minWidth: 240, maxWidth: 360), child: playButton),
                  if (hasDub) ...[const SizedBox(width: Gap.m), audioToggle],
                ])
              else if (hasDub)
                audioToggle,
              if (wide || hasDub) const SizedBox(height: Gap.m),
              ConstrainedBox(
                key: _listHeaderKey,
                constraints: const BoxConstraints(maxWidth: 900 - Gap.m - Gap.s),
                child: Row(children: [
                  Expanded(child: Text(tr.episodesHeader(eps.length), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                  if (eps.length > 1)
                    IconButton(
                      tooltip: _newestFirst ? tr.newestFirst : tr.oldestFirst,
                      icon: Icon(_newestFirst ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded),
                      onPressed: _toggleOrder,
                    ),
                  if (eps.length > 24)
                    IconButton(tooltip: tr.jumpToEpisode, icon: const Icon(Icons.pin_outlined), onPressed: () => _jump(eps)),
                ]),
              ),
              if (selecting)
                Padding(
                  padding: const EdgeInsets.only(bottom: Gap.s),
                  child: Text(tr.selectionHint, style: t.bodySmall?.copyWith(color: Colors.white54)),
                ),
            ]),
          ),
        ),
        if (eps.isEmpty)
          SliverToBoxAdapter(
            child: SizedBox(height: 220, child: EmptyState(icon: Icons.movie_filter_outlined, title: tr.noEpisodesYet, message: tr.checkBackLater)),
          )
        else
          SliverMaxWidth(
            maxWidth: 900,
            sliver: SliverFixedExtentList.builder(
              itemExtent: EpisodeTile.extent(context),
              itemCount: eps.length,
              itemBuilder: (context, i) {
                final e = eps[i];
                return EpisodeTile(
                  episode: e,
                  history: history[e.number],
                  download: downloads[e.number],
                  dubUnavailable: type == AudioType.dub && !e.hasDub,
                  selected: _selected.contains(e.number),
                  selecting: selecting,
                  highlighted: _highlight == e.number,
                  onTap: () {
                    if (!selecting) {
                      _play(b, e.number, type);
                    } else if (HardwareKeyboard.instance.isShiftPressed) {
                      _selectSpan(eps, e.number);
                    } else {
                      _toggle(e.number);
                    }
                  },
                  onLongPress: () {
                    hapticTick();
                    if (selecting && _anchor != null && _anchor != e.number) {
                      _selectSpan(eps, e.number);
                    } else {
                      _toggle(e.number);
                    }
                  },
                  onDownload: offline ? null : () => _download(b, [e], type),
                );
              },
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: Gap.xl)),
      ],
    );

    Widget? bottomBar;
    if (selecting) {
      bottomBar = StickyActionBar(
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.download_rounded),
                label: Text(_selected.isEmpty ? tr.selectEpisodes : tr.episodesToDownload(_selected.length)),
                onPressed: _selected.isEmpty || offline ? null : () => _downloadSelected(b, type),
              ),
            ),
          ),
        ),
      );
    } else if (!wide) {
      bottomBar = StickyActionBar(child: SizedBox(width: double.infinity, child: playButton));
    }

    return PopScope(
      // Back leaves selection mode first.
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endSelection();
      },
      child: Scaffold(
        body: offline
            ? scrollView
            : RefreshIndicator(
                edgeOffset: kToolbarHeight + MediaQuery.paddingOf(context).top,
                onRefresh: () async {
                  try {
                    ref.invalidate(showProvider(widget.slug));
                    await ref.read(showProvider(widget.slug).future);
                  } catch (_) {
                    // The cached copy stays on screen.
                  }
                },
                child: scrollView,
              ),
        bottomNavigationBar: bottomBar,
      ),
    );
  }

  List<Widget> _actions(ShowBundle b, AudioType type, {required bool offline, required bool hasHistory, required Strings tr}) {
    final hasEpisodes = b.episodes.isNotEmpty;
    return [
      if (!offline && hasEpisodes)
        IconButton(tooltip: tr.downloadEpisodes, icon: const Icon(Icons.download_rounded), onPressed: () => _showBatchSheet(b, type)),
      PopupMenuButton<String>(
        tooltip: tr.more,
        onSelected: (v) => switch (v) {
          'select' => setState(() => _selecting = true),
          'refresh' => ref.invalidate(showProvider(widget.slug)),
          'clear' => unawaited(_clearProgress()),
          _ => null,
        },
        itemBuilder: (_) => [
          if (hasEpisodes) PopupMenuItem(value: 'select', child: _MenuRow(Icons.checklist_rounded, tr.selectEpisodes)),
          // Phones pull down to refresh.
          if (isDesktop && !offline) PopupMenuItem(value: 'refresh', child: _MenuRow(Icons.refresh_rounded, tr.refresh)),
          if (hasHistory) PopupMenuItem(value: 'clear', child: _MenuRow(Icons.history_toggle_off_rounded, tr.clearShowProgress)),
        ],
      ),
    ];
  }

  List<Widget> _selectionActions(ShowBundle b, Strings tr) {
    final all = _selected.length == b.episodes.length;
    return [
      IconButton(
        tooltip: all ? tr.cancelSelection : tr.selectAll,
        icon: Icon(all ? Icons.deselect_rounded : Icons.select_all_rounded),
        onPressed: () => setState(() {
          all ? _selected.clear() : _selected.addAll(b.episodes.map((e) => e.number));
        }),
      ),
      PopupMenuButton<bool>(
        tooltip: tr.more,
        enabled: _selected.isNotEmpty,
        onSelected: (watched) => unawaited(_markSelected(b, watched: watched)),
        itemBuilder: (_) => [
          PopupMenuItem(value: true, child: _MenuRow(Icons.check_circle_outline_rounded, tr.markAsWatched)),
          PopupMenuItem(value: false, child: _MenuRow(Icons.radio_button_unchecked_rounded, tr.markAsUnwatched)),
        ],
      ),
    ];
  }

  // ---- selection -------------------------------------------------------------
  void _toggle(String n) {
    setState(() {
      _selecting = true;
      if (!_selected.remove(n)) _selected.add(n);
      _anchor = n;
    });
  }

  void _selectSpan(List<EpisodeInfo> eps, String to) {
    final span = episodeSpan([for (final e in eps) e.number], _anchor ?? to, to);
    setState(() {
      _selected.addAll(span);
      _anchor = to;
    });
  }

  void _endSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
      _anchor = null;
    });
  }

  Future<void> _markSelected(ShowBundle b, {required bool watched}) async {
    final downloads = ref.read(downloadsProvider).value ?? const <DownloadRecord>[];
    final durations = {
      for (final n in _selected) n: downloads.where((d) => d.slug == widget.slug && d.episode == n).firstOrNull?.durationMs ?? 0,
    };
    final count = durations.length;
    _endSelection();
    final undo = await markEpisodes(ref, widget.slug, durations, watched: watched);
    if (!mounted) return;
    final tr = Strings.of(context);
    showAppSnackBar(context, watched ? tr.markedWatched(count) : tr.markedUnwatched(count), onUndo: undo);
  }

  Future<void> _clearProgress() async {
    final tr = Strings.of(context);
    final ok = await confirmAction(context, title: tr.clearShowProgressQ, message: tr.clearShowProgressBody, confirmLabel: tr.clear);
    if (!ok || !mounted) return;
    final undo = await removeShowProgress(ref, widget.slug);
    if (mounted) showAppSnackBar(context, tr.showProgressCleared, onUndo: undo);
  }

  // ---- list order and jumping -------------------------------------------------
  void _toggleOrder() {
    setState(() => _newestFirst = !_newestFirst);
    unawaited(ref.read(dbProvider).setMisc(_newestFirstKey, _newestFirst));
  }

  Future<void> _jump(List<EpisodeInfo> eps) async {
    final tr = Strings.of(context);
    final nums = eps.map((e) => e.numeric).toList()..sort();
    final c = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr.jumpToEpisode),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: InputDecoration(labelText: tr.episodeNumber, helperText: tr.episodeRangeHint(_num(nums.first), _num(nums.last))),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(tr.go)),
        ],
      ),
    );
    if (input == null || !mounted) return;
    final index = episodeIndexFor(eps, input);
    if (index < 0) return;
    _scrollToIndex(index);
    _highlightTimer?.cancel();
    setState(() => _highlight = eps[index].number);
    _highlightTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _highlight = null);
    });
  }

  static String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Rows have a fixed height, so the target offset is the list's start plus
  /// `index` rows, less the pinned app bar.
  void _scrollToIndex(int index) {
    final header = _listHeaderKey.currentContext?.findRenderObject();
    if (header is! RenderBox || !_scroll.hasClients) return;
    final listStart = RenderAbstractViewport.of(header).getOffsetToReveal(header, 0).offset + header.size.height;
    final pinned = kToolbarHeight + MediaQuery.paddingOf(context).top;
    final extent = EpisodeTile.extent(context);
    final target = (listStart + index * extent - pinned - extent).clamp(0.0, _scroll.position.maxScrollExtent);
    unawaited(_scroll.animateTo(target, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic));
  }

  // ---- playing and downloading --------------------------------------------------
  void _play(ShowBundle b, String episode, AudioType type) {
    openPlayer(context, PlayRequest(slug: b.detail.slug, showTitle: b.detail.title, episode: episode, type: type));
  }

  Future<void> _downloadSelected(ShowBundle b, AudioType type) async {
    final eps = b.episodes.where((e) => _selected.contains(e.number)).toList();
    _endSelection();
    await _download(b, eps, type);
  }

  Future<void> _download(ShowBundle b, List<EpisodeInfo> eps, AudioType type, {String? quality}) async {
    final settings = ref.read(settingsProvider);
    await ref.read(downloadManagerProvider).enqueue(b.detail, eps, type, quality ?? settings.quality);
    if (!mounted) return;
    showAppSnackBar(context, Strings.of(context).addedEpisodes([for (final e in eps) e.number]));
  }

  Future<void> _showBatchSheet(ShowBundle b, AudioType type) async {
    final history = ref.read(historyProvider).value ?? const <HistoryEntry>[];
    final choice = await showDownloadSheet(
      context,
      episodes: b.episodes,
      finished: {for (final h in history) if (h.slug == widget.slug && h.isFinished) h.episode},
      audio: type,
      quality: ref.read(settingsProvider).quality,
      hasDub: b.episodes.any((e) => e.hasDub),
    );
    if (choice != null) await _download(b, choice.episodes, choice.audio, quality: choice.quality);
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 20, color: Colors.white70),
        const SizedBox(width: Gap.m),
        Flexible(child: Text(label)),
      ]);
}

/// Three lines of synopsis with a clear "Show more" control (the text alone
/// did not look tappable).
class _Synopsis extends StatelessWidget {
  const _Synopsis({required this.text, required this.expanded, required this.onToggle});
  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tr = Strings.of(context);
    final style = t.bodyMedium?.copyWith(color: Colors.white70, height: 1.4);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: LayoutBuilder(builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 3,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: box.maxWidth);
        final long = painter.didExceedMaxLines;
        painter.dispose();
        return InkWell(
          borderRadius: BorderRadius.circular(Radii.small),
          onTap: long ? onToggle : null,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              child: Text(text, maxLines: expanded ? null : 3, overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis, style: style),
            ),
            if (long)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(expanded ? tr.showLess : tr.showMore, style: t.labelLarge?.copyWith(color: kAccent, fontWeight: FontWeight.w700)),
              ),
          ]),
        );
      }),
    );
  }
}

class _ShowSkeleton extends StatelessWidget {
  const _ShowSkeleton();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: ListView(physics: const NeverScrollableScrollPhysics(), children: [
        const Padding(
          padding: EdgeInsets.all(Gap.m),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Skeleton(height: 200),
            SizedBox(height: Gap.m),
            Skeleton(height: 24, width: 220),
            SizedBox(height: Gap.s),
            Skeleton(height: 14),
            SizedBox(height: 6),
            Skeleton(height: 14),
            SizedBox(height: Gap.m),
            Skeleton(height: kMinTouch, radius: Radii.card),
          ]),
        ),
        for (var i = 0; i < 8; i++) const ListRowSkeleton(leadingWidth: 44, leadingHeight: 44),
      ]),
    );
  }
}
