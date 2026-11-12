import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/core/subtitles/anime_titles.dart';
import 'package:oobleck/core/subtitles/anissia.dart';
import 'package:oobleck/core/subtitles/korean_auto.dart';
import 'package:oobleck/core/subtitles/subtitle_import.dart';

AnissiaAnime a(String subject, String original, [int no = 1]) =>
    AnissiaAnime(animeNo: no, subject: subject, originalSubject: original);

void main() {
  group('pickConfident (no wrong-season matches)', () {
    // Live Anissia entries (2026-11-12).
    final kusuriya = [
      a('극장판 약사의 혼잣말', '劇場版 薬屋のひとりごと', 3357),
      a('약사의 혼잣말 3기', '薬屋のひとりごと', 3356),
      a('약사의 혼잣말 2기', '薬屋のひとりごと 第2期', 2948),
    ];
    final jjk = [
      a('주술회전 3기 「사멸회유」', '呪術廻戦 第3期 「死滅回游」', 2858),
      a('주술회전 2기 「회옥·옥절 / 시부야 사변」', '呪術廻戦 「懐玉・玉折／渋谷事変」', 2257),
      a('주술회전 0', '', 2086),
    ];

    test('season 3 picks the 3기 entry even though Anissia left the season out of the Japanese title', () {
      expect(pickConfident(kusuriya, const AnimeTitles(native: '薬屋のひとりごと 第3期'))?.animeNo, 3356);
    });

    test('season 2 picks 2기, never the film', () {
      expect(pickConfident(kusuriya, const AnimeTitles(native: '薬屋のひとりごと 第2期'))?.animeNo, 2948);
    });

    test('a season Anissia does not list gives no match instead of a wrong one', () {
      // JJK season 1 is not on Anissia; season 2/3 must not be used for it.
      expect(pickConfident(jjk, const AnimeTitles(native: '呪術廻戦')), isNull);
    });

    test('Korean synonym from AniList also counts', () {
      expect(pickConfident([a('장송의 프리렌', '', 2517)], const AnimeTitles(native: '葬送のフリーレン', korean: ['장송의 프리렌']))?.animeNo, 2517);
    });
  });

  group('postMatches', () {
    test('real post titles', () {
      expect(postMatches('약사의 혼잣말 3기 6화 자막', '약사의 혼잣말 3기', 6), isTrue);
      expect(postMatches('약사의 혼잣말 3기 5화 자막', '약사의 혼잣말 3기', 6), isFalse);
      expect(postMatches('학생회에도 구멍은 있다 06화 자막', '학생회에도 구멍은 있다', 6), isTrue);
      expect(postMatches('학생회에도 구멍은 있다 16화 자막', '학생회에도 구멍은 있다', 6), isFalse);
      expect(postMatches('나의 행복한 결혼 -특별편- 자막', '약사의 혼잣말 3기', 1), isFalse);
    });

    test('another season of the same show does not match', () {
      expect(postMatches('약사의 혼잣말 2기 6화 자막', '약사의 혼잣말 3기', 6), isFalse);
      expect(postMatches('장송의 프리렌 2기 3화', '장송의 프리렌', 3), isFalse);
      expect(postMatches('장송의 프리렌 3화', '장송의 프리렌', 3), isTrue);
    });

    test('EP. and 話 styles', () {
      expect(postMatches('장송의 프리렌 EP.03 자막', '장송의 프리렌', 3), isTrue);
      expect(postMatches('장송의 프리렌 第3話', '장송의 프리렌', 3), isTrue);
    });
  });

  group('matchEpisodeFile', () {
    test('picks 01 / 1 out of a season pack, ignoring resolution and CRC noise', () {
      final pack = [
        '[SubsPlease] Sousou no Frieren - 01 (720p) [AAAA1111].ass',
        '[SubsPlease] Sousou no Frieren - 02 (720p) [BBBB2222].ass',
        '[SubsPlease] Sousou no Frieren - 03 (720p) [C1357174].ass',
        '[SubsPlease] Sousou no Frieren - 10 (720p) [DDDD4444].ass',
      ];
      expect(matchEpisodeFile(pack, 1), pack[0]);
      expect(matchEpisodeFile(pack, 3), pack[2]);
      expect(matchEpisodeFile(pack, 10), pack[3]);
      expect(matchEpisodeFile(pack, 4), isNull);
    });

    test('number glued to the title, ASS preferred over SMI', () {
      expect(matchEpisodeFile(['약사의 혼잣말06.smi', '약사의 혼잣말06.ass', '약사의 혼잣말05.ass'], 6), '약사의 혼잣말06.ass');
    });

    test('a lone file is used only when the post is for this episode', () {
      expect(matchEpisodeFile(['tfile.ass'], 5), isNull);
      expect(matchEpisodeFile(['tfile.ass'], 5, episodeOnly: true), 'tfile.ass');
      expect(matchEpisodeFile(['약사의 혼잣말06.ass'], 5, episodeOnly: true), isNull);
    });
  });

  test('font packs are skipped', () {
    expect(isFontPack('프리렌 폰트.zip'), isTrue);
    expect(isFontPack('폰트통.zip'), isTrue);
    expect(isFontPack('Fonts.zip'), isTrue);
    expect(isFontPack('프리렌 S.zip'), isFalse);
  });

  test('feeds', () {
    const rss = '<rss><channel><title>blog</title><link>https://x.tistory.com/</link>'
        '<item><title>약사의 혼잣말 3기 6화 자막</title><link>https://x.tistory.com/25</link></item>'
        '<item><title><![CDATA[A &amp; B 5화]]></title><link>https://x.tistory.com/24</link></item></channel></rss>';
    expect(parseRssItems(rss).map((e) => '${e.title}|${e.url}'),
        ['약사의 혼잣말 3기 6화 자막|https://x.tistory.com/25', 'A & B 5화|https://x.tistory.com/24']);
    final blogger = jsonEncode({
      'feed': {
        'entry': [
          {
            'title': {r'$t': '학생회에도 구멍은 있다 6화 자막'},
            'link': [
              {'rel': 'replies', 'href': 'x'},
              {'rel': 'alternate', 'href': 'https://k.blogspot.com/2026/03/6.html'},
            ],
          }
        ]
      }
    });
    expect(parseBloggerFeed(blogger).single.url, 'https://k.blogspot.com/2026/03/6.html');
    expect(parseRssItems('garbage'), isEmpty);
    expect(parseBloggerFeed('garbage'), isEmpty);
  });

  test('Content-Disposition file names (Google Drive)', () {
    expect(fileNameFromDisposition('attachment; filename="a.ass"; filename*=UTF-8\'\'%ED%94%84%EB%A6%AC%EB%A0%8C.ass'), '프리렌.ass');
    final mangled = latin1.decode(utf8.encode('프리렌 2 9화.ass'));
    expect(fileNameFromDisposition('attachment; filename="$mangled"'), '프리렌 2 9화.ass');
    expect(fileNameFromDisposition('attachment; filename="plain.srt"'), 'plain.srt');
    expect(fileNameFromDisposition(null), isNull);
  });
}
