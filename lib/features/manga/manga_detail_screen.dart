import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../core/manga/manga_models.dart';
import '../../core/storage/app_db.dart';
import '../../core/storage/manga_records.dart';
import '../../ui/layout.dart';
import '../../ui/widgets.dart';
import '../reader/open_reader.dart';
import '../reader/reader_settings.dart';
import 'chapter_tile.dart';
import 'manga_logic.dart';
import 'manga_providers.dart';
import 'manga_strings.dart';
import 'manga_widgets.dart';

/// Series page: cover, info, Continue button and the chapter list.
class MangaDetailScreen extends ConsumerStatefulWidget {
  const MangaDetailScreen({super.key, required this.mangaKey});
  final String mangaKey;

  @override
  ConsumerState<MangaDetailScreen> createState() => _MangaDetailScreenState();
}

class _MangaDetailScreenState extends ConsumerState<MangaDetailScreen> {
  final _selected = <String>{};
  bool _descOpen = false;

  String get key => widget.mangaKey;
  bool get _selecting => _selected.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final tr = Strings.of(context);
    final refresh = ref.watch(mangaRefreshProvider(key));
    final m = ref.watch(mangaRecordProvider(key));
    final chapters = ref.watch(chaptersProvider(key));
    final states = ref.watch(chapterStatesProvider(key));
    final downloads = ref.watch(seriesDownloadsProvider(key));
    final source = ref.watch(mangaSourceProvider);

    if (m == null) {
      return Scaffold(
        appBar: AppBar(),
        body: refresh.hasError
            ? ErrorState(error: refresh.error!, onRetry: () => ref.invalidate(mangaRefreshProvider(key)))
            : const Center(child: Skeleton(width: 200, height: 24)),
      );
    }

