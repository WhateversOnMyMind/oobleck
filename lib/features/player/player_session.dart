import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/settings.dart';
import '../../core/downloads/hls.dart';
import '../../core/log.dart';
import '../../core/models.dart';
import '../../core/player/anime4k.dart';
import '../../core/sources/source.dart';
import '../../core/storage/app_db.dart';
import '../../core/subtitles/korean_lookup.dart';
import '../../core/subtitles/subtitle_import.dart';
import '../../core/storage/records.dart';
import 'play_request.dart';

class QualityOption {
  QualityOption(this.label, this.url);
  final String label;
  final String? url; // null = automatic (master playlist)
}

enum SessionPhase { loading, ready, error }

/// All player logic: resolving the stream, resume, progress saving, tracks,
/// quality/server switching, skip ranges and mpv tuning. The widgets only
/// render it ([PlayerScreen], [PlayerControls]).
class PlayerSession extends ChangeNotifier {
  PlayerSession({
    required this.request,
    required this.db,
    required this.source,
    required this.dio,
    required this.settings,
    required this.supportDir,
    required this.loadEpisodes,
    this.headless = false,
  }) {
    player = Player(
      configuration: PlayerConfiguration(
        title: 'Oobleck',
        libass: !Platform.isAndroid,
        bufferSize: 64 * 1024 * 1024,
        // Warnings include shader compile errors (Anime4K), which mpv otherwise drops silently.
        logLevel: MPVLogLevel.warn,
      ),
    );
    _subs.add(player.stream.log.listen((l) => Log.d('mpv', '${l.prefix}: ${l.text.trim()}')));
    if (headless) unawaited(_setProp('ao', 'null'));
    _subs.add(player.stream.completed.listen((c) {
      if (c) _onCompleted();
    }));
    _subs.add(player.stream.playing.listen((p) {
      if (!p) saveProgress();
    }));
    _subs.add(player.stream.error.listen(_onPlayerError));
    _subs.add(player.stream.position.listen(_onPosition));
    _ticker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (player.state.playing) saveProgress();
    });
    _applySubtitleStyle();
  }

  PlayRequest request;
  final AppDb db;
  final Source source;
  final Dio dio;
  final AppSettings Function() settings;
  final String supportDir;

  /// Episode metadata for the show (cache first, network if needed).
  final Future<List<EpisodeRecord>> Function(String slug) loadEpisodes;

  late final Player player;

  /// Created on first use (the widget tree), so tests can run the session
  /// without a rendering surface.
  late final VideoController controller = VideoController(
    player,
    configuration: VideoControllerConfiguration(
      // Shaders need the GPU video output; on Android decode must copy
      // frames back for them to be applied.
      hwdec: Platform.isAndroid ? 'mediacodec-copy' : null,
    ),
  );

  /// Tests: no audio device, no video output.
  final bool headless;
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _ticker;
  Timer? _serverTimer;
  StreamSubscription<StreamSource>? _resolveSub;
  bool _disposed = false;
  int _loadId = 0;

  // ---- observable state ------------------------------------------------------
  SessionPhase phase = SessionPhase.loading;
  String? errorMessage;
  String toast = '';
  String? toastAction;
  VoidCallback? toastCallback;
  int toastSerial = 0;

  bool offline = false;
  List<StreamSource> servers = [];
  StreamSource? current;
  List<QualityOption> qualities = [];
  QualityOption? quality;
  List<SubtitleTrackInfo> subtitleTracks = [];
  SubtitleTrackInfo? subtitle;
  double subtitleOffset = 0;
  SkipRange? intro;
  SkipRange? outro;
  String? nextEpisode;
  String anime4kPreset = 'off';
  double speed = 1.0;
  bool hasSavedSettingsNote = false;

  /// All subtitle tracks selectable for the current episode.
  List<SubtitleTrackInfo> get allSubtitleTracks => subtitleTracks;

  String get title => request.showTitle;
  String get episode => request.episode;
  AudioType get type => request.type;

  // ---- loading -----------------------------------------------------------------
  Future<void> start() => _load(request, resume: true);

  Future<void> _load(PlayRequest req, {required bool resume, StreamSource? forced}) async {
    final id = ++_loadId;
    request = req;
    phase = SessionPhase.loading;
    errorMessage = null;
    servers = [];
    current = null;
    qualities = [];
    quality = null;
    subtitleTracks = [];
    subtitle = null;
    _userPickedSubtitle = false;
    koreanSearching = false;
    intro = null;
    outro = null;
    _serverTimer?.cancel();
    unawaited(_resolveSub?.cancel());
    notifyListeners();
    try {
      unawaited(_computeNext());
      subtitleOffset = (db.misc<num>('subOffset:${req.slug}') ?? 0).toDouble();
      final saved = db.historyFor(req.slug, req.episode);
      final startAt = resume && saved != null && saved.isPartial ? Duration(milliseconds: saved.positionMs) : Duration.zero;

      final local = req.preferOffline ? _localCopy(req) : null;
      if (local != null) {
        offline = true;
        await _playLocal(local, startAt, id);
        return;
      }
      offline = false;
      await _playRemote(req, startAt, id, forced: forced);
    } catch (e, st) {
      if (id != _loadId || _disposed) return;
      Log.d('player', 'load failed: $e\n$st');
      phase = SessionPhase.error;
      errorMessage = e is SourceException ? e.message : "Couldn't start this episode. Check your connection and try again.";
      notifyListeners();
    }
  }

  DownloadRecord? _localCopy(PlayRequest req) {
    final copies = db
        .allDownloads()
        .where((d) => d.slug == req.slug && d.episode == req.episode && d.isDone && File(d.filePath!).existsSync())
        .toList();
    if (copies.isEmpty) return null;
    copies.sort((a, b) => (a.type == req.type ? 0 : 1).compareTo(b.type == req.type ? 0 : 1));
    return copies.first;
  }

  Future<void> _playLocal(DownloadRecord d, Duration startAt, int id) async {
    // Keep the audio type of the file we actually play.
    request = request.copyWith(type: d.type);
    subtitleTracks = [
      for (final s in d.subs)
        if (File(s.path).existsSync()) SubtitleTrackInfo(url: s.path, label: s.label)
    ];
    subtitleTracks.addAll(_importedTracks());
    await player.open(Media(d.filePath!, start: startAt), play: true);
    if (id != _loadId) return;
    phase = SessionPhase.ready;
    _afterOpen(startAt);
    unawaited(_loadSkipTimes());
  }

  Future<void> _playRemote(PlayRequest req, Duration startAt, int id, {StreamSource? forced}) async {
    final eps = await loadEpisodes(req.slug);
    final ep = eps.where((e) => e.number == req.episode).firstOrNull;
    if (ep == null) throw SourceException('Episode not found');
    final info = ep.toInfo();
    final order = settings().serverOrder.map((e) => e.toLowerCase()).toList();
    int rank(StreamSource s) {
      final i = order.indexOf(s.serverName.toLowerCase());
      return i < 0 ? 999 : i;
    }

    final completer = Completer<void>();
    var started = false;
    Future<void> startWith(StreamSource s) async {
      if (started || id != _loadId) return;
      started = true;
      try {
        await _open(s, startAt, id);
        if (!completer.isCompleted) completer.complete();
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
    }

    if (forced != null) {
      servers = [forced];
      await startWith(forced);
      return completer.future;
    }

    final arrived = <StreamSource>[];
    _resolveSub = source.resolveStreams(info, req.type).listen((s) {
      if (id != _loadId) return;
      arrived.add(s);
      servers = [...arrived]..sort((a, b) => rank(a).compareTo(rank(b)));
      if (started) {
        notifyListeners();
        return;
      }
      if (rank(s) == 0) {
        unawaited(startWith(s));
      } else {
        _serverTimer ??= Timer(const Duration(milliseconds: 900), () {
          final best = [...arrived]..sort((a, b) => rank(a).compareTo(rank(b)));
          unawaited(startWith(best.first));
        });
      }
    }, onError: (Object e) {
      if (!started && !completer.isCompleted) completer.completeError(e);
    }, onDone: () {
      if (!started) {
        if (arrived.isEmpty) {
          if (!completer.isCompleted) completer.completeError(SourceException('No working server found. Try again in a moment.'));
        } else {
          final best = [...arrived]..sort((a, b) => rank(a).compareTo(rank(b)));
          unawaited(startWith(best.first));
        }
      }
    });
    return completer.future;
  }

  Future<void> _open(StreamSource s, Duration startAt, int id, {String? urlOverride}) async {
    current = s;
    subtitleTracks = [...s.subtitles, ..._importedTracks()];
    intro = s.intro;
    outro = s.outro;
    final url = urlOverride ?? s.signed(s.url);
    await player.open(Media(url, httpHeaders: s.headers, start: startAt), play: true);
    if (id != _loadId) return;
    phase = SessionPhase.ready;
    _afterOpen(startAt);
    unawaited(_loadQualities(s));
    unawaited(_loadSkipTimes());
  }

  void _afterOpen(Duration startAt) {
    _applySubtitleStyle();
    _pickDefaultSubtitle();
    unawaited(_applyOffset());
    unawaited(_autoKorean(_loadId));
    unawaited(applyAnime4K(settings().anime4k));
    unawaited(player.setRate(speed));
    if (startAt > const Duration(seconds: 5)) {
      showToast('Resumed at ${_fmt(startAt)}', action: 'Start over', onAction: () {
        unawaited(player.seek(Duration.zero));
      });
    }
    notifyListeners();
  }

  // ---- subtitles ----------------------------------------------------------------
  List<SubtitleTrackInfo> _importedTracks() {
    final list = db.misc<List>('subs:${request.slug}|${request.episode}') ?? const [];
    return [
      for (final m in list.cast<Map>())
        if (File(m['path'] as String).existsSync()) SubtitleTrackInfo(url: m['path'] as String, label: m['label'] as String)
    ];
  }

  /// Adds an imported/downloaded subtitle file for this episode and selects it.
  Future<void> addExternalSubtitle(String path, String label, {bool user = true}) async {
    final key = 'subs:${request.slug}|${request.episode}';
    final list = [...(db.misc<List>(key) ?? const []).cast<Map>()];
    list.removeWhere((m) => m['path'] == path);
    list.add({'path': path, 'label': label});
    await db.setMisc(key, list);
    final t = SubtitleTrackInfo(url: path, label: label);
    subtitleTracks = [...subtitleTracks.where((x) => x.url != path), t];
    if (!user && _userPickedSubtitle) {
      notifyListeners();
      return;
    }
    await selectSubtitle(t, user: user);
  }

  void _pickDefaultSubtitle() {
    if (subtitleTracks.isEmpty) return;
    final lang = settings().autoKoreanSubs ? 'ko' : settings().subtitleLanguage;
    final pick = subtitleTracks.where((t) => t.language == lang).firstOrNull ??
        subtitleTracks.where((t) => t.language == settings().subtitleLanguage).firstOrNull ??
        subtitleTracks.where((t) => t.isDefault).firstOrNull;
    if (pick != null) unawaited(selectSubtitle(pick, user: false));
  }

  /// True once the viewer picks a track themselves; automatic Korean
  /// subtitles never replace that choice.
  bool _userPickedSubtitle = false;

  Future<void> selectSubtitle(SubtitleTrackInfo? t, {bool user = true}) async {
    if (user) _userPickedSubtitle = true;
    subtitle = t;
    notifyListeners();
    if (t == null) {
      await player.setSubtitleTrack(SubtitleTrack.no());
    } else {
      await player.setSubtitleTrack(SubtitleTrack.uri(t.url, title: t.label, language: t.language));
    }
    await _applyOffset();
  }

  // ---- sync offset ----------------------------------------------------------------
  /// Fansub timing differs from the stream by a fixed amount for a whole
  /// season, so the offset is saved per show (each season is its own show) and
  /// applies to Korean/imported tracks in every episode. The site's own tracks
  /// are already in sync and always play with no offset.
  bool isFansubTrack(SubtitleTrackInfo? t) {
    if (t == null) return false;
    if (t.language == 'ko' || t.label.startsWith('Korean')) return true;
    return _importedTracks().any((x) => x.url == t.url);
  }

  int get subtitleOffsetMs => (subtitleOffset * 1000).round();

  Future<void> _applyOffset() async {
    final d = isFansubTrack(subtitle) ? subtitleOffset : 0.0;
    await _setProp('sub-delay', d.toStringAsFixed(3));
  }

  Future<void> setSubtitleOffsetMs(int ms) async {
    subtitleOffset = ms.clamp(-600000, 600000) / 1000;
    notifyListeners();
    await _applyOffset();
    await db.setMisc('subOffset:${request.slug}', subtitleOffset);
  }

  Future<void> setSubtitleOffset(double seconds) => setSubtitleOffsetMs((seconds * 1000).round());

  // ---- automatic Korean subtitles -------------------------------------------------
  bool koreanSearching = false;

  Future<void> _autoKorean(int id) async {
    if (!settings().autoKoreanSubs) return;
    final existing = subtitleTracks.where((t) => t.language == 'ko').firstOrNull;
    if (existing != null) {
      if (!_userPickedSubtitle && subtitle != existing) await selectSubtitle(existing, user: false);
      return;
    }
    final slug = request.slug;
    final episode = request.episode;
    koreanSearching = true;
    notifyListeners();
    try {
      final found = await lookupKoreanSub(dio: dio, db: db, slug: slug, malId: malId, episode: episode);
      if (id != _loadId || _disposed) return;
      if (found == null) {
        if (!_userPickedSubtitle) showToast('No Korean subtitles found for episode $episode');
        return;
      }
      final path = await saveSubtitle(found.subtitle, supportDir, slug, episode);
      await addExternalSubtitle(path, found.label, user: false);
      if (_userPickedSubtitle) return;
      showToast('Korean subtitles · ${found.fansubber}');
    } catch (e) {
      Log.d('ko-subs', 'auto lookup failed: $e');
    } finally {
      if (id == _loadId && !_disposed) {
        koreanSearching = false;
        notifyListeners();
      }
    }
  }

  void _applySubtitleStyle() {
    final s = settings();
    unawaited(_setProp('sub-font-size', s.subSize.round().toString()));
    unawaited(_setProp('sub-color', '#${s.subColor}'));
    unawaited(_setProp('sub-border-size', s.subOutline.toString()));
    unawaited(_setProp('sub-border-style', s.subBackground ? 'background-box' : 'outline-and-shadow'));
    unawaited(_setProp('sub-back-color', s.subBackground ? '#B0000000' : '#00000000'));
    unawaited(_setProp('sub-pos', s.subPos.round().toString()));
  }

  void refreshSubtitleStyle() => _applySubtitleStyle();

  Future<String?> _getProp(String name) async {
    try {
      final platform = player.platform;
      if (platform != null) return await (platform as dynamic).getProperty(name) as String;
    } catch (e) {
      Log.d('player', 'mpv get $name failed: $e');
    }
    return null;
  }

  Future<void> _setProp(String name, String value) async {
    try {
      final platform = player.platform;
      if (platform != null) await (platform as dynamic).setProperty(name, value);
    } catch (e) {
      Log.d('player', 'mpv $name failed: $e');
    }
  }

  // ---- quality ------------------------------------------------------------------
  Future<void> _loadQualities(StreamSource s) async {
    if (!s.isHls) return;
    try {
      final r = await dio.get<String>(s.signed(s.url),
          options: Options(headers: s.headers, responseType: ResponseType.plain));
      final text = r.data ?? '';
      if (!isMasterPlaylist(text)) return;
      final variants = parseMasterPlaylist(text, Uri.parse(s.url))..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
      if (_disposed || current != s) return;
      qualities = [QualityOption('Auto', null), for (final v in variants) QualityOption(v.label, v.url.toString())];
      quality = qualities.first;
      notifyListeners();
    } catch (e) {
      Log.d('player', 'quality list failed: $e');
    }
  }

  Future<void> selectQuality(QualityOption q) async {
    final s = current;
    if (s == null) return;
    quality = q;
    notifyListeners();
    final pos = player.state.position;
    final url = q.url == null ? s.signed(s.url) : s.signed(q.url!);
    await player.open(Media(url, httpHeaders: s.headers, start: pos), play: true);
    await selectSubtitle(subtitle);
  }

  // ---- servers --------------------------------------------------------------------
  Future<void> selectServer(StreamSource s) async {
    if (s == current) return;
    final pos = player.state.position;
    final id = ++_loadId;
    phase = SessionPhase.loading;
    notifyListeners();
    try {
      await _open(s, pos, id);
    } catch (e) {
      phase = SessionPhase.error;
      errorMessage = "That server didn't respond. Try another one.";
      notifyListeners();
    }
  }

  Future<void> switchAudio(AudioType t) async {
    if (t == request.type) return;
    final pos = player.state.position;
    saveProgress();
    final req = request.copyWith(type: t);
    request = req;
    await _load(req.copyWith(), resume: false);
    if (pos > const Duration(seconds: 3)) await player.seek(pos);
  }

  // ---- playback errors ---------------------------------------------------------------
  int _reloads = 0;
  DateTime _lastReload = DateTime.fromMillisecondsSinceEpoch(0);

  void _onPlayerError(String message) {
    if (_disposed || phase != SessionPhase.ready && phase != SessionPhase.loading) return;
    Log.d('player', 'mpv error: $message');
    final s = current;
    if (s == null || offline) {
      phase = SessionPhase.error;
      errorMessage = "This video can't be played.";
      notifyListeners();
      return;
    }
    // Signed URLs expire after ~90 s: re-sign and reload at the same position.
    if (DateTime.now().difference(_lastReload) > const Duration(minutes: 2)) _reloads = 0;
    if (_reloads < 3) {
      _reloads++;
      _lastReload = DateTime.now();
      final pos = player.state.position;
      unawaited(player.open(Media(s.signed(quality?.url ?? s.url), httpHeaders: s.headers, start: pos), play: true));
      return;
    }
    phase = SessionPhase.error;
    errorMessage = 'Playback stopped. Try again or switch server.';
    notifyListeners();
  }

  Future<void> retry() => _load(request, resume: true);

  // ---- progress --------------------------------------------------------------------------
  void saveProgress() {
    final dur = player.state.duration.inMilliseconds;
    final pos = player.state.position.inMilliseconds;
    if (dur <= 0 || phase != SessionPhase.ready) return;
    unawaited(db.saveProgress(request.slug, request.episode, pos, dur));
  }

  void _onCompleted() {
    final dur = player.state.duration.inMilliseconds;
    if (dur > 0) unawaited(db.saveProgress(request.slug, request.episode, dur, dur));
    if (settings().autoNext && nextEpisode != null) {
      unawaited(playNext());
    }
  }

  Future<void> _computeNext() async {
    final nums = <String>{
      ...db.episodes(request.slug).map((e) => e.number),
      ...db.allDownloads().where((d) => d.slug == request.slug && d.isDone).map((d) => d.episode),
    };
    final cur = double.tryParse(request.episode) ?? 0;
    final later = nums.where((n) => (double.tryParse(n) ?? 0) > cur).toList()
      ..sort((a, b) => (double.tryParse(a) ?? 0).compareTo(double.tryParse(b) ?? 0));
    nextEpisode = later.firstOrNull;
    notifyListeners();
  }

  Future<void> playNext() async {
    final n = nextEpisode;
    if (n == null) return;
    saveProgress();
    await _load(request.copyWith(episode: n), resume: true);
  }

  Future<void> playEpisode(String number) async {
    saveProgress();
    await _load(request.copyWith(episode: number), resume: true);
  }

  // ---- skip intro / outro ------------------------------------------------------------------
  Duration _pos = Duration.zero;
  void _onPosition(Duration p) {
    _pos = p;
  }

  SkipRange? get activeSkip {
    if (!settings().skipIntroButton) return null;
    final s = _pos.inMilliseconds / 1000;
    if (intro != null && intro!.contains(s)) return intro;
    if (outro != null && outro!.contains(s)) return outro;
    return null;
  }

  bool get activeSkipIsIntro => intro != null && intro!.contains(_pos.inMilliseconds / 1000);

  Future<void> skipActive() async {
    final r = activeSkip;
    if (r != null) await player.seek(Duration(milliseconds: (r.end * 1000).round()));
  }

  /// MyAnimeList id of the current show, from the stored episode or show.
  String? get malId {
    final ep = db.episodes(request.slug).where((e) => e.number == request.episode).firstOrNull;
    final mal = ep?.malId ?? db.show(request.slug)?.malId;
    return mal == null || mal.isEmpty ? null : mal;
  }

  Future<void> _loadSkipTimes() async {
    if (intro != null && outro != null) return;
    final mal = malId;
    final n = int.tryParse(request.episode);
    if (mal == null || mal.isEmpty || n == null) return;
    final id = _loadId;
    try {
      final r = await dio.get<Map<String, dynamic>>('https://api.aniskip.com/v2/skip-times/$mal/$n',
          queryParameters: {'types': ['op', 'ed'], 'episodeLength': 0},
          options: Options(
            listFormat: ListFormat.multi,
            validateStatus: (s) => s != null && s < 500,
            receiveTimeout: const Duration(seconds: 8),
          ));
      if (id != _loadId || _disposed) return;
      for (final x in (r.data?['results'] as List? ?? const [])) {
        final m = x as Map;
        final iv = m['interval'] as Map;
        final range = SkipRange((iv['startTime'] as num).toDouble(), (iv['endTime'] as num).toDouble());
        if (m['skipType'] == 'op') intro ??= range;
        if (m['skipType'] == 'ed') outro ??= range;
      }
      notifyListeners();
    } catch (e) {
      Log.d('player', 'aniskip unavailable: $e');
    }
  }

  // ---- anime4k -----------------------------------------------------------------------------
  Future<void> applyAnime4K(String preset) async {
    anime4kPreset = preset;
    try {
      if (preset == 'off') {
        await _setProp('glsl-shaders', '');
      } else {
        final dir = await Anime4K.install(supportDir);
        if (!Anime4K.available(preset, dir)) {
          showToast('Anime4K shaders are missing from this build.');
          anime4kPreset = 'off';
        } else {
          if (Platform.isAndroid) {
            await _setProp('hwdec', 'mediacodec-copy');
          }
          await _setProp('glsl-shaders', Anime4K.shaderList(preset, dir));
          unawaited(_verifyAnime4K(preset));
        }
      }
    } catch (e) {
      Log.d('player', 'anime4k failed: $e');
    }
    notifyListeners();
  }

  /// Confirms the shaders actually run by reading mpv's `vo-passes` (the render
  /// passes of recent frames; user shaders appear under their `//!DESC` names,
  /// "Anime4K-v4.0-..."). Reports the result in a toast and the log.
  Future<void> _verifyAnime4K(String preset) async {
    // Give mpv a few rendered frames with the new shaders.
    await Future<void>.delayed(const Duration(seconds: 3));
    if (_disposed || anime4kPreset != preset) return;
    final passes = await _getProp('vo-passes');
    final shaders = await _getProp('glsl-shaders');
    Log.d('player', 'anime4k: glsl-shaders=$shaders');
    final result = Anime4K.checkPasses(passes);
    Log.d('player', 'anime4k: ${result.detail}');
    if (result.running == true) {
      showToast('${Anime4K.label(preset)} is running (${result.count} shader passes)');
    } else if (result.running == false) {
      showToast("Anime4K didn't start on this device. See Settings > Advanced > Source diagnostics.");
    }
  }

  // ---- misc ------------------------------------------------------------------------------------
  Future<void> setSpeed(double v) async {
    speed = v;
    await player.setRate(v);
    notifyListeners();
  }

  void showToast(String message, {String? action, VoidCallback? onAction}) {
    toast = message;
    toastAction = action;
    toastCallback = onAction;
    toastSerial++;
    notifyListeners();
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
  }

  @override
  void dispose() {
    if (_disposed) return;
    saveProgress();
    _disposed = true;
    _ticker?.cancel();
    _serverTimer?.cancel();
    unawaited(_resolveSub?.cancel());
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    unawaited(player.dispose());
    super.dispose();
  }
}
