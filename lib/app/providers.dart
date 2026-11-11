import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/http.dart';
import '../core/models.dart';
import '../core/sources/anikoto/anikoto_source.dart';
import '../core/sources/extractors/megaplay_keys.dart';
import '../core/sources/source.dart';
import '../core/storage/app_db.dart';
import '../core/storage/records.dart';
import 'settings.dart';

export 'settings.dart' show dbProvider, settingsProvider, AppSettings;

/// App-private directory for cached posters, thumbnails and shaders.
final supportDirProvider = Provider<String>((ref) => throw UnimplementedError('supportDirProvider not overridden'));

final dioProvider = Provider<Dio>((ref) => buildDio());

final megaplayKeysProvider = Provider<MegaplayKeys>((ref) {
  final s = ref.watch(settingsProvider);
  final k = MegaplayKeys();
  if (s.megaplayAesKey.isNotEmpty) k.aesKey = s.megaplayAesKey;
  if (s.megaplayIv.isNotEmpty) k.iv = s.megaplayIv;
  if (s.megaplayTokenKey.isNotEmpty) k.tokenKey = s.megaplayTokenKey;
  return k;
});

final sourceProvider = Provider<Source>((ref) {
  final s = AnikotoSource(dio: ref.watch(dioProvider), keys: ref.watch(megaplayKeysProvider));
  s.enableKiwi = ref.watch(settingsProvider.select((x) => x.enableKiwi));
  return s;
});

final historyProvider = StreamProvider<List<HistoryEntry>>((ref) => ref.watch(dbProvider).watchHistory());
final downloadsProvider = StreamProvider<List<DownloadRecord>>((ref) => ref.watch(dbProvider).watchDownloads());

final homeProvider = FutureProvider<Map<String, List<ShowSummary>>>((ref) => ref.watch(sourceProvider).home());

final searchProvider = FutureProvider.family<List<ShowSummary>, String>((ref, q) async {
  if (q.trim().isEmpty) return const [];
  return ref.watch(sourceProvider).search(q.trim());
});

/// Show detail + episodes, cached to the database (and the poster to disk) the
/// first time a show is opened so the app can talk about it offline later.
class ShowBundle {
  ShowBundle(this.detail, this.episodes);
  final ShowDetail detail;
  final List<EpisodeInfo> episodes;
}

final showProvider = FutureProvider.family<ShowBundle, String>((ref, slug) async {
  final src = ref.watch(sourceProvider);
  final db = ref.watch(dbProvider);
  final detail = await src.showDetail(slug);
  final eps = await src.episodes(detail);
  final existing = db.show(slug);
  await db.putShow(ShowRecord.fromDetail(detail, posterPath: existing?.posterPath));
  await db.putEpisodes(slug, eps.map(EpisodeRecord.fromInfo).toList());
  unawaited(cachePoster(ref, slug, detail.poster));
  return ShowBundle(detail, eps);
});

/// Downloads the poster into the support dir and records its path.
Future<String?> cachePoster(Ref ref, String slug, String? url) async {
  if (url == null) return null;
  final db = ref.read(dbProvider);
  final rec = db.show(slug);
  if (rec?.posterPath != null && File(rec!.posterPath!).existsSync()) return rec.posterPath;
  try {
    final dir = Directory(p.join(ref.read(supportDirProvider), 'posters'))..createSync(recursive: true);
    final ext = p.extension(Uri.parse(url).path);
    final path = p.join(dir.path, '$slug${ext.isEmpty ? '.jpg' : ext}');
    await ref.read(dioProvider).download(url, path, options: Options(headers: {'Referer': 'https://anikototv.to/'}));
    if (rec != null) await db.putShow(rec.copyWith(posterPath: path));
    return path;
  } catch (_) {
    return null;
  }
}

/// Library: completed downloads grouped by show.
class LibraryShow {
  LibraryShow(this.show, this.episodes);
  final ShowRecord show;
  final List<DownloadRecord> episodes; // done, sorted by number

  int get totalBytes => episodes.fold(0, (a, e) => a + e.totalBytes);
}

final libraryProvider = Provider<List<LibraryShow>>((ref) {
  final db = ref.watch(dbProvider);
  final downloads = ref.watch(downloadsProvider).value ?? const <DownloadRecord>[];
  final bySlug = <String, List<DownloadRecord>>{};
  for (final d in downloads.where((d) => d.isDone)) {
    bySlug.putIfAbsent(d.slug, () => []).add(d);
  }
  final out = <LibraryShow>[];
  for (final e in bySlug.entries) {
    final show = db.show(e.key) ?? ShowRecord(slug: e.key, title: e.key);
    e.value.sort((a, b) => a.numeric.compareTo(b.numeric));
    out.add(LibraryShow(show, e.value));
  }
  out.sort((a, b) => a.show.title.toLowerCase().compareTo(b.show.title.toLowerCase()));
  return out;
});

final continueWatchingProvider = Provider<List<ContinueItem>>((ref) {
  final db = ref.watch(dbProvider);
  final history = ref.watch(historyProvider).value ?? const <HistoryEntry>[];
  final downloads = ref.watch(downloadsProvider).value ?? const <DownloadRecord>[];
  final shows = {for (final s in db.allShows()) s.slug: s};
  final known = <String, Set<String>>{};
  for (final h in history) {
    known.putIfAbsent(h.slug, () => {}).addAll(db.episodes(h.slug).map((e) => e.number));
  }
  for (final d in downloads.where((d) => d.isDone)) {
    known.putIfAbsent(d.slug, () => {}).add(d.episode);
  }
  return buildContinueWatching(
    history: history,
    shows: shows,
    knownEpisodes: {for (final e in known.entries) e.key: e.value.toList()},
  );
});
