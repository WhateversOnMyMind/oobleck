// Pure HTML/JSON parsers for anikototv.to. Selectors as documented in PLAN.md,
// observed 2026-11-11. Kept free of I/O so they can be tested with fixtures.
import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

import '../../models.dart';

const String anikotoBase = 'https://anikototv.to';

String absUrl(String href) {
  if (href.startsWith('http')) return href;
  if (href.startsWith('//')) return 'https:$href';
  return anikotoBase + (href.startsWith('/') ? href : '/$href');
}

/// Show slug from a show or episode URL. Home cards link to episodes
/// (`/watch/<slug>/ep-7`, observed 2026-11-12), so the slug is the segment
/// right after `watch`, not the last one.
String slugOf(String url) {
  final path = Uri.parse(url).path;
  final segs = path.split('/').where((s) => s.isNotEmpty).toList();
  final w = segs.indexOf('watch');
  if (w >= 0 && w + 1 < segs.length) return segs[w + 1];
  return segs.isEmpty ? url : segs.last;
}

/// Canonical show URL (`https://anikototv.to/watch/<slug>`) for any show or
/// episode URL on the site.
String showUrlOf(String url) {
  final u = Uri.parse(url);
  if (!u.path.contains('/watch/')) return url;
  return '$anikotoBase/watch/${slugOf(url)}';
}

String? _img(Element? scope) {
  final img = scope?.querySelector('img');
  if (img == null) return null;
  final src = img.attributes['data-src'] ?? img.attributes['src'];
  if (src == null || src.isEmpty) return null;
  return absUrl(src);
}

