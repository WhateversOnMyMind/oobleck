import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/downloads/download_manager.dart';
import '../../core/models.dart';
import '../../core/player/anime4k.dart';
import '../../core/storage/records.dart';
import '../../ui/widgets.dart';
import 'diagnostics_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final downloads = ref.watch(downloadsProvider).value ?? const <DownloadRecord>[];
    final used = downloads.where((d) => d.isDone).fold<int>(0, (a, d) => a + d.totalBytes);

    return CustomScrollView(slivers: [
      const SliverAppBar(floating: true, title: Text('Settings', style: TextStyle(fontWeight: FontWeight.w800))),
      SliverList.list(children: [
        const _Header('Playback'),
        _Choice<AudioType>(
          icon: Icons.record_voice_over_rounded,
          title: 'Default audio',
          value: s.audio,
          options: const {AudioType.sub: 'Subbed', AudioType.dub: 'Dubbed'},
          onChanged: (v) => n.set('audio', v.name),
        ),
        _Choice<String>(
          icon: Icons.dns_rounded,
          title: 'Preferred server',
          value: s.serverOrder.first,
          options: {for (final x in const ['HD-1', 'HD-2', 'Vidstream-1', 'Vidstream-2', 'Kiwi']) x: x},
          onChanged: (v) => n.set('serverOrder', [v, ...const ['HD-1', 'HD-2', 'Vidstream-1', 'Vidstream-2', 'Kiwi'].where((x) => x != v)]),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.skip_next_rounded),
          title: const Text('Play next episode automatically'),
          value: s.autoNext,
          onChanged: (v) => n.set('autoNext', v),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.fast_forward_rounded),
          title: const Text('Show "Skip intro" button'),
          value: s.skipIntroButton,
          onChanged: (v) => n.set('skipIntroButton', v),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.translate_rounded),
          title: const Text('Korean subtitles automatically'),
          subtitle: const Text('Finds a Korean fansub for each episode and turns it on'),
          value: s.autoKoreanSubs,
          onChanged: (v) => n.set('autoKoreanSubs', v),
        ),
        _Choice<String>(
          icon: Icons.auto_awesome_rounded,
          title: 'Anime4K upscaling',
          subtitle: 'Real-time only. Downloads keep their original quality.',
          value: s.anime4k,
          options: {for (final p in Anime4K.presets) p.$1: p.$2},
          onChanged: (v) => n.set('anime4k', v),
        ),
        const _Header('Subtitles'),
        _Choice<String>(
          icon: Icons.closed_caption_rounded,
          title: 'Preferred language',
          value: s.subtitleLanguage,
          options: const {'en': 'English', 'ko': 'Korean', 'ja': 'Japanese', 'es': 'Spanish', 'pt': 'Portuguese', 'fr': 'French', 'de': 'German', 'ar': 'Arabic', 'id': 'Indonesian'},
          onChanged: (v) => n.set('subtitleLanguage', v),
        ),
        const ListTile(
          leading: Icon(Icons.tune_rounded),
          title: Text('Style & timing'),
          subtitle: Text('Open CC > Style & timing while watching to adjust size, colour, outline and sync.'),
        ),
        _TextSetting(
          icon: Icons.key_rounded,
          title: 'OpenSubtitles API key',
          subtitle: 'Optional. Enables searching OpenSubtitles for Korean subs.',
          value: s.openSubtitlesKey,
          obscure: true,
          onSaved: (v) => n.set('openSubtitlesKey', v),
        ),
        if (s.openSubtitlesKey.isNotEmpty) ...[
          _TextSetting(icon: Icons.person_outline_rounded, title: 'OpenSubtitles username', value: s.openSubtitlesUser, onSaved: (v) => n.set('openSubtitlesUser', v)),
          _TextSetting(icon: Icons.password_rounded, title: 'OpenSubtitles password', value: s.openSubtitlesPass, obscure: true, onSaved: (v) => n.set('openSubtitlesPass', v)),
        ],
        const _Header('Downloads'),
        _Choice<String>(
          icon: Icons.high_quality_rounded,
          title: 'Download quality',
          value: s.quality,
          options: const {'best': 'Best available', '1080': '1080p', '720': '720p', '480': '480p', '360': '360p'},
          onChanged: (v) => n.set('quality', v),
        ),
        _Choice<int>(
          icon: Icons.layers_rounded,
          title: 'Episodes at once',
          value: s.maxConcurrent,
          options: const {1: '1', 2: '2', 3: '3', 4: '4'},
          onChanged: (v) => n.set('maxConcurrent', v),
        ),
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: const Text('Download location'),
          subtitle: FutureBuilder<String>(
            future: ref.read(downloadManagerProvider).downloadRoot(),
            builder: (c, snap) => Text(snap.data ?? '…'),
          ),
          trailing: TextButton(
            child: const Text('Change'),
            onPressed: () async {
              final dir = await FilePicker.getDirectoryPath();
              if (dir != null) await n.set('downloadDir', dir);
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.storage_rounded),
          title: const Text('Storage used by downloads'),
          trailing: Text(formatBytes(used), style: const TextStyle(color: Colors.white70)),
        ),
        const _Header('Data'),
        ListTile(
          leading: const Icon(Icons.history_rounded),
          title: const Text('Clear watch history'),
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Clear watch history?'),
                content: const Text('Resume positions and Continue watching will be reset. Downloads are kept.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
                ],
              ),
            );
            if (ok == true) await ref.read(dbProvider).clearHistory();
          },
        ),
        const _Header('Advanced'),
        ExpansionTile(
          leading: const Icon(Icons.build_outlined),
          title: const Text('Advanced'),
          shape: const Border(),
          collapsedShape: const Border(),
          children: [
            SwitchListTile(
              title: const Text('Use Kiwi server'),
              value: s.enableKiwi,
              onChanged: (v) => n.set('enableKiwi', v),
            ),
            _TextSetting(icon: Icons.vpn_key_outlined, title: 'Megaplay AES key', subtitle: 'Leave empty to use the built-in key.', value: s.megaplayAesKey, onSaved: (v) => n.set('megaplayAesKey', v)),
            _TextSetting(icon: Icons.vpn_key_outlined, title: 'Megaplay IV', value: s.megaplayIv, onSaved: (v) => n.set('megaplayIv', v)),
            _TextSetting(icon: Icons.vpn_key_outlined, title: 'Megaplay token key', value: s.megaplayTokenKey, onSaved: (v) => n.set('megaplayTokenKey', v)),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: const Text('Source diagnostics'),
              subtitle: const Text('Step through search, episodes, servers and streams.'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DiagnosticsScreen())),
            ),
          ],
        ),
        const _Header('About'),
        ListTile(
          leading: const Icon(Icons.info_outline_rounded),
          title: const Text('Oobleck'),
          subtitle: Text('Personal anime player · ${Platform.isWindows ? 'Windows' : 'Android'}'),
        ),
        const SizedBox(height: Gap.xl),
      ]),
    ]);
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Gap.m, Gap.l, Gap.m, Gap.xs),
        child: Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelMedium?.copyWith(color: kAccent, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      );
}

