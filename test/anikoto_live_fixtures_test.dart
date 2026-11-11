// Parsers and extractors against real responses captured 2026-11-12
// (see test/fixtures/anikoto/live/README.md).
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/core/http.dart';
import 'package:oobleck/core/models.dart';
import 'package:oobleck/core/sources/anikoto/anikoto_parsers.dart';
import 'package:oobleck/core/sources/anikoto/anikoto_source.dart';
import 'package:oobleck/core/sources/extractors/megaplay.dart';
import 'package:oobleck/core/sources/extractors/megaplay_keys.dart';

import 'helpers/fixture_adapter.dart';

String live(String n) => FixtureAdapter.fixture('live/$n');

void main() {
  test('search', () {
    final r = parseSearch(live('search.json'));
    expect(r.length, greaterThanOrEqualTo(3));
    expect(r.first.title, 'Black Clover');
    expect(r.first.slug, 'black-clover-g7tjy');
    expect(r[1].slug, 'black-clover-season-2');
    expect(r.first.poster, startsWith('https://cdn.anipixcdn.co/thumbnail/'));
  });

  test('show page', () {
    final d = parseShow(live('watch.html'), 'https://anikototv.to/watch/black-clover-season-2');
    expect(d.siteId, '8839');
    expect(d.title, 'Black Clover Season 2');
    expect(d.synopsis, 'The second season of Black Clover.');
    expect(d.poster, 'https://cdn.anipixcdn.co/thumbnail/e7093313bd18aab07f36fbb18a54fdf7.jpg');
  });

  test('home has the main sections with cards', () {
    final h = parseHome(live('home.html'));
    expect(h.keys, containsAll(<String>['Latest Episode', 'Upcoming Anime', 'Top anime']));
    // Home cards link to episodes (/watch/<slug>/ep-7); they must map to distinct shows.
    final latest = h['Latest Episode']!;
    expect(latest.length, greaterThan(10));
    expect(latest.first.slug, 'umayuru-full-gate-41717');
    expect(latest.first.url, 'https://anikototv.to/watch/umayuru-full-gate-41717');
    expect(latest.first.title, 'Umayuru: Full Gate!');
    expect(latest.first.poster, startsWith('https://cdn.anipixcdn.co/thumbnail/'));
    for (final cards in h.values) {
      expect(cards, isNotEmpty);
      for (final c in cards) {
        expect(c.title, isNotEmpty);
        expect(c.slug, isNot(startsWith('ep-')));
        expect(c.url, 'https://anikototv.to/watch/${c.slug}');
      }
    }
  });

  test('slug and show url from episode links', () {
    expect(slugOf('https://anikototv.to/watch/black-clover-g7tjy/ep-3'), 'black-clover-g7tjy');
    expect(showUrlOf('https://anikototv.to/watch/black-clover-g7tjy/ep-3'),
        'https://anikototv.to/watch/black-clover-g7tjy');
    expect(slugOf('https://anikototv.to/watch/black-clover-season-2'), 'black-clover-season-2');
  });

  test('episodes', () {
    final eps = parseEpisodes(live('episodes.json'));
    expect(eps.length, 6);
    expect(eps.first.number, '1');
    expect(eps.first.title, 'Episode 1');
    expect(eps.first.malId, '61967');
    expect(eps.first.hasDub, isTrue);
    expect(eps.first.serverKey, isNotEmpty);
    expect(eps.map((e) => e.number), ['1', '2', '3', '4', '5', '6']);
  });

  test('servers', () {
    final s = parseServers(live('servers.json'));
    final sub = s.where((e) => e.type == AudioType.sub).map((e) => e.name).toList();
    expect(sub, ['HD-1', 'Vidstream-2', 'Vidstream-1', 'HD-2']);
    expect(s.where((e) => e.type == AudioType.dub), isNotEmpty);
  });

  test('embed url and skip data', () {
    final body = live('server_hd1.json');
    expect(parseEmbedUrl(body), 'https://megaplay.buzz/stream/s-2/181751/sub?s=tcdn');
    final skips = parseEmbedSkips(body);
    expect(skips.intro!.start, 256);
    expect(skips.intro!.end, 340);
    expect(skips.outro!.end, 1430);
    expect(parseEmbedSkips('{"result":{"url":"x","skip_data":{"intro":[0,0]}}}').intro, isNull);
    expect(parseEmbedSkips('not json').intro, isNull);
  });

  group('megaplay', () {
    final clock = DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true);

    for (final (name, embedUrl, embedFile) in [
      ('stream', 'https://megaplay.buzz/stream/s-2/181751/sub?s=tcdn', 'megaplay_embed.html'),
      ('videojs', 'https://megaplay.buzz/videojs/stream/s-2/181751/sub', 'megaplay_videojs_embed.html'),
    ]) {
      test('decrypts the live enc payload ($name embed)', () async {
        final a = FixtureAdapter({
          'megaplay.buzz/stream/getSources': live('getsources_enc.json'),
          'megaplay.buzz/': live(embedFile),
        });
        final m = MegaplayExtractor(buildDio(adapter: a), MegaplayKeys(), clock: () => clock);
        final s = await m.extract(embedUrl, serverName: 'HD-1', type: AudioType.sub);
        expect(s.url,
            startsWith('https://megap.shiora.top/e7093313bd18aab07f36fbb18a54fdf7/9d7db5a12bdf3d121b14c1bd0c0755f8/master.m3u8?token='));
        expect(s.subtitles.map((e) => e.label), ['English', 'Indonesian', 'Thai']);
        expect(s.intro!.start, 256);
        expect(s.outro!.start, 1348);
        final getSources = a.requests.firstWhere((r) => r.uri.path.contains('getSources'));
        expect(getSources.uri.queryParameters['id'], '180105');
        expect(getSources.uri.path, '/stream/getSources');
      });
    }
  });

  test('full chain on live captures', () async {
    final hd1 = live('server_hd1.json');
    final vs1 = live('server_vs1.json');
    final servers = parseServers(live('servers.json'));
    final hd1Link = servers.firstWhere((s) => s.name == 'HD-1' && s.type == AudioType.sub).linkId;
    final a = FixtureAdapter({
      'ajax/episode/list/8839': live('episodes.json'),
      'ajax/server/list': live('servers.json'),
      'ajax/server?get=': (RequestOptions o) => o.uri.queryParameters['get'] == hd1Link ? hd1 : vs1,
      '/watch/': live('watch.html'),
      'megaplay.buzz/stream/getSources': live('getsources_enc.json'),
      'megaplay.buzz/videojs/': live('megaplay_videojs_embed.html'),
      'megaplay.buzz/': live('megaplay_embed.html'),
    });
    final src = AnikotoSource(dio: buildDio(adapter: a))..enableKiwi = false;
    final show = await src.showDetail('black-clover-season-2');
    final eps = await src.episodes(show);
    final streams = await src.resolveStreams(eps.first, AudioType.sub).toList();
    expect(streams.map((s) => s.serverName).toSet(), {'HD-1', 'HD-2', 'Vidstream-1', 'Vidstream-2'});
    final best = await src.resolveBest(eps.first, AudioType.sub, grace: const Duration(milliseconds: 50));
    expect(best.serverName, 'HD-1');
    expect(best.intro!.end, 340);
  });
}
