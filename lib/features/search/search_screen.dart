import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../ui/widgets.dart';
import '../home/home_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => setState(() => _query = v.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final results = _query.isEmpty ? null : ref.watch(searchProvider(_query));
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.m, Gap.m, Gap.m, Gap.s),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              onSubmitted: (v) => setState(() => _query = v.trim()),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search anime',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: results == null
                ? const EmptyState(icon: Icons.search_rounded, title: 'Find something to watch', message: 'Search by title.')
                : results.when(
                    loading: () => GridView.builder(
                      padding: const EdgeInsets.all(Gap.m),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 160, childAspectRatio: 0.55, crossAxisSpacing: Gap.m, mainAxisSpacing: Gap.m),
                      itemCount: 9,
                      itemBuilder: (_, _) => const Skeleton(),
                    ),
                    error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(searchProvider(_query))),
                    data: (list) => list.isEmpty
                        ? EmptyState(icon: Icons.sentiment_neutral_rounded, title: 'No results', message: 'Nothing matched "$_query". Try another spelling.')
                        : GridView.builder(
                            padding: const EdgeInsets.all(Gap.m),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 160, childAspectRatio: 0.55, crossAxisSpacing: Gap.m, mainAxisSpacing: Gap.m),
                            itemCount: list.length,
                            itemBuilder: (context, i) => PosterCard(
                              title: list[i].title,
                              url: list[i].poster,
                              onTap: () => openShow(context, list[i].slug),
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