String _clean(String? s) => (s ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Extracts the HTML payload from `{ "result": "<html>" }` style responses
/// (also handles `{"result":{"html":"..."}}`).
String resultHtml(String body) {
  final j = jsonDecode(body);
  if (j is Map) {
    final r = j['result'];
    if (r is String) return r;
    if (r is Map && r['html'] is String) return r['html'] as String;
  }
  throw FormatException('Unexpected response shape: ${body.length > 120 ? body.substring(0, 120) : body}');
}

ShowSummary? _card(Element a) {
  final href = a.attributes['href'];
  if (href == null || !href.contains('/watch/')) return null;
  final url = showUrlOf(absUrl(href));
  final title = _clean(a.querySelector('.d-title, .name')?.text).isNotEmpty
      ? _clean(a.querySelector('.d-title, .name')?.text)
      : _clean(a.attributes['title'] ?? a.querySelector('img')?.attributes['alt'] ?? a.text);
  if (title.isEmpty) return null;
  return ShowSummary(
    slug: slugOf(url),
    title: title,
    url: url,
    poster: _img(a) ?? _img(a.parent),
    badge: () {
      final b = _clean(a.querySelector('.ep-status, .tick-sub, .tick-eps, .tick')?.text);
      return b.isEmpty ? null : b;
    }(),
  );
}

List<ShowSummary> parseSearch(String body) {
  final doc = html.parse(resultHtml(body));
  final out = <ShowSummary>[];
  final seen = <String>{};
  for (final a in doc.querySelectorAll('div.scaff.items > a, a[href*="/watch/"]')) {
    final c = _card(a);
    if (c != null && seen.add(c.slug)) out.add(c);
  }
  return out;
}

/// Home page: groups cards by their section (nearest section/widget with a
/// heading). Falls back to a single "Latest updates" group.
Map<String, List<ShowSummary>> parseHome(String page) {
  final doc = html.parse(page);
  final result = <String, List<ShowSummary>>{};
  final seenGlobal = <String>{};
  final containers = doc.querySelectorAll('section, div.widget, div.block');
  for (final c in containers) {
    final heading = _clean(c.querySelector('h1, h2, h3, .head .title, .title')?.text);
    if (heading.isEmpty) continue;
    final cards = <ShowSummary>[];
    final seen = <String>{};
    for (final a in c.querySelectorAll('a[href*="/watch/"]')) {
      final s = _card(a);
      if (s != null && seen.add(s.slug)) cards.add(s);
    }
    if (cards.length >= 3) {
      var key = heading;
      var n = 2;
      while (result.containsKey(key)) {
        key = '$heading $n';
        n++;
      }
      result[key] = cards;
      seenGlobal.addAll(seen);
    }
  }
  if (result.isEmpty) {
    final cards = <ShowSummary>[];
    final seen = <String>{};
    for (final a in doc.querySelectorAll('a[href*="/watch/"]')) {
      final s = _card(a);
      if (s != null && seen.add(s.slug)) cards.add(s);
    }
    if (cards.isNotEmpty) result['Latest updates'] = cards;
  }
  return result;
}

ShowDetail parseShow(String page, String url) {
  final doc = html.parse(page);
  final main = doc.querySelector('div#watch-main');
  final id = main?.attributes['data-id'];
  if (id == null || id.isEmpty) {
    throw FormatException('Show id not found (div#watch-main[data-id]) at $url');
  }
  String? meta(String prop) =>
      doc.querySelector('meta[property="$prop"]')?.attributes['content'];
  final title = _clean(doc.querySelector('h1.title, h1.d-title, h1')?.text).isNotEmpty
      ? _clean(doc.querySelector('h1.title, h1.d-title, h1')?.text)
      : _clean(meta('og:title')).replaceAll(RegExp(r'^Watch\s+|\s+(Online|English).*$'), '');
  final poster = _img(doc.querySelector('.binfo .poster, .poster, .binfo')) ?? meta('og:image');
  // Live page (2026-11-12): `.synopsis > .shorting > .content` plus a "[more]"
  // toggle, so read `.content` first to keep the toggle text out.
  final synEl = doc.querySelector('.synopsis .content') ??
      doc.querySelector('.synopsis, .desc, .content, .description');
  final synText = _clean(synEl?.text);
  final synopsis = synText.isNotEmpty ? synText : _clean(meta('og:description'));
  return ShowDetail(
    slug: slugOf(url),
    siteId: id,
    title: title,
    url: url,
    poster: poster == null ? null : absUrl(poster),
    synopsis: synopsis,
    malId: main?.attributes['data-mal'],
  );
}

List<EpisodeInfo> parseEpisodes(String body) {
  final doc = html.parse(resultHtml(body));
  final out = <EpisodeInfo>[];
  for (final li in doc.querySelectorAll('div.episodes ul li')) {
    final a = li.querySelector('a[data-ids]');
    if (a == null) continue;
    final num = a.attributes['data-num'] ?? '';
    final titleAttr = _clean(li.attributes['title'] ?? a.attributes['title']);
    out.add(EpisodeInfo(
      number: num,
      serverKey: a.attributes['data-ids']!,
      title: titleAttr,
      malId: a.attributes['data-mal'],
      hasDub: a.attributes['data-dub'] == '1',
      isFiller: li.classes.contains('filler') || a.classes.contains('filler'),
    ));
  }
  return out;
}

List<ServerOption> parseServers(String body) {
  final doc = html.parse(resultHtml(body));
  final out = <ServerOption>[];
  for (final t in doc.querySelectorAll('div.servers div.type')) {
    final type = t.attributes['data-type'] == 'dub' ? AudioType.dub : AudioType.sub;
    for (final li in t.querySelectorAll('ul li[data-link-id]')) {
      out.add(ServerOption(
        name: _clean(li.text),
        linkId: li.attributes['data-link-id']!,
        type: type,
      ));
    }
  }
  return out;
}

String parseEmbedUrl(String body) {
  final j = jsonDecode(body);
  final r = j is Map ? j['result'] : null;
  final url = r is Map ? r['url'] : (r is String ? r : null);
  if (url is! String || url.isEmpty) throw const FormatException('No embed url in response');
  return url;
}

/// Intro/outro seconds from `result.skip_data` of `/ajax/server?get=`
/// (`{"intro":[256,340],"outro":[1348,1430]}`, observed 2026-11-12).
/// Missing or empty (`[0,0]`) ranges come back as null.
({SkipRange? intro, SkipRange? outro}) parseEmbedSkips(String body) {
  SkipRange? range(Object? o) {
    if (o is List && o.length >= 2 && o[0] is num && o[1] is num) {
      final r = SkipRange((o[0] as num).toDouble(), (o[1] as num).toDouble());
      return r.end > r.start ? r : null;
    }
    return null;
  }

  try {
    final j = jsonDecode(body);
    final r = j is Map ? j['result'] : null;
    final skip = r is Map ? r['skip_data'] : null;
    if (skip is Map) return (intro: range(skip['intro']), outro: range(skip['outro']));
  } catch (_) {}
  return (intro: null, outro: null);
}
