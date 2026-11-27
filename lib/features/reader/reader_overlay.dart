import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../core/storage/app_db.dart';
import '../../ui/dimming.dart';
import '../manga/manga_strings.dart';
import 'reader_controller.dart';
import 'reader_settings.dart';

/// Top and bottom bars of the reader, shown on a tap in the middle.
class ReaderOverlay extends ConsumerWidget {
  const ReaderOverlay({super.key, required this.c, required this.onClose});
  final ReaderController c;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = Strings.of(context);
    final t = Theme.of(context).textTheme;
    final pad = MediaQuery.paddingOf(context);
    final rc = c.current;
    final total = rc?.pages.length ?? 0;
    final db = ref.read(dbProvider);
    final bookmarked = rc == null ? false : (db.chapterState(c.mangaKey, rc.chapter.id)?.bookmarked ?? false);
    const bar = Color(0xE6101016);
    return Stack(children: [
      // Top bar
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Material(
          color: bar,
          child: Padding(
            padding: EdgeInsets.fromLTRB(4 + pad.left, pad.top + 4, 4 + pad.right, 4),
            child: Row(children: [
              IconButton(tooltip: tr.back, icon: const Icon(Icons.arrow_back_rounded), onPressed: onClose),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(c.manga.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  if (rc != null)
                    Text(rc.chapter.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: Colors.white70)),
                ]),
              ),
              if (rc != null)
                IconButton(
                  tooltip: bookmarked ? tr.removeBookmark : tr.bookmark,
                  icon: Icon(bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
                  onPressed: () async {
                    await db.setBookmarked(c.mangaKey, [rc.chapter.id], !bookmarked);
                    c.toggleMenu(true); // redraw
                  },
                ),
              IconButton(
                tooltip: tr.readerSettings,
                icon: const Icon(Icons.tune_rounded),
                onPressed: () => showReaderSettings(context, c),
              ),
            ]),
          ),
        ),
      ),
      // Bottom bar
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Material(
          color: bar,
          child: Padding(
            padding: EdgeInsets.fromLTRB(8 + pad.left, 6, 8 + pad.right, 8 + pad.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                IconButton(
                  tooltip: tr.previousChapter,
                  icon: const Icon(Icons.skip_previous_rounded),
                  onPressed: c.previousChapter == null ? null : () => unawaited(c.goTo(c.previousChapter!)),
                ),
                Expanded(
                  child: total <= 1
                      ? const SizedBox(height: 48)
                      : Directionality(
                          // In right-to-left books the slider runs right to left too.
                          textDirection: c.mode == ReaderMode.rtl ? TextDirection.rtl : TextDirection.ltr,
                          child: _PageSlider(c: c, total: total),
                        ),
                ),
                IconButton(
                  tooltip: tr.nextChapter,
                  icon: const Icon(Icons.skip_next_rounded),
                  onPressed: c.nextChapter == null ? null : () => unawaited(c.goTo(c.nextChapter!)),
                ),
              ]),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _ModeButton(c: c),
                _QuickToggle(
                  icon: Icons.auto_fix_high_rounded,
                  label: tr.upscale,
                  value: ref.watch(readerSettingsProvider).upscale,
                  onChanged: (v) => ref.read(readerSettingsProvider.notifier).set('upscale', v),
                ),
                if (!(Platform.isAndroid || Platform.isIOS))
                  Tooltip(
                    message: tr.readerHelpDesktop,
                    child: const Padding(padding: EdgeInsets.all(12), child: Icon(Icons.keyboard_rounded, color: Colors.white54)),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _PageSlider extends StatefulWidget {
  const _PageSlider({required this.c, required this.total});
  final ReaderController c;
  final int total;
  @override
  State<_PageSlider> createState() => _PageSliderState();
}

class _PageSliderState extends State<_PageSlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final page = (_drag ?? widget.c.page.toDouble()).clamp(0, widget.total - 1).toDouble();
    return Row(children: [
      SizedBox(width: 36, child: Text('${page.round() + 1}', textAlign: TextAlign.center)),
      Expanded(
        child: Slider(
          value: page,
          min: 0,
          max: (widget.total - 1).toDouble(),
          divisions: widget.total - 1,
          label: '${page.round() + 1}',
          onChanged: (v) => setState(() => _drag = v),
          onChangeEnd: (v) {
            setState(() => _drag = null);
            widget.c.command(JumpTo(v.round()));
          },
        ),
      ),
      SizedBox(width: 36, child: Text('${widget.total}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54))),
    ]);
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.c});
  final ReaderController c;

  @override
  Widget build(BuildContext context) {
    final tr = Strings.of(context);
    return PopupMenuButton<ReaderMode>(
      tooltip: tr.readingMode,
      onSelected: (m) => unawaited(c.setMode(m)),
      itemBuilder: (_) => [
        for (final m in ReaderMode.values)
          CheckedPopupMenuItem(
            value: m,
            checked: (c.manga.readerMode ?? 'auto') == m.name,
            child: Text(tr.readerModeLabel(m.name)),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(c.mode.icon),
          const SizedBox(height: 2),
          Text(tr.readerModeLabel(c.mode.name), style: Theme.of(context).textTheme.labelSmall),
        ]),
      ),
    );
  }
}

class _QuickToggle extends StatelessWidget {
  const _QuickToggle({required this.icon, required this.label, required this.value, required this.onChanged});
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: value ? scheme.primary : Colors.white54),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: value ? scheme.primary : Colors.white54)),
        ]),
      ),
    );
  }
}

