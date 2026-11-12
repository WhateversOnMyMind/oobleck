import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/log.dart';
import '../../core/subtitles/anime_titles.dart';
import '../../core/subtitles/anissia.dart';
import '../../core/subtitles/opensubtitles.dart';
import '../../core/subtitles/subtitle_import.dart';
import '../player/player_session.dart';

/// "Find Korean subs": match the show on Anissia once, list release posts for
/// the episode, import with one tap. OpenSubtitles is offered when a key is set.
void showKoreanSubtitleSheet({
  required BuildContext context,
  required WidgetRef ref,
  required PlayerSession session,
  required Future<void> Function(String path, String label) onLoaded,
}) {
  unawaited(showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => _KoreanSheet(session: session, scroll: scroll, onLoaded: onLoaded),
    ),
  ));
}

class _KoreanSheet extends ConsumerStatefulWidget {
  const _KoreanSheet({required this.session, required this.scroll, required this.onLoaded});
  final PlayerSession session;
  final ScrollController scroll;
  final Future<void> Function(String path, String label) onLoaded;

  @override
  ConsumerState<_KoreanSheet> createState() => _KoreanSheetState();
}

class _KoreanSheetState extends ConsumerState<_KoreanSheet> {
  late final AnissiaClient _anissia = AnissiaClient(ref.read(dioProvider));
  final _query = TextEditingController();
  List<AnissiaAnime>? _matches;
  AnissiaAnime? _chosen;
  List<AnissiaCaption>? _captions;
  List<OpenSubtitlesResult>? _osResults;
  bool _busy = false;
  bool _showAll = false;
  String? _error;

  String get slug => widget.session.request.slug;
  String get episode => widget.session.request.episode;

  @override
  void initState() {
    super.initState();
    _query.text = widget.session.request.showTitle;
    final saved = ref.read(dbProvider).misc<Map>('anissia:$slug');
    if (saved != null) {
      _chosen = AnissiaAnime(animeNo: saved['animeNo'] as int, subject: saved['subject'] as String, originalSubject: '');
      unawaited(_loadCaptions());
    } else {
      unawaited(_autoSearch());
    }
  }

