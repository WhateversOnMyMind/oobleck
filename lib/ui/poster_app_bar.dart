import 'dart:ui';

import 'package:flutter/material.dart';

import '../app/theme.dart';
import 'widgets.dart';

/// Pinned header for a detail page: cover art that collapses into a normal
/// app bar, with the page [title] fading in once the art has scrolled away,
/// so you always know which show you are in.
///
/// On wide windows a cover stretched across the whole width is mostly blur,
/// so it becomes a soft backdrop with the sharp cover on the left.
/// [barTitle] replaces the title while it is set (e.g. "3 selected").
class PosterSliverAppBar extends StatelessWidget {
  const PosterSliverAppBar({
    super.key,
    required this.title,
    this.posterUrl,
    this.posterPath,
    this.barTitle,
    this.leading,
    this.actions = const [],
    this.expandedHeight = 280,
  });

  final String title;
  final String? posterUrl;
  final String? posterPath;
  final Widget? barTitle;
  final Widget? leading;
  final List<Widget> actions;
  final double expandedHeight;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final poster = PosterImage(url: posterUrl, localPath: posterPath);
    return SliverAppBar(
      pinned: true,
      expandedHeight: expandedHeight,
      leading: leading,
      actions: actions,
      title: barTitle ?? _FadeInWhenCollapsed(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(fit: StackFit.expand, children: [
          if (wide) ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28), child: poster) else poster,
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [const Color(0x66000000), wide ? const Color(0x55000000) : const Color(0x00000000), kBackground],
                stops: const [0, 0.35, 1],
              ),
            ),
          ),
          if (wide)
            Positioned(
              left: Gap.m,
              bottom: Gap.s,
              top: kToolbarHeight + MediaQuery.paddingOf(context).top,
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(borderRadius: BorderRadius.circular(Radii.card), child: poster),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Invisible while the header is expanded, fades in over its last quarter.
class _FadeInWhenCollapsed extends StatelessWidget {
  const _FadeInWhenCollapsed({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    var opacity = 1.0;
    if (s != null && s.maxExtent > s.minExtent) {
      final expanded = ((s.currentExtent - s.minExtent) / (s.maxExtent - s.minExtent)).clamp(0.0, 1.0);
      opacity = 1 - (expanded / 0.25).clamp(0.0, 1.0);
    }
    return IgnorePointer(ignoring: opacity == 0, child: Opacity(opacity: opacity, child: child));
  }
}

/// Bottom bar for a page's primary action, kept within thumb reach and
/// clear of the system gesture area. Use as `Scaffold.bottomNavigationBar`.
class StickyActionBar extends StatelessWidget {
  const StickyActionBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: kSurface, border: Border(top: BorderSide(color: Colors.white10))),
      child: SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, Gap.s), child: child),
      ),
    );
  }
}
