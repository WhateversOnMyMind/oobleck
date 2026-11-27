// Pure HTML/JSON parsers for 11toon.com (Gnuboard). Selectors observed
// 2026-11-27. Kept free of I/O so they can be tested with fixtures.
import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../manga/manga_models.dart';
import '../source.dart';
import 'toon11_titles.dart';

/// Series covers live on a separate image host, keyed by series id. The
/// author-search JSON carries no cover, so the site's own script builds the
/// URL like this (observed 2026-11-27).
String toon11CoverUrl(String id) => 'https://11toon8.com/data/toon_category/$id.webp';

/// Resolves protocol-relative (`//host/x`), root-relative and `./board.php`
/// style links. Every page that links relatively lives under `/bbs/`.
String toon11Abs(String url, String base) => Uri.parse('$base/bbs/').resolve(url.trim()).toString();

String _clean(String? s) => (s ?? '').replaceAll(RegExp(r'[\s ]+'), ' ').trim();

final _cssUrl = RegExp(r'''url\(\s*['"]?([^'")]+)['"]?\s*\)''');

String? _background(Element? e, String base) {
  if (e == null) return null;
  final url = _cssUrl.firstMatch(e.attributes['style'] ?? '')?.group(1) ?? e.attributes['data-mobile-image'];
  return (url == null || url.trim().isEmpty) ? null : toon11Abs(url, base);
}

/// Text of [e] without the red `<font>` comment counter the site appends.
String _textWithoutCounter(Element? e) {
  if (e == null) return '';
  final copy = e.clone(true);
  for (final f in copy.querySelectorAll('font')) {
    f.remove();
  }
  return _clean(copy.text);
}

/// Cards of a listing or search page, in page order.
///
/// `ul.homelist > li[data-id]` (data-id = series id) with `.homelist-title span`,
/// `.homelist-thumb` (cover in the inline `background-image`) and
/// `.homelist-genre`, which holds genres plus a date and comment count on
/// "latest", genres plus a view count on the ranked lists, and the last update
/// time on search results. Ranked lists restart `.homelist-ranking` at 1 on
/// every page, so pass [rankOffset] for pages after the first.
List<MangaSummary> parseToon11Cards(String body, String base, {int rankOffset = 0}) {
  final out = <MangaSummary>[];
  final seen = <String>{};
  for (final li in html.parse(body).querySelectorAll('ul.homelist li[data-id]')) {
    final id = _clean(li.attributes['data-id']);
    var title = _clean(li.querySelector('.homelist-title span')?.text);
    if (title.isEmpty) title = _clean(li.attributes['data-title']);
    if (id.isEmpty || title.isEmpty || !seen.add(id)) continue;

    var info = _textWithoutCounter(li.querySelector('.homelist-genre'))
        .replaceFirst(RegExp(r'\s*\(\d+\)$'), '') // view count on ranked lists
        .replaceFirst(RegExp(r'\s\d{2}:\d{2}:\d{2}$'), ''); // time of day on search results
    final adult = RegExp(r'(^|[,\s])17($|[,\s])').hasMatch(info);
    final rank = int.tryParse(RegExp(r'\d+').firstMatch(li.querySelector('.homelist-ranking')?.text ?? '')?.group(0) ?? '');
    if (rank != null) info = info.isEmpty ? '${rank + rankOffset}위' : '${rank + rankOffset}위 · $info';

    out.add(MangaSummary(
      id: id,
      title: title,
      cover: _background(li.querySelector('.homelist-thumb'), base) ?? toon11CoverUrl(id),
      subtitle: info,
      // "17" is the site's 17+ genre tab; there is no other age marker on cards.
      adult: adult,
    ));
  }
  return out;
}

/// Last page number from Gnuboard's pager (`nav.pg_wrap`): the largest
/// `page=N` among `.pg_page` links (`.pg_end` points at the last page) and
/// `.pg_current`. 1 when the page has no pager.
int parseToon11LastPage(String body) {
  var last = 1;
  final nav = html.parse(body).querySelector('nav.pg_wrap');
  if (nav == null) return last;
  final current = int.tryParse(_clean(nav.querySelector('.pg_current')?.text));
  if (current != null && current > last) last = current;
  for (final a in nav.querySelectorAll('a.pg_page')) {
    final n = int.tryParse(RegExp(r'[?&]page=(\d+)').firstMatch(a.attributes['href'] ?? '')?.group(1) ?? '');
    if (n != null && n > last) last = n;
  }
  return last;
}

/// Author search (`/bbs/ajax.searchauthor.php`): `{"status":"success","list":
/// [{"wr_id","wr_subject","wr_6": author,"ca_name": genres,...}]}`, or
/// `{"status":"fail","list":[]}` when nothing matches.
List<MangaSummary> parseToon11AuthorSearch(String body) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    throw SourceException('11toon: unexpected author search response');
  }
  final list = json is Map ? json['list'] : null;
  if (list is! List) return const [];
  final out = <MangaSummary>[];
  for (final e in list.whereType<Map<dynamic, dynamic>>()) {
    final id = _clean(e['wr_id']?.toString());
    final title = _clean(e['wr_subject']?.toString());
    if (id.isEmpty || title.isEmpty) continue;
    final genres = _clean(e['ca_name']?.toString());
    out.add(MangaSummary(
      id: id,
      title: title,
      cover: toon11CoverUrl(id),
      subtitle: _clean(e['wr_6']?.toString()),
      adult: genres.split(',').map((g) => g.trim()).contains('17'),
    ));
  }
  return out;
}

