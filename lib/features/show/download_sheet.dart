import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/strings.dart';
import '../../app/strings_ui.dart';
import '../../app/theme.dart';
import '../../core/models.dart';
import 'episode_selection.dart';

/// What the user chose in the batch download sheet.
class DownloadChoice {
  DownloadChoice(this.episodes, this.audio, this.quality);
  final List<EpisodeInfo> episodes;
  final AudioType audio;
  final String quality;
}

/// Batch download: whole season, unwatched only, or a typed range, with
/// audio and quality picked once. The button always says how many episodes
/// it will add.
Future<DownloadChoice?> showDownloadSheet(
  BuildContext context, {
  required List<EpisodeInfo> episodes,
  required Set<String> finished,
  required AudioType audio,
  required String quality,
  required bool hasDub,
}) {
  return showModalBottomSheet<DownloadChoice>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (ctx) => _DownloadSheet(episodes: episodes, finished: finished, audio: audio, quality: quality, hasDub: hasDub),
  );
}

enum _Preset { season, unwatched, range }

class _DownloadSheet extends StatefulWidget {
  const _DownloadSheet({required this.episodes, required this.finished, required this.audio, required this.quality, required this.hasDub});
  final List<EpisodeInfo> episodes;
  final Set<String> finished;
  final AudioType audio;
  final String quality;
  final bool hasDub;

  @override
  State<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<_DownloadSheet> {
  late final List<double> _nums = widget.episodes.map((e) => e.numeric).toList()..sort();
  late final _from = TextEditingController(text: _fmt(_nums.first));
  late final _to = TextEditingController(text: _fmt(_nums.last));
  late AudioType _audio = widget.audio;
  late String _quality = widget.quality;
  _Preset _preset = _Preset.season;

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  List<EpisodeInfo> get _chosen {
    final List<EpisodeInfo> list;
    switch (_preset) {
      case _Preset.season:
        list = widget.episodes;
      case _Preset.unwatched:
        list = widget.episodes.where((e) => !widget.finished.contains(e.number)).toList();
      case _Preset.range:
        final a = double.tryParse(_from.text.trim());
        final b = double.tryParse(_to.text.trim());
        list = a == null || b == null ? const [] : episodesBetween(widget.episodes, a, b);
    }
    return _audio == AudioType.dub ? list.where((e) => e.hasDub).toList() : list;
  }

  void _setPreset(_Preset p) {
    setState(() {
      _preset = p;
      if (p == _Preset.season) {
        _from.text = _fmt(_nums.first);
        _to.text = _fmt(_nums.last);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = Strings.of(context);
    final t = Theme.of(context).textTheme;
    final chosen = _chosen;
    Widget field(TextEditingController c, String label) => Expanded(
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(labelText: label),
            onTap: () => c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length),
            onChanged: (_) => setState(() => _preset = _Preset.range),
          ),
        );
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(Gap.m, 0, Gap.m, MediaQuery.viewInsetsOf(context).bottom + Gap.m),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr.downloadEpisodes, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: Gap.m),
          Wrap(spacing: Gap.s, runSpacing: Gap.s, children: [
            ChoiceChip(label: Text(tr.wholeSeason), selected: _preset == _Preset.season, onSelected: (_) => _setPreset(_Preset.season)),
            ChoiceChip(label: Text(tr.unwatched), selected: _preset == _Preset.unwatched, onSelected: (_) => _setPreset(_Preset.unwatched)),
          ]),
          const SizedBox(height: Gap.m),
          Row(children: [
            field(_from, tr.fromEpisode),
            const SizedBox(width: Gap.m),
            field(_to, tr.toEpisode),
          ]),
          const SizedBox(height: Gap.m),
          Wrap(spacing: Gap.m, runSpacing: Gap.s, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (widget.hasDub)
              SegmentedButton<AudioType>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: AudioType.sub, label: Text(tr.sub)),
                  ButtonSegment(value: AudioType.dub, label: Text(tr.dub)),
                ],
                selected: {_audio},
                onSelectionChanged: (s) => setState(() => _audio = s.first),
              ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(tr.qualityLabel, style: t.bodyMedium?.copyWith(color: Colors.white60)),
              const SizedBox(width: Gap.s),
              DropdownButton<String>(
                value: _quality,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(Radii.small),
                items: [
                  DropdownMenuItem(value: 'best', child: Text(tr.bestQuality)),
                  for (final q in const ['1080', '720', '480', '360']) DropdownMenuItem(value: q, child: Text('${q}p')),
                ],
                onChanged: (v) => setState(() => _quality = v ?? _quality),
              ),
            ]),
          ]),
          const SizedBox(height: Gap.s),
          Text(tr.alreadyDownloadedSkipped, style: t.bodySmall?.copyWith(color: Colors.white54)),
          const SizedBox(height: Gap.m),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.download_rounded),
              label: Text(chosen.isEmpty ? tr.nothingInRange : tr.episodesToDownload(chosen.length)),
              onPressed: chosen.isEmpty ? null : () => Navigator.pop(context, DownloadChoice(chosen, _audio, _quality)),
            ),
          ),
        ]),
      ),
    );
  }
}
