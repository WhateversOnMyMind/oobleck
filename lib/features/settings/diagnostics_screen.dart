import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../core/log.dart';
import '../../core/models.dart';
import '../../core/sources/anikoto/anikoto_source.dart';
import '../../core/sources/extractors/megaplay_keys.dart';

/// Settings > Advanced > Source diagnostics. Runs the whole source chain for a
/// typed title and prints each step's raw result (the only place raw URLs and
/// IDs are shown).
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});
  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  final _title = TextEditingController(text: 'black clover');
  final List<String> _out = [];
  bool _running = false;
  String? _lastEmbed;

  void _add(String s) => setState(() => _out.add(s));

  Future<void> _run() async {
    final src = ref.read(sourceProvider);
    if (src is! AnikotoSource) return;
    setState(() {
      _out.clear();
      _running = true;
    });
    try {
      _add('1. search "${_title.text}"');
      final res = await src.search(_title.text);
      _add('   ${res.length} results: ${res.take(5).map((e) => '${e.title} (${e.slug})').join(' | ')}');
      if (res.isEmpty) return;
      _add('2. show page ${res.first.url}');
      final show = await src.showDetail(res.first.url);
      _add('   siteId=${show.siteId} malId=${show.malId} title=${show.title}');
      _add('3. episodes');
      final eps = await src.episodes(show);
      _add('   ${eps.length} episodes. first: num=${eps.first.number} key=${eps.first.serverKey} mal=${eps.first.malId} dub=${eps.first.hasDub}');
      _add('4. servers for episode ${eps.first.number}');
      final servers = await src.servers(eps.first);
      for (final s in servers) {
        _add('   ${s.type.name} ${s.name} linkId=${s.linkId}');
      }
      _add('5. resolving streams (sub)');
      for (final s in servers.where((x) => x.type == AudioType.sub)) {
        try {
          final embed = await src.embedUrl(s);
          _add('   ${s.name}: embed $embed');
          if (Uri.parse(embed).host.contains('megaplay')) _lastEmbed ??= embed;
          final st = await src.resolveServer(s);
          _add('   ${s.name}: stream ${st.url}');
          _add('   ${s.name}: ${st.subtitles.length} subtitle tracks: ${st.subtitles.map((t) => t.label).join(', ')}');
        } catch (e) {
          _add('   ${s.name}: FAILED $e');
        }
      }
      _add('Done.');
    } catch (e) {
      _add('ERROR: $e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _refreshKeys() async {
    final src = ref.read(sourceProvider);
    if (src is! AnikotoSource) return;
    _add('Refreshing Megaplay keys from the player script…');
    final ok = await src.keys.refresh(src.dio, embedUrl: _lastEmbed ?? MegaplayKeys.sampleEmbed);
    _add(ok ? 'Keys updated for this session.' : 'No change (kept current keys).');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(Strings.of(context).sourceDiagnostics)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(child: TextField(controller: _title, decoration: InputDecoration(labelText: Strings.of(context).title))),
            const SizedBox(width: 8),
            FilledButton(onPressed: _running ? null : _run, child: Text(Strings.of(context).run)),
            IconButton(tooltip: Strings.of(context).refreshKeys, onPressed: _refreshKeys, icon: const Icon(Icons.key_rounded)),
          ]),
        ),
        Expanded(
          child: SelectionArea(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final l in _out) Text(l, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.5)),
                const Divider(height: 32),
                Text(Strings.of(context).recentLog, style: const TextStyle(fontWeight: FontWeight.w700)),
                for (final l in Log.lines.reversed.take(60)) Text(l, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: Colors.white54)),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
