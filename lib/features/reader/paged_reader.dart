import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/strings.dart';
import '../manga/manga_strings.dart';
import 'reader_controller.dart';
import 'reader_page.dart';
import 'reader_settings.dart';

/// Book-style reader: one page per screen, turned by swiping or tapping.
/// The page after the last one is a chapter end card; going on from there
/// opens the next chapter.
class PagedReader extends StatefulWidget {
  const PagedReader({
    super.key,
    required this.c,
    required this.settings,
    required this.onTap,
    required this.onLongPressPage,
  });

  final ReaderController c;
  final ReaderSettings settings;
  final void Function(TapAction action) onTap;
  final void Function(Uint8List bytes) onLongPressPage;

  @override
  State<PagedReader> createState() => _PagedReaderState();
}

class _PagedReaderState extends State<PagedReader> {
  late final PageController _pages = PageController(initialPage: widget.c.page);
  StreamSubscription<ReaderCommand>? _cmds;
  final _zoom = <int, TransformationController>{};
  bool _zoomed = false;
  Offset? _doubleTapAt;

  ReaderController get c => widget.c;
  ReaderMode get mode => c.mode;
  int get _pageCount => c.current?.pages.length ?? 0;

  @override
  void initState() {
    super.initState();
    _cmds = c.commands.listen((cmd) {
      switch (cmd) {
        case JumpTo(:final page):
          if (_pages.hasClients) _pages.jumpToPage(page);
        case PageStep(:final direction):
          _step(direction);
      }
    });
    c.preloadAfter(c.page);
  }

  @override
  void dispose() {
    unawaited(_cmds?.cancel());
    _pages.dispose();
    for (final z in _zoom.values) {
      z.dispose();
    }
    super.dispose();
  }

  void _step(int direction) {
    if (!_pages.hasClients) return;
    final target = (_pages.page?.round() ?? c.page) + direction;
    if (target < 0) return;
    if (target > _pageCount) {
      final next = c.nextChapter;
      if (next != null) unawaited(c.goTo(next));
      return;
    }
    unawaited(_pages.animateToPage(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOut));
  }

  void _onPageChanged(int i) {
    _resetZoom();
    if (i >= _pageCount) {
      // The end card: the chapter is done.
      if (_pageCount > 0) c.onPosition(c.segment, _pageCount - 1, 1, finished: true);
      return;
    }
    c.onPosition(c.segment, i, 0, finished: i == _pageCount - 1);
  }

  void _resetZoom() {
    for (final z in _zoom.values) {
      z.value = Matrix4.identity();
    }
    if (_zoomed) setState(() => _zoomed = false);
  }

  TransformationController _zoomFor(int i) => _zoom.putIfAbsent(i, () {
        final z = TransformationController();
        z.addListener(() {
          final zoomed = z.value.getMaxScaleOnAxis() > 1.01;
          if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
        });
        return z;
      });

  void _toggleZoomAt(int i) {
    final z = _zoomFor(i);
    if (z.value.getMaxScaleOnAxis() > 1.01) {
      z.value = Matrix4.identity();
      return;
    }
    final p = _doubleTapAt ?? Offset.zero;
    const s = 2.5;
    z.value = Matrix4.identity()
      ..translateByDouble(-p.dx * (s - 1), -p.dy * (s - 1), 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final tr = Strings.of(context);
    final rtl = mode == ReaderMode.rtl;
    return LayoutBuilder(builder: (context, box) {
      return PageView.builder(
        controller: _pages,
        scrollDirection: mode == ReaderMode.vertical ? Axis.vertical : Axis.horizontal,
        reverse: rtl,
        physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
        onPageChanged: _onPageChanged,
        itemCount: _pageCount + 1,
        itemBuilder: (context, i) {
          if (i >= _pageCount) return _endCard(tr);
          final ref = c.current!.pages[i];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => widget.onTap(tapActionAt(
              widget.settings.tapLayout,
              d.localPosition.dx / box.maxWidth,
              d.localPosition.dy / box.maxHeight,
              invert: widget.settings.invertTaps,
              rtl: rtl,
            )),
            onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
            onDoubleTap: () => _toggleZoomAt(i),
            child: InteractiveViewer(
              transformationController: _zoomFor(i),
              minScale: 1,
              maxScale: 5,
              child: SizedBox(
                width: box.maxWidth,
                height: box.maxHeight,
                child: _scaled(ref, i, box),
              ),
            ),
          );
        },
      );
    });
  }

  Widget _scaled(ReaderPageRef ref, int i, BoxConstraints box) {
    final page = ReaderPage(
      key: ValueKey(ref.id),
      pageRef: ref,
      load: c.bytesOf,
      number: i + 1,
      fit: widget.settings.scale.boxFit,
      upscale: widget.settings.upscale,
      sharpness: widget.settings.sharpness,
      onLongPress: widget.onLongPressPage,
    );
    // Fit width on a tall page scrolls inside the page.
    if (widget.settings.scale == PageScale.fitWidth) {
      return SingleChildScrollView(child: SizedBox(width: box.maxWidth, child: page));
    }
    return page;
  }

  Widget _endCard(Strings tr) {
    final t = Theme.of(context).textTheme;
    final next = c.nextChapter;
    final fg = widget.settings.background == ReaderBackground.white ? Colors.black87 : Colors.white;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => c.toggleMenu(),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr.finishedChapter(c.current!.chapter.title), style: t.titleMedium?.copyWith(color: fg.withValues(alpha: 0.7))),
            const SizedBox(height: 10),
            if (next == null)
              Text(tr.noNextChapter, style: t.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w700))
            else ...[
              Text(tr.upNext(next.title), textAlign: TextAlign.center, style: t.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => unawaited(c.goTo(next)),
                icon: const Icon(Icons.skip_next_rounded),
                label: Text(tr.nextChapter),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
