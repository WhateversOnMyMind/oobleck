import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'layout.dart';
import 'widgets.dart';

/// Placeholder with the shape of a `PosterCard` (cover + title line).
class PosterCardSkeleton extends StatelessWidget {
  const PosterCardSkeleton({super.key, this.width});
  final double? width;

  @override
  Widget build(BuildContext context) {
    const card = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AspectRatio(aspectRatio: 2 / 3, child: Skeleton(radius: Radii.card)),
      SizedBox(height: Gap.s),
      FractionallySizedBox(widthFactor: 0.8, child: Skeleton(height: 12, radius: 6)),
    ]);
    return width == null ? card : SizedBox(width: width, child: card);
  }
}

/// A grid of poster placeholders laid out exactly like the real poster grid,
/// so content does not jump when it arrives. Use inside a `CustomScrollView`.
class SliverPosterGridSkeleton extends StatelessWidget {
  const SliverPosterGridSkeleton({super.key, this.count = 12, this.subtitle = false});
  final int count;
  final bool subtitle;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.all(Gap.m),
      sliver: SliverLayoutBuilder(
        builder: (context, c) => SliverGrid.builder(
          gridDelegate: posterGridDelegate(context, c.crossAxisExtent + Gap.m * 2, subtitle: subtitle),
          itemCount: count,
          itemBuilder: (_, _) => const PosterCardSkeleton(),
        ),
      ),
    );
  }
}

/// Placeholder for a list row: a square/thumbnail block and two text lines.
class ListRowSkeleton extends StatelessWidget {
  const ListRowSkeleton({super.key, this.leadingWidth = 48, this.leadingHeight = 48});
  final double leadingWidth;
  final double leadingHeight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.m, vertical: Gap.s),
      child: Row(children: [
        Skeleton(width: leadingWidth, height: leadingHeight),
        const SizedBox(width: Gap.m),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FractionallySizedBox(widthFactor: 0.6, child: Skeleton(height: 14, radius: 6)),
            SizedBox(height: Gap.s),
            FractionallySizedBox(widthFactor: 0.3, child: Skeleton(height: 10, radius: 5)),
          ]),
        ),
      ]),
    );
  }
}
