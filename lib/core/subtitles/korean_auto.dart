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
        for (final url in await _episodePosts(c.website, c.number?.toInt(), show.subject, ep)) {
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

  /// Posts on the same blog that are for episode [ep]: from the blog feed
  /// (recent posts) and, using the fansubber's own short name for the show
  /// (learned from the latest post's title, whose episode is [latestEp]), from
  /// the blog's search, which also reaches older seasons.
  Future<List<String>> _episodePosts(String postUrl, int? latestEp, String subject, int ep) async {
    final u = Uri.parse(postUrl);
    final tistory = u.host.endsWith('.tistory.com');
    final blogspot = u.host.endsWith('.blogspot.com');
    if (!tistory && !blogspot) return const [];

    final feed = await _get(tistory
        ? 'https://${u.host}/rss'
        : 'https://${u.host}/feeds/posts/summary?alt=json&max-results=150');
    var items = tistory ? parseRssItems(feed ?? '') : parseBloggerFeed(feed ?? '');

    String? prefix;
    if (latestEp != null) {
      var latestTitle = items.where((i) => i.url == postUrl).firstOrNull?.title;
      latestTitle ??= _pageTitle(await _get(postUrl) ?? '');
      if (latestTitle != null) prefix = titlePrefix(latestTitle, latestEp);
    }
    if (prefix != null) {
      final q = Uri.encodeComponent(prefix);
      if (tistory) {
        for (var page = 1; page <= 3; page++) {
          final found = parseTistorySearch(await _get('https://${u.host}/search/$q?page=$page') ?? '', u.host);
          if (found.isEmpty) break;
          items = [...items, ...found];
        }
      } else {
        items = [
          ...items,
          ...parseBloggerFeed(await _get('https://${u.host}/feeds/posts/summary?alt=json&max-results=150&q=$q') ?? ''),
        ];
      }
    }
    Log.d('ko-subs', '${u.host}: ${items.length} posts checked, short name "${prefix ?? '-'}"');
    final out = <String>[];
    for (final i in items) {
      final hit = postMatches(i.title, subject, ep) || (prefix != null && prefixMatches(i.title, prefix, ep));
      if (hit && !out.contains(i.url)) out.add(i.url);
    }
    return out;
  }

  Future<String?> _get(String url) async {
    try {
      final r = await dio.get<String>(url, options: Options(responseType: ResponseType.plain));
      return r.data;
    } catch (e) {
      Log.d('ko-subs', 'GET $url failed: $e');
      return null;
    }
  }

  static String? _pageTitle(String page) {
    final m = RegExp(r'<meta[^>]+property="og:title"[^>]+content="([^"]*)"').firstMatch(page) ??
        RegExp(r'<title>([^<]*)</title>').firstMatch(page);
    final t = m?.group(1)?.trim();
    return t == null || t.isEmpty ? null : t;
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
  int seasonOfEntry(AnissiaAnime a) => seasonOf(a.subject) ?? seasonOf(a.originalSubject) ?? 1;
  bool japaneseMatches(AnissiaAnime a) => a.originalSubject.isNotEmpty && _norm(_stripSeason(a.originalSubject)) == base;

  // Korean names this show goes by: AniList synonyms, plus the Korean subject
  // of any season whose Japanese title matches. Older Anissia entries have no
  // Japanese title (e.g. "Re : 제로부터 시작하는 이세계 생활 2기", 2020), and are
  // matched through a sibling season's Korean name instead.
  final koreanBases = {
    for (final k in t.korean) _norm(_stripSeason(k)),
    for (final a in items)
      if (japaneseMatches(a) && !_isFilm(a.subject)) _norm(_stripSeason(a.subject)),
  };
  for (final a in items) {
    if (seasonOfEntry(a) != season || _isFilm(a.subject) != _isFilm(native)) continue;
    if (japaneseMatches(a) || koreanBases.contains(_norm(_stripSeason(a.subject)))) return a;
  }
  return null;
}

/// The fansubber's own name for the show, taken from a post title of a known
/// episode: "리제로2 25 - 오랜만에 보네요잉" (episode 25) gives "리제로2".
String? titlePrefix(String title, int ep) {
  final m = RegExp('(?<![0-9])0*$ep(?![0-9])').firstMatch(title);
  if (m == null) return null;
  final prefix = title.substring(0, m.start).replaceAll(RegExp(r'[\s\-#.:|\[\(]*(ep|e)?\.?\s*$', caseSensitive: false), '').trim();
  return _norm(prefix).length >= 2 ? prefix : null;
}

/// Whether [title] is `<prefix> <ep>` (any spacing, "EP", leading zeros).
bool prefixMatches(String title, String prefix, int ep) => RegExp(
      '${RegExp.escape(prefix)}\\s*[-#.:]?\\s*(?:ep\\.?|e)?\\s*0*$ep(?![0-9])',
      caseSensitive: false,
    ).hasMatch(title);

/// Post links and titles from a Tistory search page (`/search/<q>`): anchors
/// to `/<number>` with their text. Skins differ, so this stays generic.
List<({String title, String url})> parseTistorySearch(String page, String host) {
  final out = <({String title, String url})>[];
  final seen = <String>{};
  final re = RegExp(r'<a[^>]+href="(/\d+)"[^>]*>(.*?)</a>', dotAll: true);
  for (final m in re.allMatches(page)) {
    final text = m[2]!.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) continue;
    final url = 'https://$host${m[1]}';
    if (seen.add(url)) out.add((title: text, url: url));
  }
  return out;
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

