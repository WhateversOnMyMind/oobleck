import 'dart:ui';

import 'package:flutter/material.dart';

import '../app/theme.dart';

/// Lets a row be dragged with the mouse as well as touch and trackpad.
class _DragScrollBehavior extends MaterialScrollBehavior {
  const _DragScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };

  // No scrollbar under a row of covers; the arrows show there is more.
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

/// A horizontal row of cards that is comfortable with every input: swipe on
/// touch, drag with the mouse, Shift + wheel, and arrow buttons that appear on
/// hover when there is more to see. Pass [storageKey] to keep the scroll
/// position when the screen is rebuilt (for example after switching tabs).
class HScrollRow extends StatefulWidget {
  const HScrollRow({
    super.key,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.spacing = Gap.m,
    this.padding = const EdgeInsets.symmetric(horizontal: Gap.m),
    this.storageKey,
  });

  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double spacing;
  final EdgeInsets padding;
  final String? storageKey;

  @override
  State<HScrollRow> createState() => _HScrollRowState();
}

class _HScrollRowState extends State<HScrollRow> {
  final _controller = ScrollController();
  bool _hovered = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _page(int direction) {
    final p = _controller.position;
    final target = (p.pixels + direction * p.viewportDimension * 0.8).clamp(p.minScrollExtent, p.maxScrollExtent);
    _controller.animateTo(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Stack(children: [
          ScrollConfiguration(
            behavior: const _DragScrollBehavior(),
            child: ListView.separated(
              key: widget.storageKey == null ? null : PageStorageKey<String>(widget.storageKey!),
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: widget.padding,
              itemCount: widget.itemCount,
              separatorBuilder: (_, _) => SizedBox(width: widget.spacing),
              itemBuilder: widget.itemBuilder,
            ),
          ),
          if (_hovered)
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) {
                if (!_controller.hasClients || !_controller.position.hasContentDimensions) return const SizedBox.shrink();
                final p = _controller.position;
                return Stack(children: [
                  if (p.pixels > p.minScrollExtent + 1)
                    _Arrow(alignment: Alignment.centerLeft, icon: Icons.chevron_left_rounded, onTap: () => _page(-1)),
                  if (p.pixels < p.maxScrollExtent - 1)
                    _Arrow(alignment: Alignment.centerRight, icon: Icons.chevron_right_rounded, onTap: () => _page(1)),
                ]);
              },
            ),
        ]),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.alignment, required this.icon, required this.onTap});
  final Alignment alignment;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.s),
          child: Material(
            color: Colors.black.withValues(alpha: 0.72),
            shape: const CircleBorder(side: BorderSide(color: Colors.white24)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(padding: const EdgeInsets.all(Gap.s), child: Icon(icon, size: 28)),
            ),
          ),
        ),
      ),
    );
  }
}
