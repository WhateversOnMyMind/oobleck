import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../log.dart';
import 'anime_titles.dart';
import 'anissia.dart';
import 'subtitle_import.dart';

/// Finds a Korean fansub for one episode with no user interaction.
///
/// Observed 2026-11-12:
///  - Anissia's caption API lists only each fansubber's *latest* post, so for
///    any other episode we read the fansubber's blog feed and look for the post
///    titled `<show> <N>화` (Tistory `/rss`, Blogspot `/feeds/posts/summary?alt=json`).
///  - Latest posts often attach a whole-season zip, so they are tried too.
///  - Attachments: Tistory files on blog.kakaocdn.net (`knm` = file name),
///    Blogspot posts link Google Drive. Font packs ("폰트") are skipped.
///  - Naver blogs return empty feeds and redirect posts, so they are skipped.
class KoreanSubFinder {
  KoreanSubFinder(this.dio, {AnissiaClient? anissia}) : anissia = anissia ?? AnissiaClient(dio);
  final Dio dio;
  final AnissiaClient anissia;

  /// Matches the show on Anissia. Returns null unless the match is certain
  /// (same season and the same Japanese/Korean title), so a wrong season's
  /// subtitles are never loaded silently.
  Future<AnissiaAnime?> matchShow(AnimeTitles titles) async {
    for (final q in anissiaQueries(titles)) {
      List<AnissiaAnime> r;
      try {
        r = await anissia.search(q);
      } catch (e) {
        Log.d('ko-subs', 'anissia search "$q" failed: $e');
        continue;
      }
      final hit = pickConfident(r, titles);
      if (hit != null) return hit;
    }
    return null;
  }

  /// Finds and downloads the subtitle for [episode] of [show].
  Future<FoundKoreanSub?> find(AnissiaAnime show, String episode) async {
    final ep = int.tryParse(episode);
    if (ep == null) return null;
    final captions = await anissia.captions(show.animeNo);
    for (final c in captions) {
      if (c.website.isEmpty) continue;
      final host = Uri.tryParse(c.website)?.host ?? '';
      if (host.contains('naver.com')) continue;
      try {
        final posts = <({String url, bool episodeOnly})>[];
        if ((c.number ?? -1) == ep) posts.add((url: c.website, episodeOnly: true));
        for (final url in await _episodePosts(c.website, show.subject, ep)) {
          if (url != c.website) posts.add((url: url, episodeOnly: true));
        }
        // The latest post may carry a season pack.
        if ((c.number ?? -1) != ep) posts.add((url: c.website, episodeOnly: false));
        for (final post in posts) {
          final found = await _fromPost(post.url, ep, post.episodeOnly);
          if (found != null) {
            Log.d('ko-subs', 'episode $ep from ${c.name} (${post.url}): ${found.fileName}');
            return FoundKoreanSub(found.prepared, c.name.isEmpty ? 'Anissia' : c.name);
          }
        }
      } catch (e) {
        Log.d('ko-subs', '${c.name} failed: $e');
      }
    }
    return null;
  }

  Future<List<String>> _episodePosts(String postUrl, String subject, int ep) async {
    final u = Uri.parse(postUrl);
    List<({String title, String url})> items;
    if (u.host.endsWith('.tistory.com')) {
      final r = await dio.get<String>('https://${u.host}/rss', options: Options(responseType: ResponseType.plain));
      items = parseRssItems(r.data ?? '');
    } else if (u.host.endsWith('.blogspot.com')) {
      final r = await dio.get<String>('https://${u.host}/feeds/posts/summary',
          queryParameters: {'alt': 'json', 'max-results': '150'}, options: Options(responseType: ResponseType.plain));
      items = parseBloggerFeed(r.data ?? '');
    } else {
      return const [];
    }
    return [for (final i in items) if (postMatches(i.title, subject, ep)) i.url];
  }

  Future<({PreparedSubtitle prepared, String fileName})?> _fromPost(String url, int ep, bool episodeOnly) async {
    final attachments = (await findAttachments(dio, url)).where((a) => !isFontPack(a.name)).toList();
    for (final a in attachments) {
      Map<String, List<int>> files;
      try {
        files = await fetchSubtitleFiles(dio, a);
      } catch (e) {
        Log.d('ko-subs', 'attachment ${a.name} failed: $e');
        continue;
      }
      final name = matchEpisodeFile(files.keys.toList(), ep, episodeOnly: episodeOnly);
      if (name != null) return (prepared: prepareSubtitle(files[name]!, name), fileName: name);
    }
    return null;
  }
}

