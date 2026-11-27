import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/strings_ui.dart';
import '../../app/theme.dart';
import '../../core/models.dart';
import '../../ui/feedback.dart';
import '../../ui/layout.dart';
import '../../ui/skeletons.dart';
import '../../ui/widgets.dart';
import '../home/home_screen.dart';
import 'search_state.dart';

/// Search as you type. The query and results survive a visit to another tab;
/// recent searches are one tap away while the field is empty.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller = TextEditingController(text: ref.read(searchQueryProvider));
  final _fieldFocus = FocusNode();
  final _screenFocus = FocusNode(debugLabel: 'search screen');
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _fieldFocus.dispose();
    _screenFocus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    // Clearing the field shows recent searches at once; typing waits a moment.
    if (v.trim().isEmpty) {
      ref.read(searchQueryProvider.notifier).set('');
    } else {
      _debounce = Timer(const Duration(milliseconds: 350), () => ref.read(searchQueryProvider.notifier).set(v));
    }
  }

  void _submit(String v) {
    _debounce?.cancel();
    ref.read(searchQueryProvider.notifier).set(v);
    if (v.trim().isNotEmpty) ref.read(recentSearchesProvider.notifier).add(v);
  }

  void _useRecent(String q) {
    _controller.text = q;
    _controller.selection = TextSelection.collapsed(offset: q.length);
    _leaveField();
    _submit(q);
  }

  /// On phones, hides the keyboard but keeps focus on this screen so the
  /// shortcuts still work. With a physical keyboard the field keeps focus.
  void _leaveField() {
    if (!isDesktop) _screenFocus.requestFocus();
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    ref.read(searchQueryProvider.notifier).set('');
    _fieldFocus.requestFocus();
  }

  void _open(ShowSummary show) {
    // Opening a result is the best sign the search was useful: remember it.
    final q = ref.read(searchQueryProvider);
    if (q.isNotEmpty) ref.read(recentSearchesProvider.notifier).add(q);
    _leaveField();
    openShow(context, show.slug);
  }

  /// "/" or Ctrl+F jumps to the search field from anywhere on this tab.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final ctrlF = e.logicalKey == LogicalKeyboardKey.keyF &&
        (HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed);
    final slash = e.logicalKey == LogicalKeyboardKey.slash && !_fieldFocus.hasFocus;
    if (!ctrlF && !slash) return KeyEventResult.ignored;
    _fieldFocus.requestFocus();
    _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final s = Strings.of(context);
    return Focus(
      focusNode: _screenFocus,
      autofocus: !isDesktop,
      onKeyEvent: _onKey,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.m, Gap.m, Gap.m, Gap.s),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: TextField(
                  controller: _controller,
                  focusNode: _fieldFocus,
                  // A keyboard is always there on desktop; on phones it would
                  // cover the recent searches every time the tab opens.
                  autofocus: isDesktop,
                  onChanged: _onChanged,
                  onSubmitted: _submit,
                  onTapOutside: (_) => _leaveField(),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: s.searchHint,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _controller,
                      builder: (context, v, _) => v.text.isEmpty
                          ? const SizedBox.shrink()
                          : IconButton(tooltip: s.clearSearch, icon: const Icon(Icons.close_rounded), onPressed: _clear),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: query.isEmpty ? _idle(s) : _results(s, query)),
          ],
        ),
      ),
    );
  }

  Widget _idle(Strings s) {
    final recent = ref.watch(recentSearchesProvider);
    if (recent.isEmpty) {
      return EmptyState(icon: Icons.search_rounded, title: s.findSomething, message: s.searchByTitle);
    }
    final recents = ref.read(recentSearchesProvider.notifier);
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          key: const PageStorageKey<String>('search-recent'),
          padding: const EdgeInsets.only(bottom: Gap.xl),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.s, 0),
              child: Row(children: [
                Expanded(child: Text(s.recentSearches, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                TextButton(
                  onPressed: () {
                    final old = [...recent];
                    recents.clear();
                    showAppSnackBar(context, s.recentCleared, onUndo: () => recents.restore(old));
                  },
                  child: Text(s.clearAll),
                ),
              ]),
            ),
            for (final q in recent)
              ListTile(
                leading: const Icon(Icons.history_rounded),
                title: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: s.removeRecent(q),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => recents.remove(q),
                ),
                onTap: () => _useRecent(q),
              ),
          ],
        ),
      ),
    );
  }

  Widget _results(Strings s, String query) {
    final results = ref.watch(searchProvider(query));
    return results.when(
      loading: () => const CustomScrollView(
        physics: NeverScrollableScrollPhysics(),
        slivers: [SliverPosterGridSkeleton()],
      ),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(searchProvider(query))),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(icon: Icons.sentiment_neutral_rounded, title: s.noResults, message: s.nothingMatched(query));
        }
        return LayoutBuilder(
          builder: (context, box) => GridView.builder(
            key: PageStorageKey<String>('search-results-$query'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(Gap.m, Gap.s, Gap.m, Gap.xl),
            gridDelegate: posterGridDelegate(context, box.maxWidth),
            itemCount: list.length,
            itemBuilder: (context, i) => PosterCard(
              title: list[i].title,
              url: list[i].poster,
              onTap: () => _open(list[i]),
            ),
          ),
        );
      },
    );
  }
}
