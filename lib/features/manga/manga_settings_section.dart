import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/strings.dart';
import '../../core/sources/toon11/toon11_source.dart';
import '../../ui/widgets.dart';
import '../reader/reader_overlay.dart';
import 'manga_downloads_screen.dart';
import 'manga_providers.dart';
import 'manga_strings.dart';

/// Settings > Manga reader.
class MangaSettingsSection extends ConsumerStatefulWidget {
  const MangaSettingsSection({super.key});
  @override
  ConsumerState<MangaSettingsSection> createState() => _MangaSettingsSectionState();
}

class _MangaSettingsSectionState extends ConsumerState<MangaSettingsSection> {
  int? _cacheBytes;

  @override
  void initState() {
    super.initState();
    unawaited(_measure());
  }

  Future<void> _measure() async {
    final n = await ref.read(pageCacheProvider).sizeBytes();
    if (mounted) setState(() => _cacheBytes = n);
  }

  @override
  Widget build(BuildContext context) {
    final tr = Strings.of(context);
    final base = ref.watch(mangaBaseUrlProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(tr.mangaSettings),
      ListTile(
        leading: const Icon(Icons.chrome_reader_mode_outlined),
        title: Text(tr.readerSettings),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => showReaderSettings(context),
      ),
      ListTile(
        leading: const Icon(Icons.download_for_offline_outlined),
        title: Text(tr.mangaDownloads),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MangaDownloadsScreen())),
      ),
      ListTile(
        leading: const Icon(Icons.link_rounded),
        title: Text(tr.mangaSiteAddress),
        subtitle: Text('${base ?? Toon11Source.defaultBaseUrl}\n${tr.mangaSiteAddressHint}'),
        isThreeLine: true,
        onTap: () => _editAddress(tr, base),
      ),
      ListTile(
        leading: const Icon(Icons.image_outlined),
        title: Text(tr.pageCache),
        subtitle: Text(_cacheBytes == null ? '…' : tr.pageCacheSize(formatBytes(_cacheBytes!))),
        trailing: TextButton(
          onPressed: () async {
            await ref.read(pageCacheProvider).clear();
            await _measure();
          },
          child: Text(tr.clear),
        ),
      ),
    ]);
  }

  Future<void> _editAddress(Strings tr, String? current) async {
    final ctl = TextEditingController(text: current ?? Toon11Source.defaultBaseUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.mangaSiteAddress),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(hintText: Toon11Source.defaultBaseUrl, helperText: tr.mangaSiteAddressHint, helperMaxLines: 2),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, ''), child: Text(tr.reset)),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, ctl.text), child: Text(tr.save)),
        ],
      ),
    );
    ctl.dispose();
    if (result == null) return;
    final v = result.trim();
    await ref.read(mangaBaseUrlProvider.notifier).set(v == Toon11Source.defaultBaseUrl ? null : v);
  }
}
