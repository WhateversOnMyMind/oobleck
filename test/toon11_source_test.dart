// Parsers and source against pages saved from 11toon.com on 2026-11-27
// (see test/fixtures/toon11/README.md).
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/core/http.dart';
import 'package:oobleck/core/manga/manga_models.dart';
import 'package:oobleck/core/sources/source.dart';
import 'package:oobleck/core/sources/toon11/toon11_parsers.dart';
import 'package:oobleck/core/sources/toon11/toon11_source.dart';
import 'package:oobleck/core/sources/toon11/toon11_titles.dart';

import 'helpers/fixture_adapter.dart';

const base = 'https://11toon.com';

String f(String n) => File('test/fixtures/toon11/$n').readAsStringSync();

/// Routes by path and query so the tests can also assert what was requested.
FixtureAdapter site(String Function(Uri uri) board, {String search = 'search_onepiece.html', String author = 'author_none.json'}) {
  return FixtureAdapter({
    '/bbs/board.php': (RequestOptions o) => board(o.uri),
    '/bbs/search_stx.php': f(search),
    '/bbs/ajax.searchauthor.php': f(author),
  });
}

Toon11Source source(FixtureAdapter adapter, {String baseUrl = base}) =>
    Toon11Source(dio: buildDio(adapter: adapter), baseUrl: baseUrl);

