import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../core/downloads/download_manager.dart';
import '../../core/models.dart';
import '../../core/player/anime4k.dart';
import '../../core/storage/records.dart';
import '../../ui/widgets.dart';
import '../sync/sync_controller.dart';
import '../sync/sync_section.dart';
import 'diagnostics_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final downloads = ref.watch(downloadsProvider).value ?? const <DownloadRecord>[];
    final used = downloads.where((d) => d.isDone).fold<int>(0, (a, d) => a + d.totalBytes);
    final tr = Strings.of(context);

    return CustomScrollView(slivers: [
      SliverAppBar(floating: true, title: Text(tr.settingsTitle, style: const TextStyle(fontWeight: FontWeight.w800))),
      SliverList.list(children: [
        _Header(tr.languageTitle),
        _Choice<String>(
          icon: Icons.language_rounded,
          title: tr.appLanguage,
          value: tr.code,
          options: Strings.languages,
          onChanged: (v) => n.set('language', v),
        ),
        _Header(tr.playback),
        _Choice<AudioType>(
          icon: Icons.record_voice_over_rounded,
          title: tr.defaultAudio,
          value: s.audio,
          options: {AudioType.sub: tr.subbed, AudioType.dub: tr.dubbed},
          onChanged: (v) => n.set('audio', v.name),
        ),
        _Choice<String>(
          icon: Icons.dns_rounded,
          title: tr.preferredServer,
          value: s.serverOrder.first,
          options: {for (final x in const ['HD-1', 'HD-2', 'Vidstream-1', 'Vidstream-2', 'Kiwi']) x: x},
          onChanged: (v) => n.set('serverOrder', [v, ...const ['HD-1', 'HD-2', 'Vidstream-1', 'Vidstream-2', 'Kiwi'].where((x) => x != v)]),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.skip_next_rounded),
          title: Text(tr.autoNextSetting),
          value: s.autoNext,
          onChanged: (v) => n.set('autoNext', v),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.fast_forward_rounded),
          title: Text(tr.skipIntroSetting),
          value: s.skipIntroButton,
          onChanged: (v) => n.set('skipIntroButton', v),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.translate_rounded),
          title: Text(tr.autoKoreanSetting),
          subtitle: Text(tr.autoKoreanHint),
          value: s.autoKoreanSubs,
          onChanged: (v) => n.set('autoKoreanSubs', v),
        ),
        _Choice<String>(
          icon: Icons.auto_awesome_rounded,
          title: tr.anime4kUpscaling,
          subtitle: tr.anime4kHint,
          value: s.anime4k,
          options: {for (final p in Anime4K.presets) p.$1: tr.anime4kMode(p.$1)},
          onChanged: (v) => n.set('anime4k', v),
        ),
        _Header(tr.subtitles),
        _Choice<String>(
          icon: Icons.closed_caption_rounded,
          title: tr.preferredLanguage,
          value: s.subtitleLanguage,
          options: tr.subtitleLanguages,
          onChanged: (v) => n.set('subtitleLanguage', v),
        ),
        ListTile(
          leading: const Icon(Icons.tune_rounded),
          title: Text(tr.styleAndTiming),
          subtitle: Text(tr.styleHint),
        ),
        _TextSetting(
          icon: Icons.key_rounded,
          title: tr.osKey,
          subtitle: tr.osKeyHint,
          value: s.openSubtitlesKey,
          obscure: true,
          onSaved: (v) => n.set('openSubtitlesKey', v),
        ),
        if (s.openSubtitlesKey.isNotEmpty) ...[
          _TextSetting(icon: Icons.person_outline_rounded, title: tr.osUser, value: s.openSubtitlesUser, onSaved: (v) => n.set('openSubtitlesUser', v)),
          _TextSetting(icon: Icons.password_rounded, title: tr.osPass, value: s.openSubtitlesPass, obscure: true, onSaved: (v) => n.set('openSubtitlesPass', v)),
        ],
        _Header(tr.downloads),
        _Choice<String>(
          icon: Icons.high_quality_rounded,
          title: tr.downloadQuality,
          value: s.quality,
          options: {'best': tr.bestAvailable, '1080': '1080p', '720': '720p', '480': '480p', '360': '360p'},
          onChanged: (v) => n.set('quality', v),
        ),
        _Choice<int>(
          icon: Icons.layers_rounded,
          title: tr.episodesAtOnce,
          value: s.maxConcurrent,
          options: const {1: '1', 2: '2', 3: '3', 4: '4'},
          onChanged: (v) => n.set('maxConcurrent', v),
        ),
        ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(tr.downloadLocation),
          subtitle: FutureBuilder<String>(
            future: ref.read(downloadManagerProvider).downloadRoot(),
            builder: (c, snap) => Text(snap.data ?? '…'),
          ),
          // iOS keeps downloads in the app's Documents folder (shown in Files).
          trailing: Platform.isIOS ? null : TextButton(
            child: Text(tr.change),
            onPressed: () async {
              final dir = await FilePicker.getDirectoryPath();
              if (dir != null) await n.set('downloadDir', dir);
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.storage_rounded),
          title: Text(tr.storageUsed),
          trailing: Text(formatBytes(used), style: const TextStyle(color: Colors.white70)),
        ),
        _Header(tr.syncHeader),
        const SyncSettingsSection(),
        _Header(tr.data),
        ListTile(
          leading: const Icon(Icons.history_rounded),
          title: Text(tr.clearHistory),
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(tr.clearHistoryQ),
                content: Text(tr.clearHistoryBody),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr.cancel)),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr.clear)),
                ],
              ),
            );
            if (ok == true) await ref.read(dbProvider).clearHistory();
          },
        ),
        _Header(tr.advanced),
        ExpansionTile(
          leading: const Icon(Icons.build_outlined),
          title: Text(tr.advanced),
          shape: const Border(),
          collapsedShape: const Border(),
          children: [
            SwitchListTile(
              title: Text(tr.useKiwi),
              value: s.enableKiwi,
              onChanged: (v) => n.set('enableKiwi', v),
            ),
            _TextSetting(icon: Icons.vpn_key_outlined, title: 'Megaplay AES key', subtitle: tr.megaplayKeyHint, value: s.megaplayAesKey, onSaved: (v) => n.set('megaplayAesKey', v)),
            _TextSetting(icon: Icons.vpn_key_outlined, title: 'Megaplay IV', value: s.megaplayIv, onSaved: (v) => n.set('megaplayIv', v)),
            _TextSetting(icon: Icons.vpn_key_outlined, title: 'Megaplay token key', value: s.megaplayTokenKey, onSaved: (v) => n.set('megaplayTokenKey', v)),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: Text(tr.sourceDiagnostics),
              subtitle: Text(tr.sourceDiagnosticsHint),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const DiagnosticsScreen())),
            ),
            if (ref.watch(syncProvider).signedIn)
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined),
                title: Text(tr.deleteSyncAccount),
                subtitle: Text(tr.deleteSyncAccountHint),
                onTap: () => _deleteSyncAccount(context, ref),
              ),
          ],
        ),
        _Header(tr.about),
        ListTile(
          leading: const Icon(Icons.info_outline_rounded),
          title: const Text('Oobleck'),
          subtitle: Text(tr.aboutLine(Platform.isWindows ? 'Windows' : Platform.isIOS ? 'iOS' : 'Android')),
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
      subtitle: Text(value.isEmpty ? (subtitle ?? Strings.of(context).notSet) : (obscure ? '••••••••' : value), maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () async {
        final c = TextEditingController(text: value);
        final r = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: TextField(controller: c, obscureText: obscure, autofocus: true),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Strings.of(context).cancel)),
              FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(Strings.of(context).save)),
            ],
          ),
        );
        if (r != null) onSaved(r);
      },
    );
  }
}

Future<void> _deleteSyncAccount(BuildContext context, WidgetRef ref) async {
  final tr = Strings.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr.deleteSyncAccountQ),
      content: Text(tr.deleteSyncAccountBody),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr.cancel)),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr.delete)),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await ref.read(syncProvider.notifier).signOut(deleteAccount: true);
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.syncError(e))));
  }
}