  /// First search: Anissia barely matches English titles, so look up the
  /// Japanese title (and any Korean synonym) by MAL id and try those, then
  /// show the best match's Korean title in the search box.
  Future<void> _autoSearch() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final mal = widget.session.malId;
      var titles = const AnimeTitles();
      if (mal != null) {
        try {
          titles = await AnimeTitles.forMal(ref.read(dioProvider), mal);
        } catch (e) {
          Log.d('subs', 'AniList title lookup failed: $e');
        }
      }
      for (final q in anissiaQueries(titles, fallback: _query.text)) {
        List<AnissiaAnime> r;
        try {
          r = await _anissia.search(q);
        } catch (e) {
          Log.d('subs', 'Anissia search "$q" failed: $e');
          continue;
        }
        if (r.isEmpty) continue;
        r = rankMatches(r, subject: (a) => a.subject, original: (a) => a.originalSubject, native: titles.native);
        if (!mounted) return;
        setState(() {
          _matches = r;
          _query.text = r.first.subject;
        });
        return;
      }
      if (mounted) setState(() => _matches = const []);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't reach Anissia. Check your connection.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await _anissia.search(_query.text.trim());
      if (mounted) setState(() => _matches = r);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't reach Anissia. Check your connection.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose(AnissiaAnime a) async {
    _chosen = a;
    await ref.read(dbProvider).setMisc('anissia:$slug', {'animeNo': a.animeNo, 'subject': a.subject});
    await _loadCaptions();
  }

  Future<void> _loadCaptions() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final c = await _anissia.captions(_chosen!.animeNo);
      if (mounted) setState(() => _captions = c);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't load subtitle posts.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeMatch() async {
    await ref.read(dbProvider).setMisc('anissia:$slug', null);
    setState(() {
      _chosen = null;
      _captions = null;
    });
    await _search();
  }

  Future<void> _import(AnissiaCaption c) async {
    if (c.website.isEmpty) return;
    setState(() => _busy = true);
    final dio = ref.read(dioProvider);
    try {
      final attachments = await findAttachments(dio, c.website);
      if (attachments.isEmpty) {
        if (mounted) await _browserFallback(c.website);
        return;
      }
      SubAttachment pick = attachments.first;
      if (attachments.length > 1) {
        final chosen = await _pickOne<SubAttachment>('Choose a file', attachments, (a) => a.name);
        if (chosen == null) return;
        pick = chosen;
      }
      final files = await fetchSubtitleFiles(dio, pick);
      if (files.isEmpty) {
        if (mounted) await _browserFallback(c.website);
        return;
      }
      var name = pickForEpisode(files.keys.toList(), int.tryParse(episode) ?? -1);
      if (name == null) {
        name = await _pickOne<String>('Which file is episode $episode?', files.keys.toList(), (n) => p.basename(n));
        if (name == null) return;
      }
      final prepared = prepareSubtitle(files[name]!, name);
      final path = await saveSubtitle(prepared, ref.read(supportDirProvider), slug, episode);
      await widget.onLoaded(path, 'Korean · ${c.name.isEmpty ? 'Anissia' : c.name}');
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) await _browserFallback(c.website);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _browserFallback(String url) async {
    final act = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Can't import this automatically"),
        content: const Text('Open the post in your browser, download the subtitle file, then import it from your files.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'browser'), child: const Text('Open post')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'file'), child: const Text('Import from file…')),
        ],
      ),
    );
    if (act == 'browser') {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } else if (act == 'file') {
      final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['smi', 'srt', 'ass', 'ssa', 'vtt', 'zip']);
      final path = r.firstOrNull?.path;
      if (path == null) return;
      final files = path.toLowerCase().endsWith('.zip')
          ? unzipSubtitles(await _read(path))
          : {p.basename(path): await _read(path)};
      if (files.isEmpty) return;
      final name = files.length == 1 ? files.keys.first : await _pickOne<String>('Which file?', files.keys.toList(), p.basename);
      if (name == null) return;
      final prepared = prepareSubtitle(files[name]!, name);
      final out = await saveSubtitle(prepared, ref.read(supportDirProvider), slug, episode);
      await widget.onLoaded(out, 'Korean · imported');
      if (mounted) Navigator.pop(context);
    }
  }

  Future<List<int>> _read(String path) => File(path).readAsBytes();

  Future<T?> _pickOne<T>(String title, List<T> items, String Function(T) label) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [for (final i in items) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, i), child: Text(label(i)))],
      ),
    );
  }

  Future<void> _searchOpenSubtitles() async {
    final st = ref.read(settingsProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final os = OpenSubtitlesClient(ref.read(dioProvider), apiKey: st.openSubtitlesKey, username: st.openSubtitlesUser, password: st.openSubtitlesPass);
      final r = await os.search(widget.session.request.showTitle, int.tryParse(episode) ?? 1);
      if (mounted) setState(() => _osResults = r);
    } catch (_) {
      if (mounted) setState(() => _error = "OpenSubtitles didn't respond. Check your API key in Settings.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importOs(OpenSubtitlesResult r) async {
    final st = ref.read(settingsProvider);
    setState(() => _busy = true);
    try {
      final os = OpenSubtitlesClient(ref.read(dioProvider), apiKey: st.openSubtitlesKey, username: st.openSubtitlesUser, password: st.openSubtitlesPass);
      final (name, bytes) = await os.download(r);
      final prepared = prepareSubtitle(bytes, name.contains('.') ? name : '$name.srt');
      final path = await saveSubtitle(prepared, ref.read(supportDirProvider), slug, episode);
      await widget.onLoaded(path, 'Korean · OpenSubtitles');
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = "Couldn't download that file. OpenSubtitles may need your account login in Settings.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hasOs = ref.watch(settingsProvider.select((s) => s.openSubtitlesKey.isNotEmpty));
    final epNum = double.tryParse(episode);
    final caps = _captions == null
        ? const <AnissiaCaption>[]
        : (_showAll ? _captions! : _captions!.where((c) => c.number == epNum).toList());

    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
      Text('Find Korean subtitles', style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text('Episode $episode · fansub posts from Anissia', style: t.bodySmall?.copyWith(color: Colors.white60)),
      if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator(minHeight: 2)),
      if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
      const SizedBox(height: Gap.m),
      if (_chosen == null) ...[
        Row(children: [
          Expanded(
            child: TextField(
              controller: _query,
              onSubmitted: (_) => _search(),
              decoration: const InputDecoration(hintText: 'Title (Korean or Japanese works best)'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(onPressed: _search, icon: const Icon(Icons.search_rounded)),
        ]),
        const SizedBox(height: Gap.s),
        if (_matches != null && _matches!.isEmpty)
          const Padding(padding: EdgeInsets.all(12), child: Text('No match. Try the Japanese or Korean title.', style: TextStyle(color: Colors.white60))),
        for (final a in _matches ?? const <AnissiaAnime>[])
          ListTile(
            title: Text(a.subject),
            subtitle: Text([
              if (a.originalSubject.isNotEmpty) a.originalSubject,
              a.captionCount == 1 ? '1 subtitle post' : '${a.captionCount} subtitle posts',
            ].join(' · ')),
            onTap: () => _choose(a),
          ),
        if (_matches != null && _matches!.isNotEmpty)
          const Padding(padding: EdgeInsets.all(8), child: Text("Pick the right show once. We'll remember it.", style: TextStyle(color: Colors.white54, fontSize: 12))),
      ] else ...[
        Row(children: [
          Expanded(child: Text(_chosen!.subject, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
          TextButton(onPressed: _changeMatch, child: const Text('Change')),
        ]),
        SwitchListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Show all episodes'), value: _showAll, onChanged: (v) => setState(() => _showAll = v)),
        if (_captions != null && caps.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No Korean fansub post for this episode yet. Subtitles are often released a few hours after broadcast.', style: TextStyle(color: Colors.white60)),
          ),
        for (final c in caps)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(backgroundColor: kAccent.withValues(alpha: 0.2), child: Text(c.episode, style: const TextStyle(fontWeight: FontWeight.w700))),
              title: Text(c.name.isEmpty ? 'Unknown fansubber' : c.name),
              subtitle: Text(c.updated.length >= 10 ? c.updated.substring(0, 10) : c.updated),
              trailing: const Icon(Icons.download_rounded),
              onTap: _busy ? null : () => _import(c),
            ),
          ),
      ],
      const Divider(height: 32),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.upload_file_rounded),
        title: const Text('Import from file…'),
        subtitle: const Text('.smi, .srt, .ass, .vtt or a .zip'),
        onTap: () => _browserFallbackFile(),
      ),
      if (hasOs) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.subtitles_outlined),
          title: const Text('Search OpenSubtitles'),
          onTap: _busy ? null : _searchOpenSubtitles,
        ),
        for (final r in _osResults ?? const <OpenSubtitlesResult>[])
          ListTile(title: Text(r.release.isEmpty ? r.fileName : r.release, maxLines: 2, overflow: TextOverflow.ellipsis), subtitle: Text('${r.downloads} downloads'), onTap: () => _importOs(r)),
      ] else
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text('Add a free OpenSubtitles API key in Settings to search there too.', style: TextStyle(color: Colors.white54, fontSize: 12)),
        ),
    ]);
  }

  Future<void> _browserFallbackFile() async {
    final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['smi', 'srt', 'ass', 'ssa', 'vtt', 'zip']);
    final path = r.firstOrNull?.path;
    if (path == null) return;
    final bytes = await _read(path);
    final files = path.toLowerCase().endsWith('.zip') ? unzipSubtitles(bytes) : {p.basename(path): bytes};
    if (files.isEmpty || !mounted) return;
    final name = files.length == 1 ? files.keys.first : await _pickOne<String>('Which file is episode $episode?', files.keys.toList(), p.basename);
    if (name == null) return;
    final out = await saveSubtitle(prepareSubtitle(files[name]!, name), ref.read(supportDirProvider), slug, episode);
    await widget.onLoaded(out, 'Korean · imported');
    if (mounted) Navigator.pop(context);
  }
}