    final doneIds = {
      for (final d in downloads.values)
        if (d.isDone) d.chapterId,
    };
    final visible = visibleChapters(chapters, states, doneIds, newestFirst: m.chapterSortDesc, filter: m.chapterFilter);
    final next = nextToRead(chapters, states);
    final offline = refresh.error is OfflineCopy;
    final loadingChapters = chapters.isEmpty && refresh.isLoading;

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: () => ref.refresh(mangaRefreshProvider(key).future).then((_) {}, onError: (_) {}),
          child: CustomScrollView(
            slivers: [
              _selecting ? _selectionBar(tr, chapters) : _appBar(tr, m, source.imageHeaders),
              SliverToBoxAdapter(child: _header(tr, m, chapters.length, source.imageHeaders)),
              if (offline)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.cloud_off_rounded, size: 18, color: Colors.white54),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(tr.showingSaved, style: const TextStyle(color: Colors.white54)),
                        ),
                      ],
                    ),
                  ),
                ),
              if (refresh.hasError && !offline && chapters.isEmpty)
                SliverToBoxAdapter(
                  child: ErrorState(error: refresh.error!, onRetry: () => ref.invalidate(mangaRefreshProvider(key))),
                ),
              // A readable width on a wide desktop window, like the anime show page.
              SliverMaxWidth(
                maxWidth: 900,
                sliver: SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(child: _chapterHeader(tr, m, chapters.length)),
                    if (loadingChapters)
                      SliverList.builder(
                        itemCount: 8,
                        itemBuilder: (_, _) => const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Skeleton(height: 44)),
                      )
                    else
                      SliverList.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, i) {
                          final c = visible[i];
                          return ChapterTile(
                            chapter: c,
                            state: states[c.id],
                            download: downloads[c.id],
                            selected: _selected.contains(c.id),
                            selecting: _selecting,
                            onTap: () => _selecting ? _toggle(c.id) : openReader(context, mangaKey: key, chapterId: c.id),
                            onLongPress: () {
                              HapticFeedback.selectionClick();
                              _toggle(c.id);
                            },
                            onDownload: () => _downloadTap(tr, m, c, downloads[c.id]),
                          );
                        },
                      ),
                  ],
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 96)),
            ],
          ),
        ),
        floatingActionButton: _selecting || chapters.isEmpty
            ? null
            : FloatingActionButton.extended(
                onPressed: () {
                  // Everything read: reopen the newest chapter (the label says so).
                  final target = next ?? chapters.last;
                  openReader(context, mangaKey: key, chapterId: target.id);
                },
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(_continueLabel(tr, next, states, chapters)),
              ),
        bottomNavigationBar: _selecting ? _selectionActions(tr, m, chapters, states, downloads) : null,
      ),
    );
  }

  String _continueLabel(Strings tr, ChapterRecord? next, Map<String, ChapterState> states, List<ChapterRecord> chapters) {
    if (next == null) return tr.readChapter(chapters.last.title);
    final anyRead = states.values.any((s) => s.read || s.readAt != null);
    if (!anyRead) return tr.startReading;
    return tr.continueChapter(next.title);
  }

  void _toggle(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  // ---- header --------------------------------------------------------------------------
  Widget _appBar(Strings tr, MangaRecord m, Map<String, String> headers) {
    return SliverAppBar(
      pinned: true,
      title: Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: m.inLibrary ? tr.removeFromLibrary : tr.addToLibrary,
          onPressed: () => _toggleLibrary(tr, m),
          icon: Icon(m.inLibrary ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: m.inLibrary ? Theme.of(context).colorScheme.primary : null),
        ),
        PopupMenuButton<String>(
          tooltip: tr.download,
          icon: const Icon(Icons.download_rounded),
          onSelected: (v) => _bulkDownload(tr, m, v),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'next5', child: Text(tr.downloadNext5)),
            PopupMenuItem(value: 'unread', child: Text(tr.downloadUnread)),
            PopupMenuItem(value: 'all', child: Text(tr.downloadAll)),
          ],
        ),
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'browser') {
              await launchUrl(Uri.parse(ref.read(mangaSourceProvider).mangaUrl(m.mangaId)), mode: LaunchMode.externalApplication);
            } else if (v == 'mode') {
              await _pickSeriesMode(tr, m);
            } else if (v == 'categories' && mounted) {
              await editSeriesCategories(context, ref, [m.key]);
            } else if (v == 'refresh') {
              ref.invalidate(mangaRefreshProvider(key));
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'mode', child: Text(tr.readerModeForSeries)),
            if (m.inLibrary) PopupMenuItem(value: 'categories', child: Text(tr.setCategories)),
            PopupMenuItem(value: 'browser', child: Text(tr.openInBrowser)),
            PopupMenuItem(value: 'refresh', child: Text(tr.retry)),
          ],
        ),
      ],
    );
  }

  Widget _header(Strings tr, MangaRecord m, int chapterCount, Map<String, String> headers) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final info = [
      if (m.author.isNotEmpty) m.author,
      if (m.status != MangaStatus.unknown) tr.status(m.status),
      if (m.schedule.isNotEmpty && m.schedule != tr.status(m.status)) m.schedule,
    ];
    return Stack(
      children: [
        // Soft blurred cover behind the header.
        Positioned.fill(
          child: ShaderMask(
            shaderCallback: (r) =>
                const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x88000000), Colors.transparent]).createShader(r),
            blendMode: BlendMode.dstIn,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: MangaCover(url: m.cover, localPath: m.coverPath, headers: headers),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 112,
                    child: AspectRatio(
                      aspectRatio: 0.7,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: MangaCover(url: m.cover, localPath: m.coverPath, headers: headers),
                      ),
                    ),
                  ),
                  const SizedBox(width: Gap.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(m.title, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.2)),
                        const SizedBox(height: 6),
                        if (info.isNotEmpty) Text(info.join(' · '), style: t.bodyMedium?.copyWith(color: Colors.white70)),
                        if (chapterCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(tr.chapterCount(chapterCount), style: t.bodySmall?.copyWith(color: Colors.white54)),
                          ),
                        const SizedBox(height: 10),
                        FilledButton.tonalIcon(
                          onPressed: () => _toggleLibrary(tr, m),
                          icon: Icon(m.inLibrary ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: m.inLibrary ? scheme.primary : null),
                          label: Text(m.inLibrary ? tr.inLibrary : tr.addToLibrary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (m.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => setState(() => _descOpen = !_descOpen),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.topCenter,
                    child: Text(
                      m.description,
                      maxLines: _descOpen ? null : 3,
                      overflow: _descOpen ? null : TextOverflow.ellipsis,
                      style: t.bodyMedium?.copyWith(color: Colors.white70, height: 1.45),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => setState(() => _descOpen = !_descOpen), child: Text(_descOpen ? tr.less : tr.more)),
                ),
              ],
              if (m.genres.isNotEmpty)
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final g in m.genres)
                      Chip(label: Text(g), visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _chapterHeader(Strings tr, MangaRecord m, int count) {
    final db = ref.read(dbProvider);
    final filterLabel = switch (m.chapterFilter) {
      'unread' => tr.chaptersFilterUnread,
      'downloaded' => tr.chaptersFilterDownloaded,
      'bookmarked' => tr.chaptersFilterBookmarked,
      _ => tr.chaptersFilterAll,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(tr.chapterCount(count), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          PopupMenuButton<String>(
            tooltip: tr.filter,
            onSelected: (v) => db.putManga(m.copyWith(chapterFilter: v)),
            itemBuilder: (_) => [
              for (final (v, l) in [
                ('all', tr.chaptersFilterAll),
                ('unread', tr.chaptersFilterUnread),
                ('downloaded', tr.chaptersFilterDownloaded),
                ('bookmarked', tr.chaptersFilterBookmarked),
              ])
                CheckedPopupMenuItem(value: v, checked: m.chapterFilter == v, child: Text(l)),
            ],
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Icon(Icons.filter_list_rounded, size: 20, color: m.chapterFilter == 'all' ? Colors.white70 : Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(filterLabel),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: m.chapterSortDesc ? tr.newestFirst : tr.oldestFirst,
            onPressed: () => db.putManga(m.copyWith(chapterSortDesc: !m.chapterSortDesc)),
            icon: Icon(m.chapterSortDesc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }

  // ---- selection ------------------------------------------------------------------------
  Widget _selectionBar(Strings tr, List<ChapterRecord> chapters) => SliverAppBar(
    pinned: true,
    leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(_selected.clear)),
    title: Text(tr.selectedCount(_selected.length)),
    actions: [
      IconButton(
        tooltip: tr.selectAll,
        icon: const Icon(Icons.select_all_rounded),
        onPressed: () => setState(() => _selected.addAll(chapters.map((c) => c.id))),
      ),
    ],
  );

  Widget _selectionActions(
    Strings tr,
    MangaRecord m,
    List<ChapterRecord> chapters,
    Map<String, ChapterState> states,
    Map<String, MangaDownloadRecord> downloads,
  ) {
    final db = ref.read(dbProvider);
    final ids = _selected.toList();
    final allRead = ids.every((id) => states[id]?.read ?? false);
    final allBookmarked = ids.every((id) => states[id]?.bookmarked ?? false);
    final anyDownloaded = ids.any((id) => downloads[id] != null);
    void done() {
      if (mounted) setState(_selected.clear);
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _Action(
              icon: allRead ? Icons.remove_done_rounded : Icons.done_all_rounded,
              label: allRead ? tr.markUnread : tr.markRead,
              onTap: () async {
                await db.setRead(key, ids, !allRead);
                done();
              },
            ),
            _Action(
              icon: allBookmarked ? Icons.bookmark_remove_rounded : Icons.bookmark_add_rounded,
              label: allBookmarked ? tr.removeBookmark : tr.bookmark,
              onTap: () async {
                await db.setBookmarked(key, ids, !allBookmarked);
                done();
              },
            ),
            if (ids.length == 1)
              _Action(
                icon: Icons.vertical_align_bottom_rounded,
                label: tr.markPreviousRead,
                onTap: () async {
                  await db.setRead(key, previousChapterIds(chapters, ids.single), true);
                  done();
                },
              ),
            _Action(
              icon: anyDownloaded ? Icons.delete_outline_rounded : Icons.download_rounded,
              label: anyDownloaded ? tr.deleteDownload : tr.download,
              onTap: () async {
                final dl = ref.read(mangaDownloaderProvider);
                if (anyDownloaded) {
                  for (final id in ids) {
                    await dl.delete(ChapterState.keyOf(key, id));
                  }
                } else {
                  final picked = chapters.where((c) => ids.contains(c.id)).map((c) => c.toInfo(m.mangaId)).toList();
                  await dl.enqueue(m, picked);
                }
                done();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---- actions ----------------------------------------------------------------------------
  Future<void> _toggleLibrary(Strings tr, MangaRecord m) async {
    final db = ref.read(dbProvider);
    final adding = !m.inLibrary;
    await db.setInLibrary(m.key, adding);
    if (!mounted) return;
    unawaited(HapticFeedback.lightImpact());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(adding ? tr.addedToLibrary(m.title) : tr.removedFromLibrary(m.title)),
          action: SnackBarAction(label: tr.undo, onPressed: () => db.setInLibrary(m.key, !adding)),
        ),
      );
  }

  Future<void> _downloadTap(Strings tr, MangaRecord m, ChapterRecord c, MangaDownloadRecord? d) async {
    final dl = ref.read(mangaDownloaderProvider);
    final k = ChapterState.keyOf(key, c.id);
    if (d == null || d.status == MangaDownloadStatus.failed) {
      await dl.enqueue(m, [c.toInfo(m.mangaId)]);
    } else if (d.status == MangaDownloadStatus.running) {
      await dl.pause(k);
    } else if (d.status == MangaDownloadStatus.paused) {
      await dl.resume(k);
    } else {
      await dl.delete(k);
    }
  }

  Future<void> _bulkDownload(Strings tr, MangaRecord m, String which) async {
    final chapters = ref.read(chaptersProvider(key));
    final states = ref.read(chapterStatesProvider(key));
    final unread = chapters.where((c) => !(states[c.id]?.read ?? false));
    final picked = switch (which) {
      'next5' => unread.take(5),
      'unread' => unread,
      _ => chapters,
    }.map((c) => c.toInfo(m.mangaId)).toList();
    final n = await ref.read(mangaDownloaderProvider).enqueue(m, picked);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.downloadQueued(n))));
  }

  Future<void> _pickSeriesMode(Strings tr, MangaRecord m) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: RadioGroup<String>(
          groupValue: m.readerMode ?? '',
          onChanged: (v) => Navigator.pop(context, v),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(title: Text(tr.readerModeForSeries, style: Theme.of(context).textTheme.titleMedium)),
              RadioListTile<String>(value: '', title: Text(tr.useDefault)),
              for (final mode in ReaderMode.values)
                RadioListTile<String>(value: mode.name, secondary: Icon(mode.icon), title: Text(tr.readerModeLabel(mode.name))),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    await ref.read(dbProvider).putManga(m.copyWith(readerMode: picked.isEmpty ? null : picked));
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    ),
  );
}

/// Opens a series by key.
Future<void> openMangaDetail(BuildContext context, String mangaKey) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MangaDetailScreen(mangaKey: mangaKey)));

