// Live check of the automatic Korean subtitle finder against Anissia and the
// fansubbers' real blogs. Skipped unless OOBLECK_LIVE=1 (needs the network,
// and the posts change over time).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/core/http.dart';
import 'package:oobleck/core/subtitles/anime_titles.dart';
import 'package:oobleck/core/subtitles/korean_auto.dart';

void main() {
  final live = Platform.environment['OOBLECK_LIVE'] == '1';
  final finder = KoreanSubFinder(buildDio());

  Future<void> check(String label, AnimeTitles titles, String episode) async {
    final show = await finder.matchShow(titles);
    expect(show, isNotNull, reason: '$label: no confident Anissia match');
    final sub = await finder.find(show!, episode);
    expect(sub, isNotNull, reason: '$label: no subtitle for episode $episode');
    // ignore: avoid_print
    print('$label E$episode -> ${show.subject} | ${sub!.label} | ${sub.subtitle.name}${sub.subtitle.ext} '
        '(${sub.subtitle.text.length} chars)');
    expect(RegExp('[가-힣]').hasMatch(sub.subtitle.text), isTrue, reason: 'subtitle has no Korean text');
  }

  test('Tistory: per-episode post found through the blog feed', () async {
    await check('Kusuriya S3', const AnimeTitles(native: '薬屋のひとりごと 第3期'), '5');
  }, skip: live ? false : 'set OOBLECK_LIVE=1');

  test('Tistory: episode from the latest post\'s season pack (AniList title by MAL id)', () async {
    final titles = await AnimeTitles.forMal(buildDio(), '52991'); // Frieren
    await check('Frieren', titles, '3');
  }, skip: live ? false : 'set OOBLECK_LIVE=1');

  test('Blogspot + Google Drive', () async {
    await check('Frieren S2', const AnimeTitles(native: '葬送のフリーレン 第2期'), '9');
  }, skip: live ? false : 'set OOBLECK_LIVE=1');
}