/// The reader settings sheet (also reachable from Settings).
Future<void> showReaderSettings(BuildContext context, [ReaderController? c]) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (context, scroll) => ReaderSettingsList(controller: scroll, reader: c),
      ),
    );

/// All reader options. With [reader], the mode choice applies to that series.
class ReaderSettingsList extends ConsumerWidget {
  const ReaderSettingsList({super.key, this.controller, this.reader, this.shrinkWrap = false});
  final ScrollController? controller;
  final ReaderController? reader;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = Strings.of(context);
    final s = ref.watch(readerSettingsProvider);
    final n = ref.read(readerSettingsProvider.notifier);
    final mobile = Platform.isAndroid || Platform.isIOS;
    Widget header(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary)),
        );
    Widget choice<T extends Enum>(String title, T value, List<T> values, String Function(String) label, ValueChanged<T> onChanged) =>
        ListTile(
          title: Text(title),
          trailing: DropdownButton<T>(
            value: value,
            underline: const SizedBox(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
            items: [for (final v in values) DropdownMenuItem(value: v, child: Text(label(v.name)))],
          ),
        );
    final seriesMode = reader == null ? null : ReaderMode.parse(reader!.manga.readerMode, ReaderMode.auto);
    return ListView(
      controller: controller,
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      children: [
        header(tr.readingMode),
        if (reader != null)
          choice<ReaderMode>(tr.readerModeForSeries, seriesMode!, ReaderMode.values, tr.readerModeLabel, (m) => unawaited(reader!.setMode(m)))
        else
          choice<ReaderMode>(tr.readingMode, s.mode, ReaderMode.values, tr.readerModeLabel, (m) => n.set('mode', m)),
        if (s.mode == ReaderMode.auto && reader == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(tr.readerAutoHint, style: const TextStyle(color: Colors.white54)),
          ),
        choice<PageScale>(tr.scaleType, s.scale, PageScale.values, tr.scaleLabel, (v) => n.set('scale', v)),
        choice<TapLayout>(tr.tapZones, s.tapLayout, TapLayout.values, tr.tapLayoutLabel, (v) => n.set('tapLayout', v)),
        SwitchListTile(title: Text(tr.invertTaps), value: s.invertTaps, onChanged: (v) => n.set('invertTaps', v)),
        SwitchListTile(title: Text(tr.autoNextChapter), value: s.autoNextChapter, onChanged: (v) => n.set('autoNextChapter', v)),
        ListTile(
          title: Text(tr.webtoonPadding),
          subtitle: Slider(
            value: s.webtoonPadding,
            max: 0.3,
            divisions: 6,
            label: '${(s.webtoonPadding * 100).round()}%',
            onChanged: (v) => n.set('webtoonPadding', v),
          ),
        ),
        header(tr.display),
        SwitchListTile(
          title: Text(tr.upscale),
          subtitle: Text(tr.upscaleHint),
          value: s.upscale,
          onChanged: (v) => n.set('upscale', v),
        ),
        if (s.upscale)
          ListTile(
            title: Text(tr.sharpness),
            subtitle: Slider(
              value: s.sharpness,
              divisions: 10,
              label: '${(s.sharpness * 100).round()}%',
              onChanged: (v) => n.set('sharpness', v),
            ),
          ),
        choice<ReaderBackground>(tr.background, s.background, ReaderBackground.values, tr.backgroundLabel, (v) => n.set('background', v)),
        ListTile(
          title: Text(tr.dimPages),
          subtitle: Slider(
            value: s.dim,
            max: 0.8,
            divisions: 8,
            label: '${(s.dim * 100).round()}%',
            onChanged: (v) => n.set('dim', v),
          ),
        ),
        if (mobile)
          ListTile(
            title: Row(children: [
              Expanded(child: Text(tr.brightness)),
              if (s.brightness != null)
                TextButton(onPressed: () => n.set('brightness', null), child: Text(tr.brightnessUsePhone))
              else
                Text(tr.brightnessPhone, style: const TextStyle(color: Colors.white54)),
            ]),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Slider(
                value: s.brightness ?? 0.5,
                min: Dimming.darkest,
                max: 1,
                divisions: 38,
                label: '${Dimming.percent(s.brightness ?? 0.5)}%',
                onChanged: (v) => n.set('brightness', v),
              ),
              Text(tr.brightnessHint, style: const TextStyle(color: Colors.white54)),
            ]),
          ),
        SwitchListTile(title: Text(tr.grayscale), value: s.grayscale, onChanged: (v) => n.set('grayscale', v)),
        SwitchListTile(title: Text(tr.showPageNumber), value: s.showPageNumber, onChanged: (v) => n.set('showPageNumber', v)),
        SwitchListTile(title: Text(tr.fullscreenReader), value: s.fullscreen, onChanged: (v) => n.set('fullscreen', v)),
        header(tr.more),
        SwitchListTile(title: Text(tr.keepScreenOn), value: s.keepScreenOn, onChanged: (v) => n.set('keepScreenOn', v)),
        if (mobile) SwitchListTile(title: Text(tr.volumeKeys), value: s.volumeKeys, onChanged: (v) => n.set('volumeKeys', v)),
        SwitchListTile(title: Text(tr.incognito), value: s.incognito, onChanged: (v) => n.set('incognito', v)),
        const SizedBox(height: 24),
      ],
    );
  }
}