/// Lets the user tick categories for [keys] (creating new ones on the way).
Future<void> editSeriesCategories(BuildContext context, WidgetRef ref, List<String> keys) async {
  final db = ref.read(dbProvider);
  final tr = Strings.of(context);
  final all = db.mangaCategories();
  final current = {for (final k in keys) ...?db.manga(k)?.categories};
  final picked = await showDialog<Set<String>>(
    context: context,
    builder: (context) => _CategoryDialog(all: all, initial: current, tr: tr),
  );
  if (picked == null) return;
  final names = {...all, ...picked}.toList();
  await db.setMangaCategories(names);
  for (final k in keys) {
    final m = db.manga(k);
    if (m != null) await db.putManga(m.copyWith(categories: picked.toList()));
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({required this.all, required this.initial, required this.tr});
  final List<String> all;
  final Set<String> initial;
  final Strings tr;
  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final Set<String> _picked = {...widget.initial};
  late final List<String> _all = [...widget.all];
  final _new = TextEditingController();

  @override
  void dispose() {
    _new.dispose();
    super.dispose();
  }

  void _add() {
    final name = _new.text.trim();
    if (name.isEmpty) return;
    setState(() {
      if (!_all.contains(name)) _all.add(name);
      _picked.add(name);
      _new.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.tr;
    return AlertDialog(
      title: Text(tr.setCategories),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in _all)
                    CheckboxListTile(
                      value: _picked.contains(c),
                      onChanged: (v) => setState(() => v == true ? _picked.add(c) : _picked.remove(c)),
                      title: Text(c),
                    ),
                ],
              ),
            ),
            TextField(
              controller: _new,
              decoration: InputDecoration(
                hintText: tr.newCategory,
                suffixIcon: IconButton(icon: const Icon(Icons.add_rounded), onPressed: _add),
              ),
              onSubmitted: (_) => _add(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr.cancel)),
        FilledButton(onPressed: () => Navigator.pop(context, _picked), child: Text(tr.save)),
      ],
    );
  }
}
