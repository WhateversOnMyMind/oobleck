import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/core/subtitles/anime_titles.dart';

typedef A = ({String subject, String original});

void main() {
  test('season numbers', () {
    expect(seasonOf('ブラッククローバー 第2期'), 2);
    expect(seasonOf('블랙 클로버 2nd Season'), 2);
    expect(seasonOf('Black Clover Season 3'), 3);
    expect(seasonOf('진격의 거인 시즌 4'), 4);
    expect(seasonOf('약사의 혼잣말 2기'), 2);
    expect(seasonOf('블랙 클로버'), isNull);
  });

  test('queries try Korean synonyms, then the Japanese title with and without the season', () {
    final q = anissiaQueries(const AnimeTitles(native: 'ブラッククローバー 第2期'), fallback: 'Black Clover Season 2');
    expect(q, ['ブラッククローバー 第2期', 'ブラッククローバー', 'Black Clover Season 2']);
    expect(anissiaQueries(const AnimeTitles(native: '葬送のフリーレン', korean: ['장송의 프리렌'])).first, '장송의 프리렌');
    expect(anissiaQueries(const AnimeTitles(), fallback: 'X'), ['X']);
  });

  // Live Anissia results for "ブラッククローバー" (2026-11-12), in API order.
  const live = <A>[
    (subject: '블랙 클로버 2nd Season', original: 'ブラッククローバー 2nd Season'),
    (subject: '극장판 블랙 클로버: 마법제의 검', original: '映画 ブラッククローバー 魔法帝の剣'),
    (subject: '블랙 클로버', original: ''),
  ];

  List<String> rank(String native) =>
      rankMatches(live, subject: (a) => a.subject, original: (a) => a.original, native: native).map((a) => a.subject).toList();

  test('season 2 ranks the 2nd Season first', () {
    expect(rank('ブラッククローバー 第2期').first, '블랙 클로버 2nd Season');
  });

  test('season 1 ranks the TV series above the film and season 2', () {
    expect(rank('ブラッククローバー'), ['블랙 클로버', '극장판 블랙 클로버: 마법제의 검', '블랙 클로버 2nd Season']);
  });

  test('a film ranks the film first', () {
    expect(rank('映画 ブラッククローバー 魔法帝の剣').first, '극장판 블랙 클로버: 마법제의 검');
  });
}
