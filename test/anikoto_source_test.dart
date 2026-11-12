import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:oobleck/core/http.dart';
import 'package:oobleck/core/models.dart';
import 'package:oobleck/core/sources/anikoto/anikoto_parsers.dart';
import 'package:oobleck/core/sources/anikoto/anikoto_source.dart';
import 'package:oobleck/core/sources/extractors/megaplay.dart';
import 'package:oobleck/core/sources/extractors/megaplay_keys.dart';
import 'package:oobleck/core/sources/extractors/vidtube.dart';

import 'helpers/fixture_adapter.dart';

String f(String n) => FixtureAdapter.fixture(n);

void main() {
  group('parsers', () {
    test('search', () {
      final r = parseSearch(f('search.json'));
      expect(r.map((e) => e.title), ['Black Clover Season 2', 'Black Clover']);
      expect(r.first.slug, 'black-clover-season-2');
      expect(r.first.poster, 'https://img.example/bc2.jpg');
      expect(r[1].poster, 'https://anikototv.to/img/bc.jpg');
    });

    test('show page', () {
      final d = parseShow(f('watch.html'), 'https://anikototv.to/watch/black-clover-season-2');
      expect(d.siteId, '8839');
      expect(d.title, 'Black Clover Season 2');
      expect(d.malId, '34572');
      expect(d.synopsis, contains('Wizard King'));
      expect(d.poster, 'https://img.example/bc2.jpg');
    });

    test('episodes', () {
      final eps = parseEpisodes(f('episodes.json'));
      expect(eps.length, 2);
      expect(eps[0].serverKey, 'abc123:1');
      expect(eps[0].hasDub, isTrue);
      expect(eps[0].title, 'The Boy Who Wants To Be');
      expect(eps[1].isFiller, isTrue);
      expect(eps[1].hasDub, isFalse);
    });

    test('servers', () {
      final s = parseServers(f('servers.json'));
      expect(s.length, 4);
      expect(s.where((e) => e.type == AudioType.dub).single.linkId, 'L-hd1-dub');
    });

    test('home falls back to a single section', () {
      final h = parseHome('<a href="/watch/a"><img src="/a.jpg"><span class="d-title">A</span></a>');
      expect(h['Latest updates']!.single.slug, 'a');
    });
  });

  group('megaplay', () {
    final fixedClock = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true);

    MegaplayExtractor make([FixtureAdapter? a]) =>
        MegaplayExtractor(buildDio(adapter: a ?? FixtureAdapter({})), MegaplayKeys(), clock: () => fixedClock);

    test('encrypt/decrypt round trip with known key and IV', () {
      final m = make();
      const plain = '{"file":"https://x/y.m3u8"}';
      expect(m.decrypt(m.encrypt(plain)), plain);
    });

    test('decrypt tolerates padded base64url', () {
      final m = make();
      final e = m.encrypt('hello world');
      expect(m.decrypt(e.padRight(e.length + (4 - e.length % 4) % 4, '=')), 'hello world');
    });

    test('url signing is deterministic', () {
      final m = make();
      const url = 'https://cdn.example/hls/0123456789ABCDEF0123456789abcdef/fedcba9876543210fedcba9876543210/master.m3u8';
      final signed = m.signUrl(url);
      final token = Uri.parse(signed).queryParameters['token']!;
      final parts = token.split('.');
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[0])));
      expect(payload,
          '${1700000090}|0123456789abcdef0123456789abcdef/fedcba9876543210fedcba9876543210');
      expect(parts[1].length, 43); // sha256, unpadded
      expect(m.signUrl(url), signed);
      // re-signing replaces the token instead of stacking, and leaves the path alone
      final again = m.signUrl(signed);
      expect('token='.allMatches(again).length, 1);
      expect(again, signed);
      expect(again, startsWith('$url?token='));
      expect(again, isNot(contains(r'$')));
    });

    test('re-signing keeps other query parameters', () {
      final m = make();
      const url = 'https://cdn.example/0123456789abcdef0123456789abcdef/fedcba9876543210fedcba9876543210/seg.ts?a=1';
      final once = m.signUrl(url);
      expect(once, startsWith('$url&token='));
      final twice = m.signUrl(once.replaceFirst('?a=1&', '?a=1&b=2&'));
      expect(twice, startsWith('https://cdn.example/0123456789abcdef0123456789abcdef/fedcba9876543210/seg.ts?a=1&b=2&token='.replaceFirst('fedcba9876543210/seg', 'fedcba9876543210fedcba9876543210/seg')));
      expect('token='.allMatches(twice).length, 1);
    });

    test('urls without hex pair are untouched', () {
      expect(make().signUrl('https://cdn.example/a/b/master.m3u8'), 'https://cdn.example/a/b/master.m3u8');
    });

    test('extract plain sources keeps all tracks', () async {
      final a = FixtureAdapter({
        '/stream/getSources': f('getsources_plain.json'),
        'megaplay.buzz/stream/s-2': f('megaplay_embed.html'),
      });
      final s = await make(a).extract('https://megaplay.buzz/stream/s-2/181751/sub?s=tcdn',
          serverName: 'HD-1', type: AudioType.sub);
      expect(s.url, contains('token='));
      expect(s.subtitles.map((e) => e.label), ['English', 'Korean']);
      expect(s.intro!.end, 95);
      expect(s.headers['Referer'], 'https://megaplay.buzz/');
      expect(a.requests.first.headers['Referer'], 'https://anikototv.to/');
    });

    test('extract encrypted sources', () async {
      final m = make();
      final encBody = jsonEncode({
        'enc': m.encrypt(jsonEncode({'file': 'https://cdn.example/plain/master.m3u8'})),
        'tracks': [
          {'file': 'https://s/ko.vtt', 'label': 'Korean', 'kind': 'captions'}
        ]
      });
      final a = FixtureAdapter({
        '/stream/getSources': encBody,
        'megaplay.buzz/stream/s-2': f('megaplay_embed.html'),
      });
      final s = await make(a).extract('https://megaplay.buzz/stream/s-2/1/sub',
          serverName: 'HD-2', type: AudioType.sub);
      expect(s.url, 'https://cdn.example/plain/master.m3u8');
      expect(s.subtitles.single.language, 'ko');
    });

    test('vidtube decodes megaplay-style enc payloads', () async {
      final m = make();
      final encBody = jsonEncode({
        'enc': m.encrypt(jsonEncode({'file': 'https://cdn.example/vt/master.m3u8'})),
        'tracks': <Object>[],
      });
      final a = FixtureAdapter({
        'vidtube.site/stream/getSourcesNew': encBody,
        'vidtube.site/stream/s-2': f('megaplay_embed.html'),
      });
      final s = await VidtubeExtractor(buildDio(adapter: a), m)
          .extract('https://vidtube.site/stream/s-2/555/sub', serverName: 'VidPlay', type: AudioType.sub);
      expect(s.url, 'https://cdn.example/vt/master.m3u8');
    });

    test('key refresh from script', () {
      final k = MegaplayKeys();
      expect(k.applyFromScript('var cfg={key:"0123456789abcdef0123456789abcdef", iv:"ABCDEFGHIJKLMNOP"};'), isTrue);
      expect(k.aesKey, '0123456789abcdef0123456789abcdef');
      expect(k.iv, 'ABCDEFGHIJKLMNOP');
      expect(k.tokenKey, MegaplayKeys.defaultTokenKey);
      expect(k.applyFromScript('nothing here'), isFalse);
    });

    test('aes key is zero padded to 32 bytes', () {
      final b = MegaplayKeys().aesKeyBytes;
      expect(b.length, 32);
      expect(b.sublist(16), List.filled(16, 0));
    });
  });

  group('AnikotoSource end to end (fixtures)', () {
    AnikotoSource make() {
      final a = FixtureAdapter({
        'ajax/anime/search': f('search.json'),
        '/watch/': f('watch.html'),
        'ajax/episode/list/8839': f('episodes.json'),
        'ajax/server/list': f('servers.json'),
        'ajax/server?get=L-hd1-sub': f('server_hd1.json'),
        'ajax/server?get=L-vs1-sub': f('server_vs1.json'),
        'ajax/server?get=L-hd2-sub': (RequestOptions _) => throw StateError('boom'),
        'megaplay.buzz/stream/getSources': f('getsources_plain.json'),
        'megaplay.buzz/stream/s-2': f('megaplay_embed.html'),
        'vidtube.site/stream/getSourcesNew': f('vidtube_sources.json'),
        'vidtube.site/stream/s-2': f('megaplay_embed.html'),
        'mapper.nekostream': '{"Kiwi-Stream-":{"sub":{"url":"https://kiwi.example/m.m3u8"}}}',
      });
      return AnikotoSource(dio: buildDio(adapter: a))..enableKiwi = true;
    }

    test('full chain', () async {
      final src = make();
      final show = await src.showDetail('black-clover-season-2');
      final eps = await src.episodes(show);
      expect(eps.length, 2);
      final streams = await src.resolveStreams(eps.first, AudioType.sub).toList();
      expect(streams.map((s) => s.serverName).toSet(), {'HD-1', 'Vidstream-1', 'Kiwi'});
      final best = await src.resolveBest(eps.first, AudioType.sub, grace: const Duration(milliseconds: 50));
      expect(best.serverName, 'HD-1');
    });
  });
}
