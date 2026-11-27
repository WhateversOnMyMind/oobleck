import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../core/storage/app_db.dart';
import '../../ui/widgets.dart';
import '../../ui/feedback.dart';
import '../reader/open_reader.dart';
import 'manga_detail_screen.dart';
import 'manga_logic.dart';
import 'manga_providers.dart';
import 'manga_strings.dart';
import 'manga_widgets.dart';

/// How the library grid looks; kept in the settings box.
class LibraryPrefs {
  const LibraryPrefs({
    this.sort = LibrarySort.lastRead,
    this.descending = true,
    this.display = 'grid',
    this.filter = const LibraryFilter(),
    this.unreadBadge = true,
    this.continueButton = true,
  });
  final LibrarySort sort;
  final bool descending;

  /// grid | compact | list
  final String display;
  final LibraryFilter filter;
  final bool unreadBadge;
  final bool continueButton;

  static LibraryPrefs load(AppDb db) {
    T g<T>(String k, T d) => db.setting<T>('manga.lib.$k') ?? d;
    return LibraryPrefs(
      sort: LibrarySort.parse(db.setting<String>('manga.lib.sort')),
      descending: g('desc', true),
      display: g('display', 'grid'),
      filter: LibraryFilter(
        unread: g('fUnread', false),
        started: g('fStarted', false),
        downloaded: g('fDownloaded', false),
        completed: g('fCompleted', false),
      ),
      unreadBadge: g('unreadBadge', true),
      continueButton: g('continueButton', true),
    );
  }
}

class LibraryPrefsNotifier extends Notifier<LibraryPrefs> {
  @override
  LibraryPrefs build() => LibraryPrefs.load(ref.watch(dbProvider));

  Future<void> set(String key, Object value) async {
    final db = ref.read(dbProvider);
    await db.setSetting('manga.lib.$key', value is Enum ? value.name : value);
    state = LibraryPrefs.load(db);
  }
}

final libraryPrefsProvider = NotifierProvider<LibraryPrefsNotifier, LibraryPrefs>(LibraryPrefsNotifier.new);

class LibraryView extends ConsumerStatefulWidget {
  const LibraryView({super.key, required this.onBrowse});
  final VoidCallback onBrowse;

  @override
  ConsumerState<LibraryView> createState() => LibraryViewState();
}

class LibraryViewState extends ConsumerState<LibraryView> {
  final _selected = <String>{};
  String _query = '';
  bool _searching = false;
  String? _category;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get selecting => _selected.isNotEmpty;

  void toggleSearch() => setState(() {
        _searching = !_searching;
        if (!_searching) {
          _query = '';
          _search.clear();
        }
      });

  Future<void> refreshAll() async {
    final tr = Strings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final found = await ref.read(libraryRefresherProvider.notifier).refreshAll();
    messenger.showSnackBar(SnackBar(content: Text(tr.newChaptersFound(found))));
  }