/// "분류" (schedule) of a series -> status. Values seen 2026-11-27: 주간, 격주,
/// 월간, 격월/비정기, 연재중, 완결.
MangaStatus toon11Status(String schedule) {
  if (schedule.contains('완결')) return MangaStatus.completed;
  if (schedule.contains('휴재')) return MangaStatus.hiatus;
  if (RegExp('주간|격주|월간|격월|비정기|연재').hasMatch(schedule)) return MangaStatus.ongoing;
  return MangaStatus.unknown;
}

/// Series page (`board.php?bo_table=toons&is=<id>`): `h2.title`, `img.banner`
/// and label/value pairs `<span class="genre-subtitle">장르 : </span>
/// <span class="genre-link">…</span>` for 장르 (genres), 분류 (schedule),
/// 작가 (author) and 소개 (description). An unknown id still answers 200 with
/// all of these empty.
MangaDetail parseToon11Detail(String body, String id, String base) {
  final doc = html.parse(body);
  final title = _clean(doc.querySelector('h2.title')?.text);
  if (title.isEmpty) throw SourceException('11toon: series $id not found');

  final info = <String, String>{};
  for (final label in doc.querySelectorAll('span.genre-subtitle')) {
    final key = _clean(label.text).replaceAll(':', '').trim();
    info[key] = _clean(label.nextElementSibling?.text);
  }
  final cover = doc.querySelector('img.banner')?.attributes['src'];
  final schedule = info['분류'] ?? '';
  return MangaDetail(
    id: id,
    title: title,
    cover: (cover == null || cover.trim().isEmpty) ? toon11CoverUrl(id) : toon11Abs(cover, base),
    author: info['작가'] ?? '',
    genres: (info['장르'] ?? '').split(',').map((g) => g.trim()).where((g) => g.isNotEmpty).toList(),
    status: toon11Status(schedule),
    schedule: schedule,
    description: info['소개'] ?? '',
    url: '$base/bbs/board.php?bo_table=toons&is=$id',
  );
}

/// `.free-date` is `yy.MM.dd` ("26.11.23").
DateTime? parseToon11Date(String s) {
  final m = RegExp(r'(\d{2})\.(\d{1,2})\.(\d{1,2})').firstMatch(s);
  if (m == null) return null;
  final month = int.parse(m.group(2)!), day = int.parse(m.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime(2000 + int.parse(m.group(1)!), month, day);
}

/// One page of a series' chapter list, in page order (newest first).
///
/// `ul#comic-episode-list > li > button.episode` whose `onclick` navigates to
/// `./board.php?bo_table=toons&wr_id=<chapter id>&…`, with `.episode-title`,
/// `.free-date`, `.episode-banner` (thumbnail as inline background) and
/// `.list_hit` (views). 100 chapters per page.
List<ChapterInfo> parseToon11Chapters(String body, String mangaId, String seriesTitle, String base) {
  final out = <ChapterInfo>[];
  for (final b in html.parse(body).querySelectorAll('#comic-episode-list button.episode')) {
    final id = RegExp(r'wr_id=(\d+)').firstMatch(b.attributes['onclick'] ?? '')?.group(1);
    if (id == null) continue;
    final label = toon11ChapterLabel(b.querySelector('.episode-title')?.text ?? '', seriesTitle);
    out.add(ChapterInfo(
      id: id,
      mangaId: mangaId,
      title: label.isEmpty ? id : label,
      number: toon11ChapterNumber(label),
      uploaded: parseToon11Date(_textWithoutCounter(b.querySelector('.free-date'))),
      thumbnail: _background(b.querySelector('.episode-banner'), base),
      views: int.tryParse(_clean(b.querySelector('.list_hit')?.text).replaceAll(',', '')),
    ));
  }
  return out;
}

List<String>? _jsArray(String body, String name) {
  final m = RegExp('var\\s+$name\\s*=\\s*(\\[.*?\\])\\s*;', dotAll: true).firstMatch(body);
  if (m == null) return null;
  try {
    return (jsonDecode(m.group(1)!) as List).map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  } on FormatException {
    return null;
  }
}

/// Chapter page (`board.php?bo_table=toons&wr_id=<id>&is=<series>`): an inline
/// script defines `var img_list = ["//www.pl3040.com/kr/…png", …]` and
/// `var img_list_2 = [ the same paths on a mirror host ]`. The site's reader
/// falls back to the mirror entry at the same index when an image fails.
/// A removed chapter answers 200 with an `alert()` and no lists.
List<MangaPage> parseToon11Pages(String body, String base) {
  final main = _jsArray(body, 'img_list');
  if (main == null || main.isEmpty) throw SourceException('11toon: chapter has no images (removed?)');
  final mirror = _jsArray(body, 'img_list_2') ?? const <String>[];
  return [
    for (var i = 0; i < main.length; i++)
      MangaPage(i, toon11Abs(main[i], base), fallback: i < mirror.length ? toon11Abs(mirror[i], base) : null),
  ];
}
