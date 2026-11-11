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
          final t = Theme.of(context).textTheme;
          return SizedBox(
            width: 290,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => openPlayer(
                  context,
                  PlayRequest(slug: it.show.slug, showTitle: it.show.title, episode: it.episode, type: settings.audio),
                ),
                child: Row(children: [
                  AspectRatio(
                    aspectRatio: 2 / 3,
                    child: PosterImage(url: it.show.poster, localPath: it.show.posterPath),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(it.show.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          it.resumeFraction > 0 ? 'Episode ${it.episode} · resume' : 'Up next · Episode ${it.episode}',
                          style: t.bodySmall?.copyWith(color: Colors.white60),
                        ),
                        const Spacer(),
                        Row(children: [
                          const Icon(Icons.play_circle_fill_rounded, color: kAccent, size: 30),
                          const SizedBox(width: 8),
                          Text('Play', style: t.labelLarge?.copyWith(color: kAccent, fontWeight: FontWeight.w700)),
                        ]),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(value: it.resumeFraction, minHeight: 4, backgroundColor: Colors.white12),
                        ),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}