class FoundKoreanSub {
  FoundKoreanSub(this.subtitle, this.fansubber);
  final PreparedSubtitle subtitle;
  final String fansubber;
  String get label => 'Korean · $fansubber';
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');

String _stripSeason(String s) => s
    .replaceAll(RegExp(r'第\s*\d+\s*期'), '')
    .replaceAll(RegExp(r'\d+(?:st|nd|rd|th)\s+season', caseSensitive: false), '')
    .replaceAll(RegExp(r'season\s*\d+', caseSensitive: false), '')
    .replaceAll(RegExp(r'시즌\s*\d+'), '')
    .replaceAll(RegExp(r'\d+\s*기(?![가-힣])'), '')
    .trim();

bool _isFilm(String s) => s.startsWith('극장판') || s.contains('映画') || s.contains('劇場版');

/// The Anissia entry that is certainly this show and season, or null.
AnissiaAnime? pickConfident(List<AnissiaAnime> items, AnimeTitles t) {
  final native = t.native;
  if (native == null || native.isEmpty) return null;
  final season = seasonOf(native) ?? 1;
  final base = _norm(_stripSeason(native));
  for (final a in items) {
    final aSeason = seasonOf(a.subject) ?? seasonOf(a.originalSubject) ?? 1;
    if (aSeason != season || _isFilm(a.subject) != _isFilm(native)) continue;
    final sameTitle = (a.originalSubject.isNotEmpty && _norm(_stripSeason(a.originalSubject)) == base) ||
        t.korean.any((k) => _norm(_stripSeason(k)) == _norm(_stripSeason(a.subject)));
    if (sameTitle) return a;
  }
  return null;
}

/// Whether a blog post title is this show's post for episode [ep]
/// ("약사의 혼잣말 3기 6화 자막", "… 06화", "… EP.6", "… 第6話").
bool postMatches(String title, String subject, int ep) {
  final t = _norm(title);
  final base = _norm(_stripSeason(subject));
  if (base.isEmpty || !t.contains(base)) return false;
  final season = seasonOf(subject);
  final titleSeason = seasonOf(title);
  if ((season ?? 1) != (titleSeason ?? 1)) return false;
  return RegExp('(?<![0-9])0*$ep\\s*(화|話|회)').hasMatch(title) ||
      RegExp('(?:ep|e|#)\\.?\\s*0*$ep(?![0-9])', caseSensitive: false).hasMatch(title) ||
      RegExp('第\\s*0*$ep\\s*話').hasMatch(title);
}

/// Picks the file for [ep] among subtitle file names. The number must appear
/// in the name ("06", "6", "E06") unless [episodeOnly] says the whole post is
/// this episode and holds a single file.
String? matchEpisodeFile(List<String> names, int ep, {bool episodeOnly = false}) {
  if (names.isEmpty) return null;
  final noise = RegExp(r'(1080|720|480|2160|x?26[45]|10bit|8bit|\d{3,4}p|\[[0-9a-f]{8}\])', caseSensitive: false);
  final re = RegExp('(?<![0-9])0*$ep(?![0-9])');
  final hits = names.where((n) => re.hasMatch(p.basenameWithoutExtension(n).replaceAll(noise, ''))).toList();
  if (hits.isNotEmpty) {
    // Prefer ASS (styled) over SRT/SMI when a pack has both.
    hits.sort((a, b) => _rank(a).compareTo(_rank(b)));
    return hits.first;
  }
  // A lone file in this episode's post, unless its name carries another number.
  if (episodeOnly && names.length == 1) {
    final clean = p.basenameWithoutExtension(names.first).replaceAll(noise, '');
    if (!RegExp(r'(?<![0-9])[0-9]{1,3}(?![0-9])').hasMatch(clean)) return names.first;
  }
  return null;
}

int _rank(String n) => switch (p.extension(n).toLowerCase()) { '.ass' => 0, '.ssa' => 1, '.srt' => 2, '.smi' => 3, _ => 4 };

bool isFontPack(String name) => RegExp('폰트|글꼴|font', caseSensitive: false).hasMatch(name);

/// `<item><title>…</title><link>…</link></item>` pairs from an RSS feed.
List<({String title, String url})> parseRssItems(String xml) {
  String clean(String s) => s
      .replaceAllMapped(RegExp(r'<!\[CDATA\[(.*?)\]\]>', dotAll: true), (m) => m[1]!)
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&')
      .trim();
  String? tag(String item, String name) =>
      RegExp('<$name>(.*?)</$name>', dotAll: true).firstMatch(item)?.group(1);
  return [
    for (final m in RegExp(r'<item\b.*?</item>', dotAll: true).allMatches(xml))
      (title: clean(tag(m[0]!, 'title') ?? ''), url: clean(tag(m[0]!, 'link') ?? '')),
  ];
}

List<({String title, String url})> parseBloggerFeed(String body) {
  try {
    final entries = ((jsonDecode(body) as Map)['feed'] as Map?)?['entry'] as List? ?? const [];
    return [
      for (final e in entries.cast<Map>())
        (
          title: ((e['title'] as Map?)?[r'$t'] as String? ?? '').trim(),
          url: ((e['link'] as List?) ?? const [])
                  .cast<Map>()
                  .where((l) => l['rel'] == 'alternate')
                  .map((l) => l['href'] as String)
                  .firstOrNull ??
              '',
        )
    ];
  } catch (_) {
    return const [];
  }
}

