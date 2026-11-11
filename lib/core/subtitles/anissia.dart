import 'package:dio/dio.dart';

/// Anissia (anissia.net) public API client.
///
/// Endpoints verified against the live site's own web app on 2026-11-11:
///  - `GET https://api.anissia.net/anime/list/{page}?q=<query>` -> `data.content[]`
///    (matches Korean and Japanese titles; English titles rarely match)
///  - `GET https://api.anissia.net/anime/caption/animeNo/{animeNo}` -> `data[]`
///    `{episode, updDt, website, name}` (name = fansubber, website = release post)
class AnissiaAnime {
  AnissiaAnime({required this.animeNo, required this.subject, required this.originalSubject, this.captionCount = 0});
  final int animeNo;
  final String subject;
  final String originalSubject;
  final int captionCount;

  factory AnissiaAnime.fromJson(Map<String, dynamic> j) => AnissiaAnime(
        animeNo: j['animeNo'] as int,
        subject: j['subject'] as String? ?? '',
        originalSubject: j['originalSubject'] as String? ?? '',
        captionCount: j['captionCount'] as int? ?? 0,
      );
}

class AnissiaCaption {
  AnissiaCaption({required this.episode, required this.name, required this.website, required this.updated});
  final String episode;
  final String name;
  final String website;
  final String updated;

  factory AnissiaCaption.fromJson(Map<String, dynamic> j) => AnissiaCaption(
        episode: '${j['episode'] ?? ''}',
        name: j['name'] as String? ?? '',
        website: j['website'] as String? ?? '',
        updated: j['updDt'] as String? ?? '',
      );

  /// Numeric episode ("7" -> 7). Non-numeric (e.g. "0" = special) -> null.
  double? get number => double.tryParse(episode);
}

class AnissiaClient {
  AnissiaClient(this.dio, {this.base = 'https://api.anissia.net'});
  final Dio dio;
  final String base;

  Future<List<AnissiaAnime>> search(String query) async {
    final r = await dio.get<Map<String, dynamic>>('$base/anime/list/0', queryParameters: {'q': query});
    final content = ((r.data?['data'] as Map?)?['content'] as List?) ?? const [];
    return [for (final x in content) AnissiaAnime.fromJson((x as Map).cast<String, dynamic>())];
  }

  Future<List<AnissiaCaption>> captions(int animeNo) async {
    final r = await dio.get<Map<String, dynamic>>('$base/anime/caption/animeNo/$animeNo');
    final data = (r.data?['data'] as List?) ?? const [];
    return [for (final x in data) AnissiaCaption.fromJson((x as Map).cast<String, dynamic>())]
      ..sort((a, b) => (b.number ?? 0).compareTo(a.number ?? 0));
  }
}