  @override
  Widget build(BuildContext context) {
    final tr = Strings.of(context);
    final prefs = ref.watch(libraryPrefsProvider);
    final all = ref.watch(libraryEntriesProvider);
    final refresh = ref.watch(libraryRefresherProvider);
    final categories = ref.read(dbProvider).mangaCategories();
    if (_category != null && !categories.contains(_category)) _category = null;
    final entries = arrangeLibrary(all,
        sort: prefs.sort, descending: prefs.descending, filter: prefs.filter, category: _category, query: _query);
    final headers = ref.watch(mangaSourceProvider).imageHeaders;

    Widget content;
    if (all.isEmpty) {
      content = ListView(children: [
        const SizedBox(height: 60),
        EmptyState(
          icon: Icons.collections_bookmark_outlined,
          title: tr.libraryEmpty,
          message: tr.libraryEmptyHint,
          actionLabel: tr.goBrowse,
          onAction: widget.onBrowse,
        ),
      ]);
    } else if (entries.isEmpty) {
      content = ListView(children: [
        const SizedBox(height: 60),
        EmptyState(icon: Icons.filter_alt_off_outlined, title: tr.noResults),
      ]);
    } else if (prefs.display == 'list') {
      content = ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: entries.length,
        itemBuilder: (context, i) => _listTile(tr, entries[i], headers, prefs),
      );
    } else {
      content = LayoutBuilder(
        builder: (context, box) => GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          gridDelegate: coverGridDelegate(box.maxWidth, compact: prefs.display == 'compact'),
          itemCount: entries.length,
          itemBuilder: (context, i) => _card(tr, entries[i], headers, prefs),
        ),
      );
    }

    return Column(children: [
      if (selecting) _selectionBar(tr, entries),
      if (_searching)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _search,
            autofocus: true,
            decoration: InputDecoration(
              hintText: tr.searchLibrary,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(icon: const Icon(Icons.close_rounded), onPressed: toggleSearch),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
      if (categories.isNotEmpty)
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final c in [null, ...categories])
              Padding(
                padding: const EdgeInsets.only(right: 6, top: 6, bottom: 6),
                child: ChoiceChip(
                  label: Text(c ?? tr.allCategory),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
              ),
          ]),
        ),
      if (refresh.running)
        LinearProgressIndicator(value: refresh.total == 0 ? null : refresh.done / refresh.total, minHeight: 2),
      Expanded(child: RefreshIndicator(onRefresh: refreshAll, child: content)),
    ]);
  }

  List<(String, Color)> _badges(LibraryEntry e, LibraryPrefs prefs) => [
        if (prefs.unreadBadge && e.unread > 0) ('${e.unread}', Theme.of(context).colorScheme.primary),
        if (e.downloaded > 0) ('${e.downloaded}', const Color(0xFF2E7D5B)),
      ];

  void _open(LibraryEntry e) {
    if (selecting) return _toggle(e.manga.key);
    unawaited(openMangaDetail(context, e.manga.key));
  }

  void _toggle(String key) => setState(() => _selected.contains(key) ? _selected.remove(key) : _selected.add(key));

  Widget _card(Strings tr, LibraryEntry e, Map<String, String> headers, LibraryPrefs prefs) => MangaCard(
        title: e.manga.title,
        cover: e.manga.cover,
        coverPath: e.manga.coverPath,
        headers: headers,
        compact: prefs.display == 'compact',
        subtitle: e.unread > 0 ? tr.unreadCount(e.unread) : tr.chapterCount(e.total),
        badges: _badges(e, prefs),
        selected: _selected.contains(e.manga.key),
        onTap: () => _open(e),
        onLongPress: () {
          hapticTick();
          _toggle(e.manga.key);
        },
        onContinue: prefs.continueButton && e.next != null && !selecting
            ? () => openReader(context, mangaKey: e.manga.key, chapterId: e.next!.id)
            : null,
      );

  Widget _listTile(Strings tr, LibraryEntry e, Map<String, String> headers, LibraryPrefs prefs) {
    final selected = _selected.contains(e.manga.key);
    return ListTile(
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
      leading: MangaThumb(e.manga, headers: headers),
      title: Text(e.manga.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(e.unread > 0 ? tr.unreadCount(e.unread) : tr.chapterCount(e.total)),
      trailing: e.next != null && prefs.continueButton && !selecting
          ? IconButton(
              tooltip: tr.resume,
              icon: const Icon(Icons.play_circle_fill_rounded),
              onPressed: () => openReader(context, mangaKey: e.manga.key, chapterId: e.next!.id),
            )
          : null,
      onTap: () => _open(e),
      onLongPress: () => _toggle(e.manga.key),
    );
  }

  Widget _selectionBar(Strings tr, List<LibraryEntry> visible) {
    final db = ref.read(dbProvider);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Row(children: [
        IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(_selected.clear)),
        Expanded(child: Text(tr.selectedCount(_selected.length))),
        IconButton(
          tooltip: tr.selectAll,
          icon: const Icon(Icons.select_all_rounded),
          onPressed: () => setState(() => _selected.addAll(visible.map((e) => e.manga.key))),
        ),
        IconButton(
          tooltip: tr.setCategories,
          icon: const Icon(Icons.label_outline_rounded),
          onPressed: () async {
            await editSeriesCategories(context, ref, _selected.toList());
            if (mounted) setState(_selected.clear);
          },
        ),
        IconButton(
          tooltip: tr.markRead,
          icon: const Icon(Icons.done_all_rounded),
          onPressed: () async {
            for (final k in _selected.toList()) {
              await db.setRead(k, db.chapters(k).map((c) => c.id), true);
            }
            if (mounted) setState(_selected.clear);
          },
        ),
        IconButton(
          tooltip: tr.removeFromLibrary,
          icon: const Icon(Icons.favorite_rounded),
          onPressed: () async {
            final keys = _selected.toList();
            for (final k in keys) {
              await db.setInLibrary(k, false);
            }
            if (!mounted) return;
            setState(_selected.clear);
            showAppSnackBar(
              context,
              tr.removedFromLibrary(keys.length == 1 ? (db.manga(keys.first)?.title ?? '') : tr.selectedCount(keys.length)),
              onUndo: () async {
                for (final k in keys) {
                  await db.setInLibrary(k, true);
                }
              },
            );
          },
        ),
      ]),
    );
  }
}

