// End-to-end test of the offline path through the real PlayerSession + libmpv:
// a downloaded episode plays with its sidecar subtitles and resumes at the saved
// position. Needs libmpv + ffmpeg, so it only runs with OOBLECK_PLAYBACK=1.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:oobleck/app/settings.dart';
import 'package:oobleck/core/http.dart';
import 'package:oobleck/core/models.dart';
import 'package:oobleck/core/sources/source.dart';
import 'package:oobleck/core/storage/app_db.dart';
import 'package:oobleck/core/storage/records.dart';
import 'package:oobleck/features/player/play_request.dart';
import 'package:oobleck/features/player/player_session.dart';

class _NoNetworkSource implements Source {
  @override
  dynamic noSuchMethod(Invocation i) => throw StateError('network used while offline: ${i.memberName}');
}

Future<T> _until<T>(Stream<T> s, bool Function(T) f) => s.firstWhere(f).timeout(const Duration(seconds: 30));

void main() {
  final enabled = Platform.environment['OOBLECK_PLAYBACK'] == '1';

  test('downloaded episode plays offline, loads subtitles, resumes, and saves progress', () async {
    MediaKit.ensureInitialized();
    final tmp = Directory.systemTemp.createTempSync('oobleck_sess');
    final video = '${tmp.path}/ep.ts';
    final gen = Process.runSync('ffmpeg', [
      '-y', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc=duration=30:size=160x90:rate=10',
      '-f', 'lavfi', '-i', 'sine=duration=30', '-c:v', 'mpeg2video', '-c:a', 'mp2', '-f', 'mpegts', video,
    ]);
    expect(gen.exitCode, 0, reason: '${gen.stderr}');
    final sub = File('${tmp.path}/ep.en.srt')..writeAsStringSync('1\n00:00:01,000 --> 00:00:04,000\nhello\n');

    final db = await AppDb.open('${tmp.path}/db');
    await db.putShow(ShowRecord(slug: 'demo', title: 'Demo'));
    await db.putDownload(DownloadRecord(
      slug: 'demo',
      episode: '1',
      type: AudioType.sub,
      status: DownloadStatus.done,
      filePath: video,
      subs: [DownloadedSub(path: sub.path, label: 'English', language: 'en')],
    ));
    await db.saveProgress('demo', '1', 10000, 30000); // watched 10 s of 30 s

    final session = PlayerSession(
      request: const PlayRequest(slug: 'demo', showTitle: 'Demo', episode: '1'),
      db: db,
      source: _NoNetworkSource(),
      dio: buildDio(),
      settings: () => const AppSettings(),
      supportDir: tmp.path,
      loadEpisodes: (_) async => const [],
      headless: true,
    );
    addTearDown(() async {
      session.dispose();
      await db.close();
      tmp.deleteSync(recursive: true);
    });

    await session.start();
    expect(session.phase, SessionPhase.ready);
    expect(session.offline, isTrue);
    expect(session.allSubtitleTracks.single.label, 'English');
    expect(session.subtitle?.label, 'English', reason: 'preferred language is auto-selected');

    // Resumed near 10 s, not 0.
    await _until(session.player.stream.position, (d) => d >= const Duration(seconds: 10));
    expect(session.player.state.position, lessThan(const Duration(seconds: 20)));
    expect(session.toast, startsWith('Resumed at 0:10'));

    // Subtitle sync offset persists per show.
    await session.setSubtitleOffset(0.3);
    expect(db.misc<num>('subOffset:demo'), 0.3);

    // Progress is saved on demand (and on dispose).
    await session.player.seek(const Duration(seconds: 15));
    await _until(session.player.stream.position, (d) => d >= const Duration(seconds: 15));
    session.saveProgress();
    final h = db.historyFor('demo', '1')!;
    expect(h.positionMs, greaterThanOrEqualTo(15000));
    expect(h.durationMs, greaterThan(25000));
    expect(h.isPartial, isTrue);
  }, skip: enabled ? false : 'set OOBLECK_PLAYBACK=1 (needs libmpv + ffmpeg)', timeout: const Timeout(Duration(minutes: 2)));
}