void main() {
  group('listing parser', () {
    test('latest updates: cards, covers, subtitle, pager', () {
      final body = f('latest_p1.html');
      final cards = parseToon11Cards(body, base);
      expect(cards.length, 35);
      expect(cards.first.id, '37841');
      expect(cards.first.title, '즐거운 음악');
      expect(cards.first.cover, 'https://11toon8.com/data/toon_category/37841.webp');
      expect(cards.first.subtitle, '학원, 밴드, 러브 코미디 11.27');
      expect(cards.map((c) => c.id).toSet().length, 35);
      expect(parseToon11LastPage(body), 491);
    });

    test('last page of latest has no "end" link', () {
      final body = f('latest_last.html');
      expect(parseToon11Cards(body, base).length, 4);
      expect(parseToon11LastPage(body), 491);
    });

    test('ranked list: rank in subtitle, view count dropped', () {
      final cards = parseToon11Cards(f('popular_p1.html'), base);
      expect(cards.length, 101);
      expect(cards.first.id, '1');
      expect(cards.first.title, '열혈강호');
      expect(cards.first.subtitle, '1위 · 무협');
      expect(cards.last.subtitle, startsWith('101위'));
      expect(parseToon11LastPage(f('popular_p1.html')), 1);
    });

    test('ranked list page 2 continues the ranking with an offset', () {
      final cards = parseToon11Cards(f('popular_p2.html'), base, rankOffset: 101);
      expect(cards.length, 32);
      expect(cards.first.subtitle, startsWith('102위'));
      expect(cards.last.subtitle, startsWith('133위'));
    });

    test('daily picks: genre text is tidied, 17+ flagged', () {
      final cards = parseToon11Cards(f('recommended.html'), base);
      expect(cards.length, 100);
      expect(cards.first.id, '22298');
      expect(cards.first.subtitle, 'BL');
      expect(cards.first.adult, isFalse);
      expect(cards.firstWhere((c) => c.id == '20977').adult, isTrue);
    });

    test('search results: id, title without stray newline, date subtitle', () {
      final cards = parseToon11Cards(f('search_onepiece.html'), base);
      expect(cards.map((c) => c.id), ['34801', '2', '24969', '34228']);
      expect(cards[1].title, '원피스(ONE PIECE)');
      expect(cards[1].cover, 'https://11toon8.com/data/toon_category/2.webp');
      expect(cards[1].subtitle, '2026-11-23');
      expect(cards[2].title, '원피스 episode A(에이스)');
    });

    test('no results', () {
      expect(parseToon11Cards(f('search_none.html'), base), isEmpty);
      expect(parseToon11AuthorSearch(f('author_none.json')), isEmpty);
    });

    test('author search JSON', () {
      final r = parseToon11AuthorSearch(f('author_oda.json'));
      expect(r.length, 43);
      expect(r.first.id, '20947');
      expect(r.first.title, '다이쇼 로맨티카');
      expect(r.first.subtitle, '오다와라 미즈에');
      expect(r.first.cover, 'https://11toon8.com/data/toon_category/20947.webp');
      expect(() => parseToon11AuthorSearch('<html>'), throwsA(isA<SourceException>()));
    });
  });

  group('series parser', () {
    test('detail', () {
      final d = parseToon11Detail(f('series_2_p1.html'), '2', base);
      expect(d.title, '원피스(ONE PIECE)');
      expect(d.cover, 'https://11toon8.com/data/toon_category/2.webp');
      expect(d.author, '오다 에이이치로');
      expect(d.genres, ['애니화', '액션', '판타지']);
      expect(d.schedule, '주간');
      expect(d.status, MangaStatus.ongoing);
      expect(d.description, startsWith('표면 대부분이 바다인 행성을'));
      expect(d.url, 'https://11toon.com/bbs/board.php?bo_table=toons&is=2');
    });

    test('completed series', () {
      final d = parseToon11Detail(f('series_10394.html'), '10394', base);
      expect(d.title, '젤다의 전설 -황혼의 공주-');
      expect(d.status, MangaStatus.completed);
    });

    test('schedule to status', () {
      expect(toon11Status('주간'), MangaStatus.ongoing);
      expect(toon11Status('격월/비정기'), MangaStatus.ongoing);
      expect(toon11Status('연재중'), MangaStatus.ongoing);
      expect(toon11Status('완결'), MangaStatus.completed);
      expect(toon11Status('휴재'), MangaStatus.hiatus);
      expect(toon11Status(''), MangaStatus.unknown);
    });

    test('unknown series id', () {
      expect(() => parseToon11Detail(f('series_missing.html'), '99999999', base), throwsA(isA<SourceException>()));
    });

    test('chapters of one list page, newest first', () {
      final body = f('series_2_p1.html');
      final ch = parseToon11Chapters(body, '2', '원피스(ONE PIECE)', base);
      expect(ch.length, 100);
      expect(parseToon11LastPage(body), 14);
      final c = ch.first;
      expect(c.id, '1834578');
      expect(c.mangaId, '2');
      expect(c.title, '1199화');
      expect(c.number, 1199);
      expect(c.uploaded, DateTime(2026, 11, 23));
      expect(c.thumbnail, 'https://11toon7.com/03/1834578.webp');
      expect(c.views, greaterThan(50000));
      expect(ch.every((c) => !c.title.contains('원피스')), isTrue);
    });

    test('oldest page: extras keep their names, no number', () {
      final ch = parseToon11Chapters(f('series_2_p14.html'), '2', '원피스(ONE PIECE)', base);
      expect(ch.length, 9);
      expect(ch.last.title, '원피스x토리코 콜라보');
      expect(ch.last.number, isNull);
      expect(ch.map((c) => c.title), containsAll(<String>['RED', 'WANTED', '캐릭터 초기 구상']));
    });

    test('volumes and chapters with a title cut in the middle', () {
      final ch = parseToon11Chapters(f('series_10394.html'), '10394', '젤다의 전설 -황혼의 공주-', base);
      expect(ch.length, 27);
      expect(ch.first.title, '11권');
      expect(ch.first.number, 11);
      final labels = ch.map((c) => c.title).toList();
      expect(labels, containsAll(<String>['9권', '16화', '9화']));
      expect(labels.where((l) => l.contains('젤다') || l.contains('…')), isEmpty);
    });

    test('side stories, specials and half chapters', () {
      final ch = parseToon11Chapters(f('series_3737_p1.html'), '3737', '귀멸의 칼날', base);
      final byLabel = {for (final c in ch) c.title: c};
      expect(byLabel.keys, containsAll(<String>['특별단편', '탄지로의 근황보고서', '205.5화', '205화', '134화']));
      expect(byLabel['205.5화']!.number, 205.5);
      expect(byLabel['205화']!.number, 205);
      expect(byLabel['특별단편']!.number, isNull);
      expect(byLabel['렌고쿠…로 외전 2-2화']!.number, 2.2);
      expect(ch.where((c) => c.title.startsWith('귀멸의 칼날')), isEmpty);
    });

    test('decimal volumes, "(완)" and untranslated markers', () {
      final ch = parseToon11Chapters(f('series_19.html'), '19', '한마바키', base);
      final byLabel = {for (final c in ch) c.title: c};
      expect(byLabel['312화(완)']!.number, 312);
      expect(byLabel['299-300화']!.number, 299);
      expect(byLabel['283화 미번역']!.number, 283);
      expect(byLabel['10.5권']!.number, 10.5);
      expect(byLabel['24권']!.number, 24);
    });

    test('long series name spelled several ways', () {
      const title = '전(前) 세계1위의 서브캐 육성일기~폐플레이어 이세계를 공략중!~';
      final ch = parseToon11Chapters(f('series_8158.html'), '8158', title, base);
      expect(ch.length, 94);
      expect(ch.first.title, '94화');
      final labels = ch.map((c) => c.title).toSet();
      expect(labels, containsAll(<String>['79화', '17화', '9화', '3화']));
      expect(ch.every((c) => c.number != null), isTrue);
    });

    test('bare numbers and named specials', () {
      final ch = parseToon11Chapters(f('series_34801.html'), '34801', '원피스 학원', base);
      final byLabel = {for (final c in ch) c.title: c};
      expect(byLabel['49화']!.number, 49);
      expect(byLabel['38-2화']!.number, 38.2);
      expect(byLabel['36']!.number, 36);
      expect(byLabel['출장판']!.number, isNull);
      expect(byLabel['특별편']!.number, isNull);
    });
  });

  group('chapter titles', () {
    test('label', () {
      expect(toon11ChapterLabel('원피스(ONE PI…CE) 1199화', '원피스(ONE PIECE)'), '1199화');
      expect(toon11ChapterLabel('원피스 1화', '원피스(ONE PIECE)'), '1화');
      expect(toon11ChapterLabel('원피스 episod…에이스) 4-2화', '원피스 episode A(에이스)'), '4-2화');
      expect(toon11ChapterLabel('귀멸의 칼날 귀멸의 칼날 134화', '귀멸의 칼날'), '134화');
      expect(toon11ChapterLabel('귀멸의 칼날205화', '귀멸의 칼날'), '205화');
      expect(toon11ChapterLabel('바키 외전 스카페이스 5권', '바키 외전'), '스카페이스 5권');
      expect(toon11ChapterLabel('원펀맨 리메이크 34권 번외편', '원펀맨 리메이크'), '34권 번외편');
      expect(toon11ChapterLabel('백랑 [단편]', '백랑'), '[단편]');
      expect(toon11ChapterLabel('어떤 작품 1부 에필로그', '어떤 작품'), '1부 에필로그');
      expect(toon11ChapterLabel('어떤 작품 외전 3화', '어떤 작품'), '외전 3화');
      expect(toon11ChapterLabel('어떤 작품 - 후기', '어떤 작품'), '후기');
      expect(toon11ChapterLabel('전 세계 1위의 서…육성 일기 79화', '전(前) 세계1위의 서브캐 육성일기'), '79화');
    });

    test('label falls back to the full text', () {
      expect(toon11ChapterLabel('백랑', '백랑'), '백랑');
      expect(toon11ChapterLabel('전혀 다른 제목', '백랑'), '전혀 다른 제목');
      expect(toon11ChapterLabel('(ONE PIECE…스x토리코 콜라보', '원피스(ONE PIECE)'), '(ONE PIECE…스x토리코 콜라보');
      expect(toon11ChapterLabel('  3화 ', ''), '3화');
    });

    test('number', () {
      expect(toon11ChapterNumber('1199화'), 1199);
      expect(toon11ChapterNumber('12.5화'), 12.5);
      expect(toon11ChapterNumber('제 3화'), 3);
      expect(toon11ChapterNumber('3권'), 3);
      expect(toon11ChapterNumber('외전 3화'), 3);
      expect(toon11ChapterNumber('34권 번외편'), 34);
      expect(toon11ChapterNumber('2권 15화'), 15);
      expect(toon11ChapterNumber('262-2화'), 262.2);
      expect(toon11ChapterNumber('1-2화'), 1.2);
      expect(toon11ChapterNumber('729'), 729);
      expect(toon11ChapterNumber('1부 에필로그'), isNull);
      expect(toon11ChapterNumber('특별편'), isNull);
    });

    test('date', () {
      expect(parseToon11Date('26.11.23'), DateTime(2026, 11, 23));
      expect(parseToon11Date('16.10.01'), DateTime(2016, 10, 1));
      expect(parseToon11Date(''), isNull);
      expect(parseToon11Date('26.13.40'), isNull);
    });
  });

  group('chapter page parser', () {
    test('images with the mirror as fallback', () {
      final p = parseToon11Pages(f('chapter_1834578.html'), base);
      expect(p.length, 12);
      expect(p.first.index, 0);
      expect(p.first.url, 'https://www.pl3040.com/kr/03/2/1834578/182723_680d372c43e5.png');
      expect(p.first.fallback, 'https://www.pl4050.com/kr/03/2/1834578/182723_680d372c43e5.png?v=ei');
      expect(p.last.index, 11);
      expect(p.every((e) => e.fallback != null && e.fallback != e.url), isTrue);
    });

    test('removed chapter', () {
      expect(() => parseToon11Pages(f('chapter_missing.html'), base), throwsA(isA<SourceException>()));
    });

    test('no mirror list', () {
      final p = parseToon11Pages('<script>var img_list = ["/data/a.jpg","b.jpg"];</script>', 'https://x.test');
      expect(p.map((e) => e.url), ['https://x.test/data/a.jpg', 'https://x.test/bbs/b.jpg']);
      expect(p.first.fallback, isNull);
    });
  });

  group('source', () {
    test('identity, catalogs and genres', () {
      final s = source(site((_) => ''), baseUrl: 'https://11toon.example/');
      expect(s.id, 'toon11');
      expect(s.name, '11toon');
      expect(s.baseUrl, 'https://11toon.example');
      expect(s.imageHeaders['Referer'], 'https://11toon.example/');
      expect(s.mangaUrl('2'), 'https://11toon.example/bbs/board.php?bo_table=toons&is=2');
      expect(s.catalogs.map((c) => c.id), ['latest', 'popular', 'completed', 'recommended']);
      expect(s.catalogs.where((c) => c.supportsGenres).map((c) => c.id), ['latest', 'popular', 'completed']);
      expect(s.catalogs.last.paged, isFalse);
      expect(s.genres.map((g) => g.value).toSet().length, s.genres.length);
      expect(s.genres.firstWhere((g) => g.label == '일상+치유').value, '일상 치유');
    });

    test('latest: request shape and paging', () async {
      final a = site((u) => f(u.queryParameters['page'] == '491' ? 'latest_last.html' : 'latest_p1.html'));
      final s = source(a);
      final first = await s.browse('latest', genres: {'SF', '학원'});
      expect(first.items.length, 35);
      expect(first.hasNext, isTrue);
      final q = a.requests.single.uri.queryParameters;
      expect(a.requests.single.uri.path, '/bbs/board.php');
      expect(q, {'bo_table': 'toon_c', 'type': 'upd', 'sca': 'SF||학원'});
      expect(a.requests.single.headers['Referer'], 'https://11toon.com/');

      final last = await s.browse('latest', page: 491);
      expect(last.items.length, 4);
      expect(last.hasNext, isFalse);
      expect(a.requests.last.uri.queryParameters, {'bo_table': 'toon_c', 'type': 'upd', 'page': '491'});
    });

    test('popular and completed: 101 cards then 32 per page', () async {
      final a = site((u) => f(u.queryParameters.containsKey('page') ? 'popular_p2.html' : 'popular_p1.html'));
      final s = source(a);
      final p1 = await s.browse('popular');
      expect(p1.items.length, 101);
      expect(p1.hasNext, isTrue);
      expect(a.requests.last.uri.queryParameters, {'bo_table': 'toon_c', 'is_over': '0'});

      final p3 = await s.browse('popular', page: 3, genres: {'판타지'});
      expect(p3.hasNext, isTrue);
      expect(p3.items.first.subtitle, startsWith('134위'));
      expect(a.requests.last.uri.queryParameters, {'bo_table': 'toon_c', 'is_over': '0', 'sca': '판타지', 'page': '3'});

      await s.browse('completed');
      expect(a.requests.last.uri.queryParameters, {'bo_table': 'toon_c', 'is_over': '1'});
    });

    test('a short ranked page is the last one', () async {
      final s = source(site((_) => f('latest_last.html')));
      expect((await s.browse('popular', page: 2)).hasNext, isFalse);
    });

    test('daily picks: single page, genres ignored', () async {
      final a = site((_) => f('recommended.html'));
      final s = source(a);
      final r = await s.browse('recommended', genres: {'SF'});
      expect(r.items.length, 100);
      expect(r.hasNext, isFalse);
      expect(a.requests.single.uri.queryParameters, {'bo_table': 'toon_c', 'type': 'today'});
      expect((await s.browse('recommended', page: 2)).items, isEmpty);
      expect(a.requests.length, 1);
    });

    test('unknown catalog', () {
      expect(() => source(site((_) => '')).browse('nope'), throwsA(isA<SourceException>()));
    });

    test('search merges title and author matches, title first, no repeats', () async {
      // One Piece (id 2) is in both: by title and by its author 오다 에이이치로.
      final a = FixtureAdapter({
        '/bbs/search_stx.php': f('search_onepiece.html'),
        '/bbs/ajax.searchauthor.php': f('author_oda.json'),
      });
      final r = await source(a).search(' 원피스 ');
      expect(r.items.take(4).map((m) => m.id), ['34801', '2', '24969', '34228']);
      expect(r.items.length, 4 + 43 - 1);
      expect(r.items.where((m) => m.id == '2').single.title, '원피스(ONE PIECE)');
      expect(r.items[4].subtitle, '오다와라 미즈에');
      expect(r.hasNext, isFalse);
      final byPath = {for (final q in a.requests) q.uri.path: q.uri.queryParameters};
      expect(byPath['/bbs/search_stx.php'], {'stx': '원피스'});
      expect(byPath['/bbs/ajax.searchauthor.php'], {'search_key': '원피스'});
    });

    test('search survives a failing author endpoint; blank query and page 2 are empty', () async {
      final a = FixtureAdapter({'/bbs/search_stx.php': f('search_onepiece.html')});
      final s = source(a);
      expect((await s.search('원피스')).items.length, 4);
      final before = a.requests.length;
      expect((await s.search('  ')).items, isEmpty);
      expect((await s.search('원피스', page: 2)).items, isEmpty);
      expect(a.requests.length, before);
    });

    test('fetch reads every chapter page, drops repeats, returns oldest first', () async {
      var active = 0, peak = 0;
      final a = FixtureAdapter({
        '/bbs/board.php': (RequestOptions o) {
          final page = o.uri.queryParameters['page'];
          return f(page == null ? 'series_2_p1.html' : 'series_2_p14.html');
        },
      });
      final dio = buildDio(adapter: a)
        ..interceptors.add(InterceptorsWrapper(
          onRequest: (o, h) async {
            peak = ++active > peak ? active : peak;
            await Future<void>.delayed(const Duration(milliseconds: 5));
            h.next(o);
          },
          onResponse: (r, h) {
            active--;
            h.next(r);
          },
        ));
      final b = await Toon11Source(dio: dio).fetch('2');

      expect(b.detail.title, '원피스(ONE PIECE)');
      expect(a.requests.length, 14);
      expect(a.requests.first.uri.queryParameters, {'bo_table': 'toons', 'is': '2'});
      expect(a.requests.map((r) => r.uri.queryParameters['page']).whereType<String>().toSet(),
          {for (var p = 2; p <= 14; p++) '$p'});
      expect(peak, lessThanOrEqualTo(Toon11Source.chapterListConcurrency));
      expect(peak, greaterThan(1));

      // Pages 2-14 all served the same 9 chapters.
      expect(b.chapters.length, 109);
      expect(b.chapters.map((c) => c.id).toSet().length, 109);
      expect(b.chapters.first.title, '원피스x토리코 콜라보');
      expect(b.chapters.last.title, '1199화');
      expect(b.chapters.last.id, '1834578');
    });

    test('fetch of a single-page series makes one request', () async {
      final a = site((_) => f('series_10394.html'));
      final b = await source(a).fetch('10394');
      expect(a.requests.length, 1);
      expect(b.chapters.length, 27);
      expect(b.chapters.last.title, '11권');
      expect(b.detail.url, 'https://11toon.com/bbs/board.php?bo_table=toons&is=10394');
    });

    test('fetch of a removed series', () {
      expect(() => source(site((_) => f('series_missing.html'))).fetch('99999999'), throwsA(isA<SourceException>()));
    });

    test('pages', () async {
      final a = site((_) => f('chapter_1834578.html'));
      final p = await source(a).pages(const ChapterInfo(id: '1834578', mangaId: '2', title: '1199화'));
      expect(p.length, 12);
      expect(a.requests.single.uri.queryParameters, {'bo_table': 'toons', 'wr_id': '1834578', 'is': '2'});
    });

    test('HTTP failure becomes a SourceException', () async {
      final s = source(FixtureAdapter({}));
      await expectLater(s.browse('latest'), throwsA(isA<SourceException>().having((e) => e.message, 'message', contains('404'))));
      await expectLater(s.fetch('2'), throwsA(isA<SourceException>()));
      await expectLater(
          s.pages(const ChapterInfo(id: '1', mangaId: '2', title: 'x')), throwsA(isA<SourceException>()));
    });
  });
}