class _Choice<T> extends StatelessWidget {
  const _Choice({required this.icon, required this.title, required this.value, required this.options, required this.onChanged, this.subtitle});
  final IconData icon;
  final String title;
  final String? subtitle;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle ?? options[value] ?? '$value'),
      onTap: () async {
        final picked = await showModalBottomSheet<T>(
          context: context,
          builder: (ctx) => SafeArea(
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(padding: const EdgeInsets.all(Gap.m), child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
                for (final e in options.entries)
                  ListTile(
                    title: Text(e.value),
                    trailing: e.key == value ? const Icon(Icons.check_rounded, color: kAccent) : null,
                    onTap: () => Navigator.pop(ctx, e.key),
                  ),
              ]),
            ),
          ),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}

class _TextSetting extends StatelessWidget {
  const _TextSetting({required this.icon, required this.title, required this.value, required this.onSaved, this.subtitle, this.obscure = false});
  final IconData icon;
  final String title;
  final String? subtitle;
  final String value;
  final bool obscure;
  final ValueChanged<String> onSaved;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value.isEmpty ? (subtitle ?? 'Not set') : (obscure ? '••••••••' : value), maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () async {
        final c = TextEditingController(text: value);
        final r = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: TextField(controller: c, obscureText: obscure, autofocus: true),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
            ],
          ),
        );
        if (r != null) onSaved(r);
      },
    );
  }
}
