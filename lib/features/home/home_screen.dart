import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/models.dart';
import '../../core/storage/app_db.dart';
import '../../ui/widgets.dart';
import '../player/open_player.dart';
import '../player/play_request.dart';
import '../show/show_screen.dart';
import '../sync/sync_section.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cont = ref.watch(continueWatchingProvider);
    final home = ref.watch(homeProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(homeProvider.future),
      child: CustomScrollView(
        slivers: [
          const SliverAppBar(
            floating: true,
            title: Text('Oobleck', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            actions: [HomeSyncButton()],
          ),
          if (cont.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader('Continue watching')),
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
                const SliverToBoxAdapter(
                  child: SizedBox(
                    height: 320,
                    child: EmptyState(icon: Icons.explore_outlined, title: 'Nothing to show yet', message: 'Pull down to refresh.'),
                  ),
                ),
              for (final e in sections.entries) ...[
                SliverToBoxAdapter(child: SectionHeader(e.key)),
                SliverToBoxAdapter(child: _ShowRow(shows: e.value)),
              ],
            ],
          ),
          const SliverToBoxAdapter(child: SizedBox(height: Gap.xl)),
        ],
      ),
    );
  }
}

class _ShowRow extends StatelessWidget {
  const _ShowRow({required this.shows});
  final List<ShowSummary> shows;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 260,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Gap.m),
        itemCount: shows.length,
        separatorBuilder: (_, _) => const SizedBox(width: Gap.m),
        itemBuilder: (context, i) {
          final s = shows[i];
          return PosterCard(
            width: 130,
            title: s.title,
            url: s.poster,
            badge: s.badge,
            onTap: () => openShow(context, s.slug),
          );
        },
      ),
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
        for (var r = 0; r < 2; r++) ...[
          const SectionHeader(' '),
          SizedBox(
            height: 260,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: Gap.m),
              itemCount: 6,
              separatorBuilder: (_, _) => const SizedBox(width: Gap.m),
              itemBuilder: (_, _) => const SizedBox(
                width: 130,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AspectRatio(aspectRatio: 2 / 3, child: Skeleton()),
                  SizedBox(height: 8),
                  Skeleton(height: 12, width: 100),
                ]),
              ),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Gap.m),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: Gap.m),
        itemBuilder: (context, i) {
          final it = items[i];
          return ContinueCard(
            item: it,
            onPlay: () => openPlayer(
              context,
              PlayRequest(slug: it.show.slug, showTitle: it.show.title, episode: it.episode, type: settings.audio),
            ),
            onEpisodes: () => openShow(context, it.show.slug),
          );
        },
      ),
    );
  }
}

/// A "Continue watching" card: tap (or Play) resumes; Episodes (or a long
/// press / right click) opens the show page with the whole season.
class ContinueCard extends StatelessWidget {
  const ContinueCard({super.key, required this.item, required this.onPlay, required this.onEpisodes});
  final ContinueItem item;
  final VoidCallback onPlay;
  final VoidCallback onEpisodes;

  static const double width = 340;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPlay,
          onLongPress: onEpisodes,
          onSecondaryTap: onEpisodes,
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
                    item.resumeFraction > 0 ? 'Episode ${item.episode} · resume' : 'Up next · Episode ${item.episode}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(color: Colors.white60),
                  ),
                  const Spacer(),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(children: [
                      _CardAction(icon: Icons.play_circle_fill_rounded, label: 'Play', accent: true, onTap: onPlay),
                      const SizedBox(width: 4),
                      _CardAction(icon: Icons.format_list_bulleted_rounded, label: 'Episodes', onTap: onEpisodes),
                    ]),
                  ),
                  const SizedBox(height: 8),
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
      message: accent ? 'Resume this episode' : 'See all episodes of this season',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: accent ? 28 : 22),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }
}
