import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

enum LibrarySort { title, recent, size }

/// [shows] in the chosen order: A-Z, most recently downloaded first, or
/// largest first. Ties fall back to the title so the order is stable.
List<LibraryShow> sortLibrary(List<LibraryShow> shows, LibrarySort sort) {
  int byTitle(LibraryShow a, LibraryShow b) => a.show.title.toLowerCase().compareTo(b.show.title.toLowerCase());
  int newest(LibraryShow s) => s.episodes.fold(0, (m, e) => e.createdAt > m ? e.createdAt : m);
  final out = [...shows];
  switch (sort) {
    case LibrarySort.title:
      out.sort(byTitle);
    case LibrarySort.recent:
      out.sort((a, b) {
        final c = newest(b).compareTo(newest(a));
        return c != 0 ? c : byTitle(a, b);
      });
    case LibrarySort.size:
      out.sort((a, b) {
        final c = b.totalBytes.compareTo(a.totalBytes);
        return c != 0 ? c : byTitle(a, b);
      });
  }
  return out;
}

/// The Downloaded tab's sort order, remembered between launches.
class LibrarySortNotifier extends Notifier<LibrarySort> {
  static const _key = 'ui:librarySort';

  @override
  LibrarySort build() {
    final saved = ref.watch(dbProvider).misc<String>(_key);
    return LibrarySort.values.firstWhere((s) => s.name == saved, orElse: () => LibrarySort.title);
  }

  void set(LibrarySort sort) {
    state = sort;
    unawaited(ref.read(dbProvider).setMisc(_key, sort.name));
  }
}

final librarySortProvider = NotifierProvider<LibrarySortNotifier, LibrarySort>(LibrarySortNotifier.new);
