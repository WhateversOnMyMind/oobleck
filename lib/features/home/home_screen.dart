import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/strings_ui.dart';
import '../../app/theme.dart';
import '../../core/models.dart';
import '../../core/storage/app_db.dart';
import '../../ui/feedback.dart';
import '../../ui/h_scroll_row.dart';
import '../../ui/layout.dart';
import '../../ui/skeletons.dart';
import '../../ui/widgets.dart';
import '../player/open_player.dart';
import '../player/play_request.dart';
import '../show/progress_actions.dart';
import '../show/show_screen.dart';
import '../sync/sync_section.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cont = ref.watch(continueWatchingProvider);
    final home = ref.watch(homeProvider);
    final s = Strings.of(context);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(homeProvider.future),
      child: CustomScrollView(
        // Keeps the scroll position when coming back from another tab.
        key: const PageStorageKey<String>('home'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            floating: true,
            title: const Text('Oobleck', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            actions: [
              // There is no pull-to-refresh with a mouse.
              if (isDesktop)
                IconButton(
                  tooltip: s.refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: home.isLoading ? null : () => ref.invalidate(homeProvider),
                ),
              const HomeSyncButton(),
            ],
          ),
          if (cont.isNotEmpty) ...[
            SliverToBoxAdapter(child: SectionHeader(s.continueWatching)),
            SliverToBoxAdapter(child: _ContinueRow(items: cont)),
          ],
          ...home.when(
            loading: () => [const SliverToBoxAdapter(child: _HomeSkeleton())],
            error: (e, _) => [
              SliverFillRemaining(
                hasScrollBody: false,
                child: SizedBox(
                  height: 360,
                  child: ErrorState(error: e, onRetry: () => ref.invalidate(homeProvider)),
                ),
              ),
            ],
            data: (sections) => [
              if (sections.isEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 320,
                    child: EmptyState(
                      icon: Icons.explore_outlined,
                      title: s.nothingToShow,
                      message: isDesktop ? null : s.pullToRefresh,
                      actionLabel: s.refresh,
                      onAction: () => ref.invalidate(homeProvider),
                    ),
                  ),
                ),
              for (final e in sections.entries) ...[
                SliverToBoxAdapter(child: SectionHeader(s.section(e.key))),
                SliverToBoxAdapter(child: _ShowRow(name: e.key, shows: e.value)),
              ],
            ],
          ),
          const SliverToBoxAdapter(child: SizedBox(height: Gap.xl)),
        ],
      ),
    );
  }
}

const double _posterWidth = 130;

class _ShowRow extends StatelessWidget {
  const _ShowRow({required this.name, required this.shows});
  final String name;
  final List<ShowSummary> shows;

  @override
  Widget build(BuildContext context) {
    return HScrollRow(
      height: posterCardHeight(context, _posterWidth),
      storageKey: 'home-row-$name',
      itemCount: shows.length,
      itemBuilder: (context, i) {
        final s = shows[i];
        return PosterCard(
          width: _posterWidth,
          title: s.title,
          url: s.poster,
          badge: s.badge,
          onTap: () => openShow(context, s.slug),
        );
      },
    );
  }
}

void openShow(BuildContext context, String slug) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ShowScreen(slug: slug)));
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var r = 0; r < 3; r++) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(Gap.m, Gap.l, Gap.m, Gap.s),
            child: Align(alignment: Alignment.centerLeft, child: Skeleton(width: 160, height: 24, radius: 8)),
          ),
          SizedBox(
            height: posterCardHeight(context, _posterWidth),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: Gap.m),
              itemCount: 12,
              separatorBuilder: (_, _) => const SizedBox(width: Gap.m),
              itemBuilder: (_, _) => const PosterCardSkeleton(width: _posterWidth),
            ),
          ),
        ],
      ],
    );
  }
}

class _ContinueRow extends ConsumerWidget {
  const _ContinueRow({required this.items});
  final List<ContinueItem> items;

  void _play(BuildContext context, ContinueItem it, AudioType type) {
    openPlayer(context, PlayRequest(slug: it.show.slug, showTitle: it.show.title, episode: it.episode, type: type));
  }

  Future<void> _more(BuildContext context, WidgetRef ref, ContinueItem it, AudioType type) async {
    hapticTick();
    final s = Strings.of(context);
    final picked = await showActionSheet<String>(context, title: it.show.title, actions: [
      SheetAction(
        value: 'play',
        icon: Icons.play_arrow_rounded,
        label: it.resumeFraction > 0 ? s.resumeEpisode(it.episode) : s.playEpisode(it.episode),
      ),
      SheetAction(value: 'show', icon: Icons.format_list_bulleted_rounded, label: s.openShowPage),
      SheetAction(value: 'remove', icon: Icons.remove_circle_outline_rounded, label: s.removeFromContinue),
    ]);
    if (picked == null || !context.mounted) return;
    switch (picked) {
      case 'play':
        _play(context, it, type);
      case 'show':
        openShow(context, it.show.slug);
      case 'remove':
        final undo = await removeShowProgress(ref, it.show.slug);
        if (context.mounted) showAppSnackBar(context, s.removedFromContinue(it.show.title), onUndo: undo);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final type = ref.watch(settingsProvider.select((s) => s.audio));
    // The card's text grows with the system font size; give it room.
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return HScrollRow(
      height: 190 + (scale > 1 ? (scale - 1) * 80 : 0),
      storageKey: 'home-continue',
      itemCount: items.length,
      itemBuilder: (context, i) {
        final it = items[i];
        return ContinueCard(
          item: it,
          onPlay: () => _play(context, it, type),
          onEpisodes: () => openShow(context, it.show.slug),
          onMore: () => _more(context, ref, it, type),
        );
      },
    );
  }
}

/// A "Continue watching" card: tap (or Play) resumes; Episodes opens the show
/// page with the whole season; a long press / right click opens more actions.
class ContinueCard extends StatelessWidget {
  const ContinueCard({super.key, required this.item, required this.onPlay, required this.onEpisodes, this.onMore});
  final ContinueItem item;
  final VoidCallback onPlay;
  final VoidCallback onEpisodes;

  /// Long press / right click. Defaults to [onEpisodes].
  final VoidCallback? onMore;

  static const double width = 340;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = Strings.of(context);
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPlay,
          onLongPress: onMore ?? onEpisodes,
          onSecondaryTap: onMore ?? onEpisodes,
          child: Row(children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: PosterImage(url: item.show.poster, localPath: item.show.posterPath),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.show.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    item.resumeFraction > 0 ? s.resumeLine(item.episode) : s.upNextLine(item.episode),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(color: Colors.white60),
                  ),
                  const Spacer(),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(children: [
                      _CardAction(icon: Icons.play_circle_fill_rounded, label: s.play, accent: true, onTap: onPlay),
                      const SizedBox(width: 4),
                      _CardAction(icon: Icons.format_list_bulleted_rounded, label: s.episodesWord, onTap: onEpisodes),
                    ]),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(value: item.resumeFraction, minHeight: 4, backgroundColor: Colors.white12),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  const _CardAction({required this.icon, required this.label, required this.onTap, this.accent = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ? kAccent : Colors.white70;
    return Tooltip(
      message: accent ? Strings.of(context).resumeThisEpisode : Strings.of(context).seeAllEpisodes,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: ConstrainedBox(
          // Tall enough to hit comfortably with a thumb.
          constraints: const BoxConstraints(minHeight: kMinTouch),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: color, size: accent ? 28 : 22),
              const SizedBox(width: 6),
              Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    );
  }
}
