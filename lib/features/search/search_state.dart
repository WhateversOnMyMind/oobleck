import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// The query shown on the Search tab. Kept outside the screen so it (and its
/// results) are still there after visiting another tab.
class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String q) => state = q.trim();
}

final searchQueryProvider = NotifierProvider<SearchQuery, String>(SearchQuery.new);

/// [current] with [query] moved to the front: trimmed, no duplicates
/// (ignoring case), at most [max] entries.
List<String> addRecentSearch(List<String> current, String query, {int max = 8}) {
  final q = query.trim();
  if (q.isEmpty) return current;
  return [q, ...current.where((e) => e.toLowerCase() != q.toLowerCase())].take(max).toList();
}

/// Recent searches, newest first, saved in the local database.
class RecentSearches extends Notifier<List<String>> {
  static const _key = 'ui:recentSearches';

  @override
  List<String> build() => (ref.watch(dbProvider).misc<List<dynamic>>(_key) ?? const []).cast<String>().toList();

  void _save(List<String> next) {
    state = next;
    unawaited(ref.read(dbProvider).setMisc(_key, next.isEmpty ? null : next));
  }

  void add(String query) => _save(addRecentSearch(state, query));
  void remove(String query) => _save(state.where((e) => e != query).toList());
  void clear() => _save(const []);

  /// Puts a cleared list back (Undo).
  void restore(List<String> list) => _save(list);
}

final recentSearchesProvider = NotifierProvider<RecentSearches, List<String>>(RecentSearches.new);
