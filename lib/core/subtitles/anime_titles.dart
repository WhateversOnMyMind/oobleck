import 'package:dio/dio.dart';

/// Native (Japanese) title and Korean synonyms for a show, looked up by its
/// MyAnimeList id on AniList's public GraphQL API (`https://graphql.anilist.co`,
/// no key; checked 2026-11-12). Anissia matches Korean and Japanese titles but
/// almost never English ones, so these are what the Korean finder searches with.
class AnimeTitles {
  const AnimeTitles({this.native, this.korean = const []});
  final String? native;
  final List<String> korean;

  static final RegExp _hangul = RegExp(r'[가-힣]');

  static Future<AnimeTitles> forMal(Dio dio, String malId) async {
    final id = int.tryParse(malId);
    if (id == null) return const AnimeTitles();
    final r = await dio.post<Map<String, dynamic>>(
      'https://graphql.anilist.co',
      data: {
        'query': r'query($id:Int){Media(idMal:$id,type:ANIME){title{native} synonyms}}',
        'variables': {'id': id},
      },
      options: Options(headers: {'Content-Type': 'application/json', 'Accept': 'application/json'}),
    );
    final media = ((r.data?['data'] as Map?)?['Media'] as Map?) ?? const {};
    final synonyms = [for (final s in (media['synonyms'] as List?) ?? const []) '$s'];
    return AnimeTitles(
      native: ((media['title'] as Map?)?['native'] as String?)?.trim(),
      korean: synonyms.where(_hangul.hasMatch).toList(),
    );
  }
}

/// Season number in a title: "第2期", "2nd Season", "Season 2", "시즌 2", "2기".
int? seasonOf(String title) {
  final patterns = [
    RegExp(r'第\s*(\d+)\s*期'),
    RegExp(r'(\d+)(?:st|nd|rd|th)\s+season', caseSensitive: false),
    RegExp(r'season\s*(\d+)', caseSensitive: false),
    RegExp(r'시즌\s*(\d+)'),
    RegExp(r'(\d+)\s*기(?![가-힣])'),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(title);
    if (m != null) return int.tryParse(m.group(1)!);
  }
  return null;
}

/// Search strings to try on Anissia, best first: Korean synonyms, the native
/// title, the native title without a season marker, and its first word.
List<String> anissiaQueries(AnimeTitles t, {String? fallback}) {
  final out = <String>[...t.korean];
  final n = t.native;
  if (n != null && n.isNotEmpty) {
    out.add(n);
    final base = n
        .replaceAll(RegExp(r'第\s*\d+\s*期'), '')
        .replaceAll(RegExp(r'\d+(?:st|nd|rd|th)\s+season', caseSensitive: false), '')
        .replaceAll(RegExp(r'season\s*\d+', caseSensitive: false), '')
        .replaceAll(RegExp(r'[(（].*?[)）]'), '')
        .trim();
    out.add(base);
    final first = base.split(RegExp(r'[\s:：・]')).first.trim();
    if (first.length >= 2) out.add(first);
  }
  if (fallback != null && fallback.trim().isNotEmpty) out.add(fallback.trim());
  final seen = <String>{};
  return [for (final q in out) if (q.isNotEmpty && seen.add(q)) q];
}

bool _isMovie(String s) => s.startsWith('극장판') || s.contains('映画') || s.contains('劇場版');

/// Orders Anissia matches for a show: exact native title first, then the same
/// season (no marker = season 1), and films last unless the show is a film.
List<T> rankMatches<T>(List<T> items, {required String Function(T) subject, required String Function(T) original, String? native}) {
  final season = native == null ? 1 : (seasonOf(native) ?? 1);
  final wantMovie = native != null && _isMovie(native);
  int score(T a) {
    var s = 0;
    if (native != null && original(a) == native) s += 100;
    final aSeason = seasonOf(subject(a)) ?? seasonOf(original(a)) ?? 1;
    if (aSeason == season) s += 50;
    if (_isMovie(subject(a)) || _isMovie(original(a))) s += wantMovie ? 20 : -30;
    return s;
  }

  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((x, y) {
    final d = score(y.$2).compareTo(score(x.$2));
    return d != 0 ? d : x.$1.compareTo(y.$1);
  });
  return [for (final e in indexed) e.$2];
}
