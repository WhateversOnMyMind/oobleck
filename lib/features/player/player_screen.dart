import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../core/storage/records.dart';
import '../../core/subtitles/subtitle_import.dart';
import '../subtitles/korean_sheet.dart';
import '../sync/sync_controller.dart';
import 'play_request.dart';
import 'player_controls.dart';
import 'player_session.dart';
import 'video_fit.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.request});
  final PlayRequest request;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> with WidgetsBindingObserver {
  late final PlayerSession session;
  late final SyncController _sync;
  bool get _mobile => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final db = ref.read(dbProvider);
    _sync = ref.read(syncProvider.notifier);
    session = PlayerSession(
      request: widget.request,
      db: db,
      source: ref.read(sourceProvider),
      dio: ref.read(dioProvider),
      settings: () => ref.read(settingsProvider),
      supportDir: ref.read(supportDirProvider),
      loadEpisodes: (slug) async {
        final cached = db.episodes(slug);
        if (cached.isNotEmpty) return cached;
        final b = await ref.read(showProvider(slug).future);
        return b.episodes.map(EpisodeRecord.fromInfo).toList();
      },
    );
    if (_mobile) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    WakelockPlus.enable();
    session.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      session.saveProgress();
      if (state == AppLifecycleState.paused && _mobile) session.player.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    session.dispose();
    _sync.syncSoon(); // share the progress just saved
    WakelockPlus.disable();
    if (_mobile) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  Future<void> _importSubtitle() async {
    final r = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['srt', 'vtt', 'ass', 'ssa', 'smi', 'sub'],
    );
    final path = r.firstOrNull?.path;
    if (path == null) return;
    try {
      final saved = await importSubtitleFile(path, session, ref.read(supportDirProvider));
      await session.addExternalSubtitle(saved, p.basenameWithoutExtension(path));
      session.showToast('Subtitles loaded');
    } catch (_) {
      session.showToast("Couldn't read that subtitle file.");
    }
  }

  void _findKorean() {
    showKoreanSubtitleSheet(
      context: context,
      ref: ref,
      session: session,
      onLoaded: (path, label) => session.addExternalSubtitle(path, label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    return PopScope(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, box) => ValueListenableBuilder<VideoFit>(
            valueListenable: session.videoFit,
            builder: (context, fit, _) => Video(
              controller: session.controller,
              fill: Colors.black,
              fit: fit.boxFit,
              controls: (state) => PlayerControls(
                session: session,
                videoState: state,
                onImportSubtitle: _importSubtitle,
                onFindKorean: _findKorean,
                onClose: () => Navigator.of(context).maybePop(),
              ),
              // Android renders text subtitles in Flutter (system fonts cover CJK);
              // desktop uses mpv/libass so ASS styling is kept. Sized from the
              // screen height so 4:3 shows get the same size as 16:9 ones.
              subtitleViewConfiguration: SubtitleViewConfiguration(
                visible: _mobile,
                textScaler: TextScaler.linear(subtitleTextScale(box.biggest)),
                style: TextStyle(
                  height: 1.3,
                  fontSize: s.subSize,
                  color: Color(int.parse('FF${s.subColor}', radix: 16)),
                  backgroundColor: s.subBackground ? const Color(0xB0000000) : null,
                  shadows: s.subOutline > 0
                      ? const [Shadow(blurRadius: 3, color: Colors.black), Shadow(blurRadius: 6, color: Colors.black)]
                      : null,
                  fontWeight: FontWeight.w600,
                ),
                padding: EdgeInsets.fromLTRB(24, 0, 24, box.biggest.height * 0.05 + (100 - s.subPos) * 2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reads a user-picked subtitle file, converts it to UTF-8 (SMI -> SRT) and
/// stores it under the app support dir. Returns the stored path.
Future<String> importSubtitleFile(String path, PlayerSession session, String supportDir) async {
  final bytes = await File(path).readAsBytes();
  final prepared = prepareSubtitle(bytes, p.basename(path));
  return saveSubtitle(prepared, supportDir, session.request.slug, session.request.episode);
}
