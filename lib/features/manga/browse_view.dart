import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../core/manga/manga_models.dart';
import '../../core/storage/app_db.dart';
import '../../core/storage/manga_records.dart';
import '../../ui/widgets.dart';
import 'manga_detail_screen.dart';
import 'manga_providers.dart';
import 'manga_strings.dart';
import 'manga_widgets.dart';

/// The site's lists (latest, popular, completed...) with genre filters, and search.
class BrowseView extends ConsumerStatefulWidget {
  const BrowseView({super.key});
  @override
  ConsumerState<BrowseView> createState() => BrowseViewState();
}

class BrowseViewState extends ConsumerState<BrowseView> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String? _catalog;
  Set<String> _genres = {};
  String? _query;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void focusSearch() => _searchFocus.requestFocus();

  void _onType(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => _submit(v));
  }

  void _submit(String v) {
    _debounce?.cancel();
    final q = v.trim();
    setState(() => _query = q.isEmpty ? null : q);
  }

  @override
  Widget build(BuildContext context) {
    final tr = Strings.of(context);
    final source = ref.watch(mangaSourceProvider);
    final catalogs = source.catalogs;
    final catalog = catalogs.firstWhere((c) => c.id == _catalog, orElse: () => catalogs.first);
    final genresOn = catalog.supportsGenres && _query == null;
    final query = _query != null
        ? ListingQuery(query: _query)
        : ListingQuery(catalog: catalog.id, genres: genresOn ? _genres : const {});

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: TextField(
          controller: _search,
          focusNode: _searchFocus,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: tr.searchManga,
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query == null && _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: tr.clear,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _search.clear();
                      _submit('');
                    },
                  ),
            isDense: true,
          ),
          onChanged: (v) {
            setState(() {});
            _onType(v);
          },
          onSubmitted: _submit,
        ),
      ),
      if (_query == null)
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final c in catalogs)
              Padding(
                padding: const EdgeInsets.only(right: 6, top: 8, bottom: 8),
                child: ChoiceChip(
                  label: Text(c.title(tr.isKorean)),
                  selected: c.id == catalog.id,
                  onSelected: (_) => setState(() => _catalog = c.id),
                ),
              ),
            if (catalog.supportsGenres)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 8, bottom: 8),
                child: ActionChip(
                  avatar: Icon(Icons.tune_rounded, size: 18, color: _genres.isEmpty ? null : Theme.of(context).colorScheme.primary),
                  label: Text(_genres.isEmpty ? tr.genres : '${tr.genres} · ${_genres.length}'),
                  onPressed: () => _pickGenres(tr, source.genres),
                ),
              ),
          ]),
        ),
      Expanded(child: _Listing(key: ValueKey(query.hashCode), query: query)),
    ]);
  }

  Future<void> _pickGenres(Strings tr, List<MangaGenre> all) async {
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _GenreSheet(all: all, initial: _genres, tr: tr),
    );
    if (picked != null) setState(() => _genres = picked);
  }
}

class _GenreSheet extends StatefulWidget {
  const _GenreSheet({required this.all, required this.initial, required this.tr});
  final List<MangaGenre> all;
  final Set<String> initial;
  final Strings tr;
  @override
  State<_GenreSheet> createState() => _GenreSheetState();
}

class _GenreSheetState extends State<_GenreSheet> {
  late final Set<String> _picked = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    final tr = widget.tr;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(tr.genres, style: Theme.of(context).textTheme.titleMedium)),
            TextButton(onPressed: () => setState(_picked.clear), child: Text(tr.allGenres)),
          ]),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final g in widget.all)
                  FilterChip(
                    label: Text(g.label),
                    selected: _picked.contains(g.value),
                    onSelected: (v) => setState(() => v ? _picked.add(g.value) : _picked.remove(g.value)),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: () => Navigator.pop(context, _picked), child: Text(tr.save)),
          ),
        ]),
      ),
    );
  }
}

/// An infinite grid of a catalog or search.
class _Listing extends ConsumerWidget {
  const _Listing({super.key, required this.query});
  final ListingQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = Strings.of(context);
    final state = ref.watch(listingProvider(query));
    final notifier = ref.read(listingProvider(query).notifier);
    final source = ref.watch(mangaSourceProvider);
    final records = ref.watch(mangaRecordsProvider).value ?? const [];
    final inLibrary = {for (final r in records) if (r.inLibrary && r.sourceId == source.id) r.mangaId};

    if (state.items.isEmpty) {
      if (state.error != null) return ErrorState(error: state.error!, onRetry: notifier.reload);
      if (state.loading) {
        return LayoutBuilder(
          builder: (context, box) => GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: coverGridDelegate(box.maxWidth),
            itemCount: 12,
            itemBuilder: (_, _) => const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AspectRatio(aspectRatio: 0.7, child: Skeleton()),
              SizedBox(height: 8),
              Skeleton(height: 14),
            ]),
          ),
        );
      }
      return ListView(children: [
        const SizedBox(height: 60),
        EmptyState(icon: Icons.search_off_rounded, title: tr.noResults, message: query.query == null ? null : tr.noResultsHint),
      ]);
    }

    return RefreshIndicator(
      onRefresh: notifier.reload,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels > n.metrics.maxScrollExtent - 600 && state.hasNext && !state.loading && state.error == null) {
            unawaited(notifier.loadMore());
          }
          return false;
        },
        child: LayoutBuilder(
          builder: (context, box) => CustomScrollView(slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              sliver: SliverGrid.builder(
                gridDelegate: coverGridDelegate(box.maxWidth),
                itemCount: state.items.length,
                itemBuilder: (context, i) {
                  final m = state.items[i];
                  final saved = inLibrary.contains(m.id);
                  return MangaCard(
                    title: m.title,
                    cover: m.cover,
                    headers: source.imageHeaders,
                    subtitle: m.subtitle,
                    dimmed: saved,
                    badges: [
                      if (saved) (tr.inLibrary, Theme.of(context).colorScheme.primary),
                      if (m.adult) ('17+', const Color(0xFFB3261E)),
                    ],
                    onTap: () async {
                      final key = await rememberSummary(ref.read(dbProvider), source, m);
                      if (context.mounted) await openMangaDetail(context, key);
                    },
                    onLongPress: () async {
                      // Long press toggles the library without opening the series.
                      final db = ref.read(dbProvider);
                      final key = await rememberSummary(db, source, m);
                      await db.setInLibrary(key, !saved);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(SnackBar(
                          content: Text(saved ? tr.removedFromLibrary(m.title) : tr.addedToLibrary(m.title)),
                          action: SnackBarAction(label: tr.undo, onPressed: () => db.setInLibrary(key, saved)),
                        ));
                      if (!saved) unawaited(ref.read(mangaRefreshProvider(mangaKeyOf(source.id, m.id)).future).then((_) {}, onError: (_) {}));
                    },
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: state.loading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : state.error != null
                          ? TextButton.icon(onPressed: notifier.loadMore, icon: const Icon(Icons.refresh_rounded), label: Text(tr.retry))
                          : state.hasNext
                              ? TextButton(onPressed: notifier.loadMore, child: Text(tr.loadMore))
                              : const SizedBox.shrink(),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
