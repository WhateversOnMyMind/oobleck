import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/strings.dart';
import '../../app/providers.dart';
import '../../core/sources/toon11/toon11_address.dart';
import '../../core/sources/toon11/toon11_source.dart';
import '../../ui/feedback.dart';
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
  bool _finding = false;

  Future<void> _findAddress(Strings tr) async {
    setState(() => _finding = true);
    final finder = ref.read(mangaSiteFinderProvider);
    final before = ref.read(mangaSiteAddressProvider);
    final found = await finder.recover(fromSettings: true);
    final works = found != null || await Toon11AddressFinder(ref.read(dioProvider)).works(before);
    if (!mounted) return;
    setState(() => _finding = false);
    showAppSnackBar(context, found != null ? tr.siteAddressFound(found) : works ? tr.siteAddressUnchanged : tr.siteAddressNotFound);
  }

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
    final address = ref.watch(mangaSiteAddressProvider);
    final found = ref.watch(mangaFoundUrlProvider);
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
        subtitle: Text([
          address + (base != null ? ' (${tr.siteAddressTyped})' : found != null ? ' (${tr.siteAddressAuto})' : ''),
          tr.mangaSiteAddressHint,
        ].join('\n')),
        isThreeLine: true,
        onTap: () => _editAddress(tr, base),
      ),
      ListTile(
        leading: _finding
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
            : const Icon(Icons.travel_explore_rounded),
        title: Text(tr.findSiteAddress),
        enabled: !_finding,
        onTap: () => _findAddress(tr),
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
    final ctl = TextEditingController(text: current ?? ref.read(mangaSiteAddressProvider));
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
    // Saving the address in use unchanged must not pin it as typed by hand.
    if (current == null && v == ref.read(mangaSiteAddressProvider)) return;
    await ref.read(mangaBaseUrlProvider.notifier).set(v == Toon11Source.defaultBaseUrl ? null : v);
  }
}