/// Sort / filter / display sheet for the library.
Future<void> showLibraryOptions(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, scroll) => _LibraryOptions(scroll: scroll),
      ),
    );

class _LibraryOptions extends ConsumerWidget {
  const _LibraryOptions({required this.scroll});
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = Strings.of(context);
    final p = ref.watch(libraryPrefsProvider);
    final n = ref.read(libraryPrefsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(t, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: scheme.primary)),
        );
    final sorts = [
      (LibrarySort.lastRead, tr.sortLastRead),
      (LibrarySort.lastUpdate, tr.sortLastUpdate),
      (LibrarySort.unread, tr.sortUnread),
      (LibrarySort.title, tr.sortTitle),
      (LibrarySort.added, tr.sortAdded),
    ];
    return ListView(controller: scroll, children: [
      header(tr.filter),
      CheckboxListTile(title: Text(tr.filterUnread), value: p.filter.unread, onChanged: (v) => n.set('fUnread', v ?? false)),
      CheckboxListTile(title: Text(tr.filterStarted), value: p.filter.started, onChanged: (v) => n.set('fStarted', v ?? false)),
      CheckboxListTile(title: Text(tr.filterDownloaded), value: p.filter.downloaded, onChanged: (v) => n.set('fDownloaded', v ?? false)),
      CheckboxListTile(title: Text(tr.filterCompleted), value: p.filter.completed, onChanged: (v) => n.set('fCompleted', v ?? false)),
      header(tr.sortBy),
      for (final (s, label) in sorts)
        ListTile(
          title: Text(label),
          leading: Icon(
            p.sort == s ? (p.descending ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded) : null,
            color: scheme.primary,
          ),
          onTap: () async {
            if (p.sort == s) {
              await n.set('desc', !p.descending);
            } else {
              await n.set('sort', s);
              await n.set('desc', s != LibrarySort.title);
            }
          },
        ),
      header(tr.display),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'grid', icon: const Icon(Icons.grid_view_rounded), label: Text(tr.displayGrid)),
            ButtonSegment(value: 'compact', icon: const Icon(Icons.apps_rounded), label: Text(tr.displayCompact)),
            ButtonSegment(value: 'list', icon: const Icon(Icons.view_list_rounded), label: Text(tr.displayList)),
          ],
          selected: {p.display},
          onSelectionChanged: (v) => n.set('display', v.first),
        ),
      ),
      SwitchListTile(title: Text(tr.showUnreadBadge), value: p.unreadBadge, onChanged: (v) => n.set('unreadBadge', v)),
      SwitchListTile(title: Text(tr.showContinueButton), value: p.continueButton, onChanged: (v) => n.set('continueButton', v)),
      const SizedBox(height: 24),
    ]);
  }
}
