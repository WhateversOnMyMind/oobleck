import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/app/providers.dart';
import 'package:oobleck/core/sources/toon11/toon11_address.dart';
import 'package:oobleck/core/sources/toon11/toon11_source.dart';
import 'package:oobleck/core/storage/app_db.dart';
import 'package:oobleck/features/manga/manga_providers.dart';

/// A short stand-in for the Namuwiki article: the info box link (same markup
/// as observed 2026-11-27), plus an image host and unrelated links.
const namuPage = '''
<td><div><strong>링크</strong></div></td><td style='text-align:left;'><div>
<a class='WUh1ki3o' href='http://103.204.13.68:8904/bbs/board.php?bo_table=toon_c&amp;type=upd' target='_blank'
 title='http://103.204.13.68:8904/bbs/board.php?bo_table=toon_c&amp;type=upd'>링크</a></div></td>
<img src="https://11toon8.com/data/logo.png"> <a href="https://namu.wiki/w/Other">x</a>
<a href="https://policies.google.com/privacy">privacy</a>
''';

final listing = File('test/fixtures/toon11/latest_p1.html').readAsStringSync();

/// Answers by host: [up] hosts serve the listing, the Namuwiki host serves
/// [namu], everything else fails like a blocked network.
class HostAdapter implements HttpClientAdapter {
  HostAdapter({required this.up, this.namu = namuPage});
  final Set<String> up;
  final String namu;
  final hits = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final origin = '${o.uri.scheme}://${o.uri.host}${o.uri.hasPort && o.uri.port != 80 && o.uri.port != 443 ? ':${o.uri.port}' : ''}';
    hits.add(origin);
    if (o.uri.host == 'namu.wiki') return ResponseBody.fromString(namu, 200);
    if (up.contains(origin)) return ResponseBody.fromString(listing, 200);
    throw DioException.connectionError(requestOptions: o, reason: 'reset', error: const SocketException('Connection reset by peer'));
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('addresses are read from the article, image hosts included but checked later', () {
    expect(parseToon11Addresses(namuPage), ['http://103.204.13.68:8904', 'https://11toon8.com']);
    expect(parseToon11Addresses('<a href="https://11toon55.net/">x</a> https://11toon55.net/bbs'), ['https://11toon55.net']);
    expect(parseToon11Addresses('<a href="https://example.com/11toon">x</a>'), isEmpty);
    expect(looksLikeToon11(listing), isTrue);
    expect(looksLikeToon11('<title>Parked domain</title>'), isFalse);
  });

  test('the finder skips dead and wrong addresses', () async {
    final a = HostAdapter(up: {'http://103.204.13.68:8904'});
    final finder = Toon11AddressFinder(Dio()..httpClientAdapter = a);
    expect(await finder.find(tryFirst: [Toon11Source.defaultBaseUrl]), 'http://103.204.13.68:8904');
    expect(a.hits, ['https://11toon.com', 'https://namu.wiki', 'http://103.204.13.68:8904']);
    expect(await Toon11AddressFinder(Dio()..httpClientAdapter = HostAdapter(up: {})).find(), isNull);
  });

  group('in the app', () {
    late Directory dir;
    late AppDb db;
    setUp(() async {
      dir = Directory.systemTemp.createTempSync('toon11_address');
      db = await AppDb.open(dir.path);
    });
    tearDown(() async {
      await db.close();
      dir.deleteSync(recursive: true);
    });

    ProviderContainer make(HostAdapter a) => ProviderContainer(overrides: [
          dbProvider.overrideWithValue(db),
          dioProvider.overrideWithValue(Dio()..httpClientAdapter = a),
        ]);

    test('Browse switches to the found address and loads there', () async {
      final c = make(HostAdapter(up: {'http://103.204.13.68:8904'}));
      addTearDown(c.dispose);
      const q = ListingQuery(catalog: 'latest');
      final sub = c.listen(listingProvider(q), (_, _) {});
      addTearDown(sub.close);
      for (var i = 0; i < 50 && c.read(listingProvider(q)).items.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(c.read(listingProvider(q)).items, hasLength(35));
      expect(c.read(mangaSiteAddressProvider), 'http://103.204.13.68:8904');
      expect(db.setting<String>(mangaFoundUrlKey), 'http://103.204.13.68:8904', reason: 'remembered for next launch');
    });

    test('an address typed in Settings is left alone, and bare IPs get http', () async {
      final c = make(HostAdapter(up: {'http://103.204.13.68:8904'}));
      addTearDown(c.dispose);
      await c.read(mangaBaseUrlProvider.notifier).set('5.6.7.8:9000');
      expect(c.read(mangaSiteAddressProvider), 'http://5.6.7.8:9000');
      expect(await c.read(mangaSiteFinderProvider).recover(), isNull);
      expect(await c.read(mangaSiteFinderProvider).recover(fromSettings: true), 'http://103.204.13.68:8904');
      expect(c.read(mangaBaseUrlProvider), isNull, reason: 'finding from Settings clears the typed address');
      expect(c.read(mangaSiteAddressProvider), 'http://103.204.13.68:8904');
    });
  });
}
