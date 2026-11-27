import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../core/storage/app_db.dart';
import '../../core/storage/manga_records.dart';
import 'browse_view.dart';
import 'library_view.dart';
import 'manga_downloads_screen.dart';
import 'manga_providers.dart';
import 'manga_strings.dart';
import 'updates_view.dart';

/// The Manga tab: Library, Updates, History and Browse.
class MangaTab extends ConsumerStatefulWidget {
  const MangaTab({super.key});
  @override
  ConsumerState<MangaTab> createState() => _MangaTabState();
}

class _MangaTabState extends ConsumerState<MangaTab> with SingleTickerProviderStateMixin {
  static const _tabKey = 'manga.tab';
  late final TabController _tabs;
  final _library = GlobalKey<LibraryViewState>();
  final _browse = GlobalKey<BrowseViewState>();

  @override
  void initState() {
    super.initState();
    final db = ref.read(dbProvider);
    // Start on Browse until something is in the library.
    final saved = db.setting<int>(_tabKey);
    final initial = saved ?? (db.libraryManga().isEmpty ? 3 : 0);
    _tabs = TabController(length: 4, vsync: this, initialIndex: initial.clamp(0, 3))
      ..addListener(() {
        if (_tabs.indexIsChanging) return;
        unawaited(db.setSetting(_tabKey, _tabs.index));
        setState(() {});
      });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final tr = Strings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final found = await ref.read(libraryRefresherProvider.notifier).refreshAll();
    if (mounted) messenger.showSnackBar(SnackBar(content: Text(tr.newChaptersFound(found))));
  }

  @override
  Widget build(BuildContext context) {
    final tr = Strings.of(context);
    final downloads = ref.watch(mangaDownloadsProvider).value ?? const <MangaDownloadRecord>[];
    final active = downloads.where((d) => d.status == MangaDownloadStatus.running || d.status == MangaDownloadStatus.queued).length;
    final refreshing = ref.watch(libraryRefresherProvider).running;
    final updates = ref.watch(mangaUpdatesProvider).value?.length ?? 0;

    final downloadsButton = IconButton(
      tooltip: tr.mangaDownloads,
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MangaDownloadsScreen())),
      icon: Badge(isLabelVisible: active > 0, label: Text('$active'), child: const Icon(Icons.download_rounded)),
    );
    final refreshButton = IconButton(
      tooltip: tr.checkForUpdates,
      onPressed: refreshing ? null : _refresh,
      icon: refreshing
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.refresh_rounded),
    );

    final actions = switch (_tabs.index) {
      0 => [
          IconButton(tooltip: tr.searchLibrary, icon: const Icon(Icons.search_rounded), onPressed: () => _library.currentState?.toggleSearch()),
          IconButton(tooltip: tr.filter, icon: const Icon(Icons.filter_list_rounded), onPressed: () => showLibraryOptions(context)),
          refreshButton,
          downloadsButton,
        ],
      1 => [
          refreshButton,
          PopupMenuButton<String>(
            onSelected: (_) => ref.read(dbProvider).clearMangaUpdates(),
            itemBuilder: (_) => [PopupMenuItem(value: 'clear', child: Text(tr.clearUpdates))],
          ),
        ],
      2 => [
          IconButton(
            tooltip: tr.clearMangaHistory,
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(tr.clearMangaHistory),
                  content: Text(tr.clearMangaHistoryBody),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr.cancel)),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr.clear)),
                  ],
                ),
              );
              if (ok == true) await ref.read(dbProvider).clearMangaHistory();
            },
          ),
        ],
      _ => [
          IconButton(tooltip: tr.searchManga, icon: const Icon(Icons.search_rounded), onPressed: () => _browse.currentState?.focusSearch()),
          downloadsButton,
        ],
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(tr.navManga, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: actions,
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: tr.mangaLibrary),
            Tab(child: Badge(isLabelVisible: updates > 0, label: Text('$updates'), offset: const Offset(14, -4), child: Text(tr.mangaUpdates))),
            Tab(text: tr.mangaHistory),
            Tab(text: tr.mangaBrowse),
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        LibraryView(key: _library, onBrowse: () => _tabs.animateTo(3)),
        UpdatesView(onRefresh: _refresh),
        const HistoryView(),
        BrowseView(key: _browse),
      ]),
    );
  }
}
