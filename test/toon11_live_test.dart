// Live check of the 11toon source. Skipped unless OOBLECK_LIVE=1 (needs the
// network, and the catalogue changes over time).
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/core/http.dart';
import 'package:oobleck/core/manga/manga_models.dart';
import 'package:oobleck/core/sources/toon11/toon11_source.dart';

void main() {
  final live = Platform.environment['OOBLECK_LIVE'] == '1';
  final skip = live ? false : 'set OOBLECK_LIVE=1';
  final dio = buildDio();
  final source = Toon11Source(dio: dio);

  void expectCards(MangaListing l, {int atLeast = 1}) {
    expect(l.items.length, greaterThanOrEqualTo(atLeast));
    for (final m in l.items) {
      expect(int.tryParse(m.id), isNotNull);
      expect(m.title, isNotEmpty);
      expect(m.cover, startsWith('https://'));
    }
  }

  test('latest updates page through and filter by genres', () async {
    final p1 = await source.browse(Toon11Source.latest);
    expectCards(p1, atLeast: 30);
    expect(p1.hasNext, isTrue);
    final p2 = await source.browse(Toon11Source.latest, page: 2);
    expectCards(p2, atLeast: 30);
    expect(p2.items.first.id, isNot(p1.items.first.id));

    final one = await source.browse(Toon11Source.latest, genres: {'판타지'});
    final two = await source.browse(Toon11Source.latest, genres: {'판타지', '액션'});
    expectCards(one, atLeast: 30);
    expectCards(two, atLeast: 10);
    expect(two.items.map((m) => m.id), isNot(one.items.map((m) => m.id)));
    expectCards(await source.browse(Toon11Source.latest, genres: {'일상 치유'}));
  }, skip: skip);

  test('popular, completed and daily picks', () async {
    final pop = await source.browse(Toon11Source.popular);
    expectCards(pop, atLeast: 100);
    expect(pop.items.first.subtitle, startsWith('1위'));
    expect(pop.hasNext, isTrue);
    final pop2 = await source.browse(Toon11Source.popular, page: 2);
    expectCards(pop2, atLeast: 32);
    expect(pop2.items.first.subtitle, startsWith('102위'));
    expect(pop.items.map((m) => m.id).toSet().intersection(pop2.items.map((m) => m.id).toSet()), isEmpty);

    expectCards(await source.browse(Toon11Source.popular, genres: {'SF'}), atLeast: 50);
    expectCards(await source.browse(Toon11Source.completed), atLeast: 100);
    final picks = await source.browse(Toon11Source.recommended);
    expectCards(picks, atLeast: 50);
    expect(picks.hasNext, isFalse);
  }, skip: skip);

  test('search by title and by author', () async {
    final byTitle = await source.search('원피스');
    expectCards(byTitle, atLeast: 2);
    expect(byTitle.items.map((m) => m.id), contains('2'));
    final byAuthor = await source.search('오다');
    expect(byAuthor.items.map((m) => m.id), contains('2'));
    expect((await source.search('zzqqxxyy')).items, isEmpty);
  }, skip: skip);

  test('series with many chapter pages, then a chapter and its first image', () async {
    final b = await source.fetch('2');
    expect(b.detail.title, contains('원피스'));
    expect(b.detail.author, isNotEmpty);
    expect(b.detail.genres, isNotEmpty);
    expect(b.detail.status, MangaStatus.ongoing);
    expect(b.chapters.length, greaterThan(1200));
    expect(b.chapters.map((c) => c.id).toSet().length, b.chapters.length);
    expect(b.chapters.first.uploaded!.isBefore(b.chapters.last.uploaded!), isTrue);
    expect(b.chapters.last.number, greaterThan(1100));
    final numbered = b.chapters.where((c) => c.number != null).length;
    // ignore: avoid_print
    print('${b.detail.title}: ${b.chapters.length} chapters, $numbered numbered, '
        'last "${b.chapters.last.title}"');
    expect(numbered, greaterThan(b.chapters.length * 0.9));

    final pages = await source.pages(b.chapters.last);
    expect(pages, isNotEmpty);
    expect(pages.first.fallback, isNotNull);
    for (final url in [pages.first.url, pages.first.fallback!]) {
      final r = await dio.get<List<int>>(url,
          options: Options(responseType: ResponseType.bytes, headers: source.imageHeaders));
      expect(r.headers.value('content-type'), startsWith('image/'));
      expect(r.data!.length, greaterThan(1000));
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}
