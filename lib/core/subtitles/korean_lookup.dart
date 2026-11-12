import 'package:dio/dio.dart';

import '../log.dart';
import '../storage/app_db.dart';
import 'anime_titles.dart';
import 'anissia.dart';
import 'korean_auto.dart';

/// Finds a Korean fansub for one episode of a show, remembering the show's
/// Anissia match in the database (`anissia:<slug>`, shared with the manual
/// finder) so the title lookup runs once per season.
Future<FoundKoreanSub?> lookupKoreanSub({
  required Dio dio,
  required AppDb db,
  required String slug,
  required String? malId,
  required String episode,
}) async {
  final finder = KoreanSubFinder(dio);
  AnissiaAnime? show;
  final saved = db.misc<Map>('anissia:$slug');
  if (saved != null && saved['animeNo'] is int) {
    show = AnissiaAnime(animeNo: saved['animeNo'] as int, subject: saved['subject'] as String? ?? '', originalSubject: '');
  } else {
    if (malId == null || malId.isEmpty) return null;
    final titles = await AnimeTitles.forMal(dio, malId);
    show = await finder.matchShow(titles);
    if (show == null) {
      Log.d('ko-subs', 'no certain Anissia match for $slug (${titles.native})');
      return null;
    }
    await db.setMisc('anissia:$slug', {'animeNo': show.animeNo, 'subject': show.subject});
  }
  return finder.find(show, episode);
}
