import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../app/strings.dart';
import '../manga/manga_strings.dart';
import 'reader_controller.dart';
import 'reader_page.dart';
import 'reader_settings.dart';

/// An entry of the strip: a page, or the gap card between two chapters.
class _Item {
  const _Item.page(this.segment, this.page) : transition = false;
  const _Item.transition(this.segment)
      : page = -1,
        transition = true;
  final int segment;
  final int page;
  final bool transition;
}

/// Long-strip reader (webtoon, or vertical pages with gaps). Scrolls on into
/// the next chapter when the setting is on.
class ScrollReader extends StatefulWidget {
  const ScrollReader({
    super.key,
    required this.c,
    required this.settings,
    required this.gaps,
    required this.onTap,
    required this.onLongPressPage,
  });

  final ReaderController c;
  final ReaderSettings settings;
  final bool gaps;
  final void Function(TapAction action) onTap;
  final void Function(Uint8List bytes) onLongPressPage;

  @override
  State<ScrollReader> createState() => _ScrollReaderState();
}

class _ScrollReaderState extends State<ScrollReader> {
  final _items = ItemScrollController();
  final _offsets = ScrollOffsetController();
  final _positions = ItemPositionsListener.create();
  final _zoom = TransformationController();
  StreamSubscription<ReaderCommand>? _cmds;
  List<_Item> _list = const [];

  /// Until the user scrolls, a page whose real size arrives re-aligns the
  /// restored position.
  bool _userMoved = false;
  bool _restored = false;
  final _finishedSegments = <int>{};

