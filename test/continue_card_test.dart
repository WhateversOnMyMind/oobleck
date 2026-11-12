import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oobleck/app/theme.dart';
import 'package:oobleck/core/storage/app_db.dart';
import 'package:oobleck/core/storage/records.dart';
import 'package:oobleck/features/home/home_screen.dart';

void main() {
  Future<({int play, int episodes})> pumpCard(WidgetTester tester, {String title = 'Frieren', double textScale = 1}) async {
    var play = 0;
    var episodes = 0;
    final item = ContinueItem(
      show: ShowRecord(slug: 'frieren', title: title),
      episode: '3',
      entry: null,
      resumeFraction: 0.4,
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Center(
            // Same height as the Continue watching row.
            child: SizedBox(
              height: 190,
              child: ContinueCard(item: item, onPlay: () => play++, onEpisodes: () => episodes++),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    return (play: play, episodes: episodes);
  }

  testWidgets('Episodes opens the season, Play resumes', (tester) async {
    var play = 0;
    var episodes = 0;
    final item = ContinueItem(show: ShowRecord(slug: 'frieren', title: 'Frieren'), episode: '3', entry: null, resumeFraction: 0.4);
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(height: 190, child: ContinueCard(item: item, onPlay: () => play++, onEpisodes: () => episodes++)),
        ),
      ),
    ));

    expect(find.text('Episode 3 · resume'), findsOneWidget);
    await tester.tap(find.text('Episodes'));
    expect((play, episodes), (0, 1));
    await tester.tap(find.text('Play'));
    expect((play, episodes), (1, 1));
    await tester.tap(find.text('Frieren')); // the card itself resumes
    expect((play, episodes), (2, 1));
    await tester.longPress(find.text('Frieren'));
    expect((play, episodes), (2, 2));
  });

  testWidgets('no overflow with a long title or large text', (tester) async {
    await pumpCard(tester, title: 'Re:ZERO -Starting Life in Another World- Season 3: Counterattack Arc');
    expect(tester.takeException(), isNull);
    await pumpCard(tester, textScale: 1.6);
    expect(tester.takeException(), isNull);
    expect(find.text('Episodes'), findsOneWidget);
  });
}