  ReaderController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _positions.itemPositions.addListener(_onPositions);
    _cmds = c.commands.listen(_onCommand);
  }

  @override
  void dispose() {
    _positions.itemPositions.removeListener(_onPositions);
    unawaited(_cmds?.cancel());
    _zoom.dispose();
    super.dispose();
  }

  List<_Item> _build() => [
        for (var s = 0; s < c.segments.length; s++) ...[
          for (var p = 0; p < c.segments[s].pages.length; p++) _Item.page(s, p),
          _Item.transition(s),
        ],
      ];

  int _indexOf(int segment, int page) => _list.indexWhere((i) => i.segment == segment && i.page == page && !i.transition);

  void _onCommand(ReaderCommand cmd) {
    if (!_items.isAttached) return;
    switch (cmd) {
      case JumpTo(:final page):
        _userMoved = true;
        final i = _indexOf(c.segment, page);
        if (i >= 0) _items.jumpTo(index: i);
      case PageStep(:final direction):
        _scrollBy(direction);
    }
  }

  void _scrollBy(int direction) {
    _userMoved = true;
    final h = context.size?.height ?? 600;
    unawaited(_offsets.animateScroll(offset: direction * h * 0.8, duration: const Duration(milliseconds: 220), curve: Curves.easeOut));
  }

  void _onPositions() {
    final pos = _positions.itemPositions.value.where((p) => p.index < _list.length).toList();
    if (pos.isEmpty) return;
    pos.sort((a, b) => a.index.compareTo(b.index));
    // The item covering the top of the screen (or the first one below it).
    final top = pos.firstWhere((p) => p.itemTrailingEdge > 0.02, orElse: () => pos.first);
    final item = _list[top.index];
    final last = pos.last;

    // A chapter is finished once its end card scrolls into view.
    for (final p in pos) {
      final it = _list[p.index];
      if (it.transition && p.itemLeadingEdge < 1 && _finishedSegments.add(it.segment)) {
        final seg = c.segments[it.segment];
        if (seg.pages.isNotEmpty) c.onPosition(it.segment, seg.pages.length - 1, 1, finished: true);
        if (widget.settings.autoNextChapter && it.segment == c.segments.length - 1) unawaited(c.appendNext());
      }
    }
    if (item.transition) return;
    final height = top.itemTrailingEdge - top.itemLeadingEdge;
    final offset = height <= 0 ? 0.0 : (-top.itemLeadingEdge / height).clamp(0.0, 1.0);
    c.onPosition(item.segment, item.page, offset);
    // Start loading the next chapter a few pages before the end.
    final lastItem = _list[last.index];
    if (widget.settings.autoNextChapter && lastItem.segment == c.segments.length - 1) {
      final seg = c.segments[lastItem.segment];
      if (!lastItem.transition && lastItem.page >= seg.pages.length - 3) unawaited(c.appendNext());
    }
  }

  double _stripWidth(BoxConstraints box) {
    var w = box.maxWidth;
    // On a wide desktop window a full-width strip is uncomfortably large.
    if (!(Platform.isAndroid || Platform.isIOS) && w > box.maxHeight && w > 960) w = 960;
    return w * (1 - 2 * widget.settings.webtoonPadding.clamp(0.0, 0.3));
  }

  void _restore(double width, double viewport) {
    if (_restored || !_items.isAttached) return;
    _restored = true;
    final i = _indexOf(c.segment, c.page);
    if (i < 0) return;
    _items.jumpTo(index: i, alignment: _alignmentFor(i, width, viewport));
  }

  double _alignmentFor(int index, double width, double viewport) {
    final item = _list[index];
    final ref = c.segments[item.segment].pages[item.page];
    final itemH = width * (c.aspects[ref.id] ?? 1.45);
    return -(c.offset * itemH) / viewport;
  }

  @override
  Widget build(BuildContext context) {
    _list = _build();
    final tr = Strings.of(context);
    return LayoutBuilder(builder: (context, box) {
      final width = _stripWidth(box);
      if (!_restored && c.segments.isNotEmpty && c.segments.first.pages.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _restore(width, box.maxHeight));
      }
      return Listener(
        onPointerDown: (_) => _userMoved = true,
        onPointerSignal: (_) => _userMoved = true,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (d) => widget.onTap(tapActionAt(
            widget.settings.tapLayout,
            d.localPosition.dx / box.maxWidth,
            d.localPosition.dy / box.maxHeight,
            invert: widget.settings.invertTaps,
          )),
          child: InteractiveViewer(
            transformationController: _zoom,
            minScale: 1,
            maxScale: 4,
            scaleEnabled: true,
            panEnabled: true,
            child: ScrollablePositionedList.builder(
              itemCount: _list.length,
              itemScrollController: _items,
              scrollOffsetController: _offsets,
              itemPositionsListener: _positions,
              minCacheExtent: box.maxHeight * 1.5,
              itemBuilder: (context, i) {
                final item = _list[i];
                final seg = c.segments[item.segment];
                if (item.transition) return _transition(tr, item.segment, width);
                final ref = seg.pages[item.page];
                return Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: widget.gaps ? 10 : 0),
                    child: SizedBox(
                      width: width,
                      child: ReaderPage(
                        key: ValueKey(ref.id),
                        pageRef: ref,
                        load: c.bytesOf,
                        number: item.page + 1,
                        fit: BoxFit.fitWidth,
                        displayWidth: width,
                        placeholderAspect: c.aspects[ref.id] ?? 1.45,
                        upscale: widget.settings.upscale,
                        sharpness: widget.settings.sharpness,
                        onLongPress: widget.onLongPressPage,
                        onSize: (s) {
                          final first = !c.aspects.containsKey(ref.id);
                          c.aspects[ref.id] = s.height / s.width;
                          // Re-align a restored position once the target page knows its height.
                          if (first && !_userMoved && item.segment == c.segment && item.page == c.page && c.offset > 0) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (_items.isAttached && !_userMoved) {
                                _items.jumpTo(index: i, alignment: _alignmentFor(i, width, box.maxHeight));
                              }
                            });
                          }
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    });
  }

  Widget _transition(Strings tr, int segment, double width) {
    final seg = c.segments[segment];
    final nextLoaded = segment + 1 < c.segments.length ? c.segments[segment + 1] : null;
    final next = nextLoaded?.chapter ?? (segment == c.segments.length - 1 ? c.nextChapter : null);
    final t = Theme.of(context).textTheme;
    final dark = widget.settings.background != ReaderBackground.white;
    final fg = dark ? Colors.white : Colors.black87;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width.clamp(280, 560)),
          child: Column(children: [
            Text(tr.finishedChapter(seg.chapter.title), style: t.titleMedium?.copyWith(color: fg.withValues(alpha: 0.7))),
            const SizedBox(height: 10),
            if (next == null)
              Text(tr.noNextChapter, style: t.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w700))
            else ...[
              Text(tr.upNext(next.title), style: t.titleLarge?.copyWith(color: fg, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              if (nextLoaded == null || !widget.settings.autoNextChapter)
                FilledButton.icon(
                  onPressed: () => unawaited(c.goTo(next)),
                  icon: const Icon(Icons.skip_next_rounded),
                  label: Text(tr.nextChapter),
                )
              else if (nextLoaded.loading)
                const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5))
              else if (nextLoaded.error != null)
                FilledButton.tonalIcon(
                  onPressed: () => unawaited(c.goTo(next)),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(tr.retry),
                )
              else
                Icon(Icons.keyboard_double_arrow_down_rounded, color: fg.withValues(alpha: 0.5), size: 32),
            ],
          ]),
        ),
      ),
    );
  }
}
