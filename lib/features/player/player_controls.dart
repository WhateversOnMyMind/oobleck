import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/models.dart';
import '../../core/player/anime4k.dart';
import '../../ui/widgets.dart';
import 'player_session.dart';
import 'video_fit.dart';

/// Our own full-screen controls: auto-hiding overlay, big centre play/pause,
/// clean bottom bar, gestures on touch, keyboard shortcuts on desktop.
class PlayerControls extends ConsumerStatefulWidget {
  const PlayerControls({
    super.key,
    required this.session,
    required this.videoState,
    required this.onImportSubtitle,
    required this.onFindKorean,
    required this.onClose,
  });

  final PlayerSession session;
  final VideoState videoState;
  final VoidCallback onImportSubtitle;
  final VoidCallback onFindKorean;
  final VoidCallback onClose;

  @override
  ConsumerState<PlayerControls> createState() => _PlayerControlsState();
}

class _PlayerControlsState extends ConsumerState<PlayerControls> {
  PlayerSession get s => widget.session;
  final FocusNode _focus = FocusNode();
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _hide;
  Timer? _hudTimer;

  bool _visible = true;
  bool _playing = false;
  bool _buffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;
  double? _drag; // seconds while dragging the seek bar
  double _volume = 100;
  String? _hud; // transient centre indicator text
  IconData? _hudIcon;
  double _gestureStartValue = 0;

  bool get _mobile => Platform.isAndroid || Platform.isIOS;
  bool get _wide => MediaQuery.sizeOf(context).width >= 700;

  @override
  void initState() {
    super.initState();
    final pl = s.player;
    _playing = pl.state.playing;
    _position = pl.state.position;
    _duration = pl.state.duration;
    _volume = pl.state.volume;
    _subs.addAll([
      pl.stream.playing.listen((v) {
        setState(() => _playing = v);
        _poke();
      }),
      pl.stream.buffering.listen((v) => setState(() => _buffering = v)),
      pl.stream.position.listen((v) {
        if (_drag == null) setState(() => _position = v);
      }),
      pl.stream.duration.listen((v) => setState(() => _duration = v)),
      pl.stream.buffer.listen((v) => setState(() => _buffered = v)),
      pl.stream.volume.listen((v) => setState(() => _volume = v)),
    ]);
    s.addListener(_onSession);
    _poke();
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    s.removeListener(_onSession);
    for (final x in _subs) {
      unawaited(x.cancel());
    }
    _hide?.cancel();
    _hudTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  // ---- visibility ----------------------------------------------------------
  void _poke() {
    _hide?.cancel();
    if (!_visible) setState(() => _visible = true);
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing && !_menuOpen) setState(() => _visible = false);
    });
  }

  bool _menuOpen = false;

  void _toggleVisible() {
    if (_visible) {
      _hide?.cancel();
      setState(() => _visible = false);
    } else {
      _poke();
    }
  }

  void _showHud(IconData icon, String text) {
    _hudTimer?.cancel();
    setState(() {
      _hud = text;
      _hudIcon = icon;
    });
    _hudTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _hud = null);
    });
  }

  // ---- actions ---------------------------------------------------------------
  void _seekBy(int seconds) {
    final target = _position + Duration(seconds: seconds);
    final clamped = target < Duration.zero ? Duration.zero : (_duration > Duration.zero && target > _duration ? _duration : target);
    unawaited(s.player.seek(clamped));
    _showHud(seconds < 0 ? Icons.replay_10_rounded : Icons.forward_10_rounded, '${seconds > 0 ? '+' : '−'}${seconds.abs()}s');
  }

  void _togglePlay() => unawaited(s.player.playOrPause());

  void _setVolume(double v) {
    final c = v.clamp(0, 100).toDouble();
    unawaited(s.player.setVolume(c));
    _showHud(c == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded, '${c.round()}%');
  }

  Future<void> _toggleFullscreen() async {
    if (widget.videoState.isFullscreen()) {
      await widget.videoState.exitFullscreen();
    } else {
      await widget.videoState.enterFullscreen();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    _poke();
    if (k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.keyK) {
      _togglePlay();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      _seekBy(-5);
    } else if (k == LogicalKeyboardKey.arrowRight) {
      _seekBy(5);
    } else if (k == LogicalKeyboardKey.keyJ) {
      _seekBy(-10);
    } else if (k == LogicalKeyboardKey.keyL) {
      _seekBy(10);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _setVolume(_volume + 5);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _setVolume(_volume - 5);
    } else if (k == LogicalKeyboardKey.keyM) {
      _setVolume(_volume > 0 ? 0 : 100);
    } else if (k == LogicalKeyboardKey.keyF) {
      unawaited(_toggleFullscreen());
    } else if (k == LogicalKeyboardKey.escape) {
      if (widget.videoState.isFullscreen()) {
        unawaited(widget.videoState.exitFullscreen());
      } else {
        widget.onClose();
      }
    } else if (k == LogicalKeyboardKey.keyZ) {
      unawaited(_cycleFit());
    } else if (k == LogicalKeyboardKey.keyN) {
      unawaited(s.playNext());
    } else if (k == LogicalKeyboardKey.keyC) {
      _cycleSubtitle();
    } else if (k == LogicalKeyboardKey.bracketLeft) {
      unawaited(s.setSpeed((s.speed - 0.25).clamp(0.25, 3.0)));
      _showHud(Icons.speed_rounded, '${s.speed.toStringAsFixed(2)}×');
    } else if (k == LogicalKeyboardKey.bracketRight) {
      unawaited(s.setSpeed((s.speed + 0.25).clamp(0.25, 3.0)));
      _showHud(Icons.speed_rounded, '${s.speed.toStringAsFixed(2)}×');
    } else if (k == LogicalKeyboardKey.keyG || k == LogicalKeyboardKey.keyH) {
      // G / H: -/+100 ms, with Shift: -/+1 s.
      final step = HardwareKeyboard.instance.isShiftPressed ? 1000 : 100;
      final ms = s.subtitleOffsetMs + (k == LogicalKeyboardKey.keyG ? -step : step);
      unawaited(s.setSubtitleOffsetMs(ms));
      _showHud(Icons.subtitles_rounded, 'Sync ${formatOffsetMs(ms)}');
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _cycleSubtitle() {
    final tracks = s.allSubtitleTracks;
    if (tracks.isEmpty) return;
    final i = s.subtitle == null ? -1 : tracks.indexOf(s.subtitle!);
    final next = i + 1 >= tracks.length ? null : tracks[i + 1];
    unawaited(s.selectSubtitle(next));
    _showHud(Icons.closed_caption_rounded, next?.label ?? 'Subtitles off');
  }

  // ---- gestures (touch) ----------------------------------------------------------
  Offset? _lastTap;
  void _onDoubleTap() {
    final w = MediaQuery.sizeOf(context).width;
    final x = _lastTap?.dx ?? w / 2;
    if (x < w * 0.4) {
      _seekBy(-10);
    } else if (x > w * 0.6) {
      _seekBy(10);
    } else {
      _togglePlay();
    }
  }

  Future<void> _dragStart(DragStartDetails d) async {
    final w = MediaQuery.sizeOf(context).width;
    _gestureLeft = d.globalPosition.dx < w / 2;
    if (_gestureLeft) {
      try {
        _gestureStartValue = await ScreenBrightness.instance.application;
      } catch (_) {
        _gestureStartValue = 0.5;
      }
    } else {
      _gestureStartValue = _volume;
    }
    _gestureDy = 0;
  }

  bool _gestureLeft = true;
  double _gestureDy = 0;

  void _dragUpdate(DragUpdateDetails d) {
    final h = MediaQuery.sizeOf(context).height;
    _gestureDy -= d.delta.dy;
    final frac = _gestureDy / (h * 0.7);
    if (_gestureLeft) {
      final v = (_gestureStartValue + frac).clamp(0.0, 1.0);
      unawaited(ScreenBrightness.instance.setApplicationScreenBrightness(v).catchError((_) {}));
      _showHud(Icons.brightness_6_rounded, '${(v * 100).round()}%');
    } else {
      _setVolume(_gestureStartValue + frac * 100);
    }
  }

  // ---- build -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final showUi = _visible || s.phase != SessionPhase.ready;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: MouseRegion(
        cursor: showUi || _mobile ? MouseCursor.defer : SystemMouseCursors.none,
        onHover: (_) {
          if (!_mobile) {
            _poke();
          }
        },
        child: Stack(fit: StackFit.expand, children: [
          // Hit layer
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _lastTap = d.localPosition,
            onTap: _mobile ? _toggleVisible : _togglePlay,
            onDoubleTap: _mobile ? _onDoubleTap : () => unawaited(_toggleFullscreen()),
            onVerticalDragStart: _mobile ? _dragStart : null,
            onVerticalDragUpdate: _mobile ? _dragUpdate : null,
            child: const SizedBox.expand(),
          ),
          // Overlay
          IgnorePointer(
            ignoring: !showUi,
            child: AnimatedOpacity(
              opacity: showUi ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: _overlay(context),
            ),
          ),
          if (s.activeSkip != null) _skipButton(context),
          if (s.phase == SessionPhase.loading) _loading(context),
          if (s.phase == SessionPhase.error) _error(context),
          if (s.phase == SessionPhase.ready && _buffering)
            const Center(child: SizedBox(width: 44, height: 44, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white70))),
          if (_hud != null) _hudWidget(),
          _toast(context),
        ]),
      ),
    );
  }

  Widget _overlay(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pad = MediaQuery.paddingOf(context);
    final dur = _duration.inMilliseconds / 1000;
    final pos = (_drag ?? _position.inMilliseconds / 1000).clamp(0, dur <= 0 ? 1 : dur).toDouble();
    return Stack(fit: StackFit.expand, children: [
      // Gradients
      const IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xCC000000), Color(0x00000000), Color(0x00000000), Color(0xE6000000)],
              stops: [0, 0.28, 0.6, 1],
            ),
          ),
        ),
      ),
      // Top bar
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Padding(
          padding: EdgeInsets.fromLTRB(8 + pad.left, 8 + pad.top, 8 + pad.right, 0),
          child: Row(children: [
            IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back_rounded, size: 28),
              onPressed: widget.onClose,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(
                  'Episode ${s.episode}${s.offline ? ' · Downloaded' : ''}${s.type == AudioType.dub ? ' · Dub' : ''}',
                  style: t.bodySmall?.copyWith(color: Colors.white70),
                ),
              ]),
            ),
          ]),
        ),
      ),
      // Centre controls
      Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _roundButton(Icons.replay_10_rounded, 40, () => _seekBy(-10), 'Back 10 seconds'),
          const SizedBox(width: 28),
          Material(
            color: Colors.black45,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _togglePlay,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, key: ValueKey(_playing), size: 56),
                ),
              ),
            ),
          ),
          const SizedBox(width: 28),
          _roundButton(Icons.forward_10_rounded, 40, () => _seekBy(10), 'Forward 10 seconds'),
        ]),
      ),
      // Bottom bar
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16 + pad.left, 0, 16 + pad.right, 8 + pad.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_drag != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                  child: Text(formatDuration(Duration(seconds: pos.round())), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ),
            Row(children: [
              SizedBox(width: 52, child: Text(formatDuration(Duration(seconds: pos.round())), style: t.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]))),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                    activeTrackColor: kAccent,
                    inactiveTrackColor: Colors.white24,
                    secondaryActiveTrackColor: Colors.white38,
                    thumbColor: kAccent,
                  ),
                  child: Slider(
                    min: 0,
                    max: dur <= 0 ? 1 : dur,
                    value: pos,
                    secondaryTrackValue: (_buffered.inMilliseconds / 1000).clamp(0, dur <= 0 ? 1 : dur).toDouble(),
                    onChangeStart: (_) => _hide?.cancel(),
                    onChanged: (v) => setState(() => _drag = v),
                    onChangeEnd: (v) {
                      unawaited(s.player.seek(Duration(milliseconds: (v * 1000).round())));
                      setState(() {
                        _position = Duration(milliseconds: (v * 1000).round());
                        _drag = null;
                      });
                      _poke();
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 52,
                child: Text(formatDuration(_duration), textAlign: TextAlign.end, style: t.bodySmall?.copyWith(color: Colors.white70)),
              ),
            ]),
            Row(children: [
              _barButton(Icons.closed_caption_rounded, 'Subtitles', _subtitleMenu, active: s.subtitle != null),
              if (s.qualities.length > 1) _barButton(Icons.high_quality_rounded, s.quality?.label ?? 'Quality', _qualityMenu, label: s.quality?.label),
              _barButton(Icons.speed_rounded, 'Speed', _speedMenu, label: s.speed == 1 ? null : '${s.speed}×'),
              _barButton(Icons.auto_awesome_rounded, 'Anime4K', _anime4kMenu, active: s.anime4kPreset != 'off'),
              if (s.servers.length > 1 || s.current != null) _barButton(Icons.dns_rounded, 'Server', _serverMenu, label: _wide ? s.current?.serverName : null),
              const Spacer(),
              ValueListenableBuilder<VideoFit>(
                valueListenable: s.videoFit,
                builder: (context, fit, _) => _barButton(fit.icon, 'Picture: ${fit.label} (Z)', _cycleFit, active: fit != VideoFit.fit),
              ),
              if (s.nextEpisode != null) _barButton(Icons.skip_next_rounded, 'Next episode', () => unawaited(s.playNext()), label: _wide ? 'Next' : null),
              if (!_mobile) _barButton(widget.videoState.isFullscreen() ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, 'Fullscreen', () => unawaited(_toggleFullscreen())),
            ]),
          ]),
        ),
      ),
    ]);
  }

  Future<void> _cycleFit() async {
    final f = await widget.session.cycleVideoFit();
    _showHud(f.icon, f.label);
  }

  Widget _roundButton(IconData icon, double size, VoidCallback onTap, String tip) => IconButton(
        tooltip: tip,
        iconSize: size,
        icon: Icon(icon),
        onPressed: () {
          onTap();
          _poke();
        },
      );

  Widget _barButton(IconData icon, String tip, VoidCallback onTap, {String? label, bool active = false}) {
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          _poke();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 24, color: active ? kAccent : Colors.white),
            if (label != null) ...[
              const SizedBox(width: 6),
              Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _skipButton(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Positioned(
      right: 24 + pad.right,
      bottom: (_visible ? 110 : 40) + pad.bottom,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: Colors.black87, foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
        onPressed: () => unawaited(s.skipActive()),
        icon: const Icon(Icons.fast_forward_rounded),
        label: Text(s.activeSkipIsIntro ? 'Skip intro' : 'Skip outro'),
      ),
    );
  }

  Widget _loading(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Skeleton(width: 220, height: 14),
        const SizedBox(height: 12),
        Text('Loading episode ${s.episode}…', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white54)),
        const SizedBox(height: 18),
        SizedBox(width: 160, child: LinearProgressIndicator(minHeight: 2, color: kAccent, backgroundColor: Colors.white12)),
      ]),
    );
  }

  Widget _error(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(children: [
        Positioned(
          top: 8 + MediaQuery.paddingOf(context).top,
          left: 8,
          child: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: widget.onClose),
        ),
        EmptyState(
          icon: Icons.error_outline_rounded,
          title: "Can't play this episode",
          message: s.errorMessage,
          actionLabel: 'Try again',
          onAction: () => unawaited(s.retry()),
        ),
      ]),
    );
  }

  Widget _hudWidget() => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(16)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_hudIcon, size: 30),
            const SizedBox(width: 10),
            Text(_hud!, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  int _shownToast = 0;
  Timer? _toastTimer;
  bool _toastVisible = false;

  Widget _toast(BuildContext context) {
    if (s.toastSerial != _shownToast && s.toast.isNotEmpty) {
      _shownToast = s.toastSerial;
      _toastVisible = true;
      _toastTimer?.cancel();
      _toastTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _toastVisible = false);
      });
    }
    final pad = MediaQuery.paddingOf(context);
    return Positioned(
      left: 24 + pad.left,
      bottom: 100 + pad.bottom,
      child: AnimatedOpacity(
        opacity: _toastVisible ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !_toastVisible,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
            decoration: BoxDecoration(color: const Color(0xE6202028), borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(s.toast),
              if (s.toastAction != null) ...[
                const SizedBox(width: 6),
                Text('·', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white38)),
                TextButton(
                  onPressed: () {
                    s.toastCallback?.call();
                    setState(() => _toastVisible = false);
                  },
                  child: Text(s.toastAction!),
                ),
              ] else
                const SizedBox(width: 10),
            ]),
          ),
        ),
      ),
    );
  }

  // ---- menus ---------------------------------------------------------------------------
  Future<T?> _sheet<T>(String title, Widget Function(BuildContext, void Function(void Function())) body) async {
    _menuOpen = true;
    _hide?.cancel();
    final r = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setSheet) => ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(title, style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Flexible(child: SingleChildScrollView(child: body(ctx, setSheet))),
            ]),
          ),
        ),
      ),
    );
    _menuOpen = false;
    _poke();
    return r;
  }

  Widget _option(BuildContext ctx, String label, bool selected, VoidCallback onTap, {String? subtitle}) => ListTile(
        dense: true,
        title: Text(label),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: selected ? const Icon(Icons.check_rounded, color: kAccent) : null,
        onTap: () {
          onTap();
          Navigator.pop(ctx);
        },
      );

  void _subtitleMenu() {
    unawaited(_sheet<void>('Subtitles', (ctx, setSheet) {
      final tracks = s.allSubtitleTracks;
      return Column(children: [
        _option(ctx, 'Off', s.subtitle == null, () => unawaited(s.selectSubtitle(null))),
        for (final t in tracks) _option(ctx, t.label, s.subtitle == t, () => unawaited(s.selectSubtitle(t))),
        const Divider(height: 1),
        ListTile(
          dense: true,
          leading: const Icon(Icons.upload_file_rounded),
          title: const Text('Import subtitle file…'),
          onTap: () {
            Navigator.pop(ctx);
            widget.onImportSubtitle();
          },
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.travel_explore_rounded),
          title: const Text('Search Korean subs manually'),
          subtitle: s.koreanSearching ? const Text('Looking for Korean subtitles automatically…') : null,
          onTap: () {
            Navigator.pop(ctx);
            widget.onFindKorean();
          },
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.tune_rounded),
          title: const Text('Style & timing'),
          onTap: () {
            Navigator.pop(ctx);
            _subtitleStyleSheet();
          },
        ),
      ]);
    }));
  }

  void _subtitleStyleSheet() {
    unawaited(_sheet<void>('Subtitle style & timing', (ctx, setSheet) {
      final st = ref.read(settingsProvider);
      final notifier = ref.read(settingsProvider.notifier);
      Future<void> set(String k, Object v) async {
        await notifier.set(k, v);
        s.refreshSubtitleStyle();
        setSheet(() {});
      }

      Widget slider(String label, double value, double min, double max, String key, {int? div}) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              SizedBox(width: 90, child: Text(label)),
              Expanded(child: Slider(value: value.clamp(min, max), min: min, max: max, divisions: div, label: value.toStringAsFixed(1), onChanged: (v) => set(key, v))),
            ]),
          );
      const colors = {'White': 'FFFFFF', 'Yellow': 'FFE066', 'Cyan': '7DF9FF', 'Green': '9BE564'};
      return Column(children: [
        _SyncControl(session: s, onChanged: () => setSheet(() {})),
        const Divider(),
        slider('Size', st.subSize, 24, 90, 'subSize'),
        slider('Outline', st.subOutline, 0, 6, 'subOutline'),
        slider('Position', st.subPos, 60, 100, 'subPos'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(spacing: 8, children: [
            for (final e in colors.entries)
              ChoiceChip(label: Text(e.key), selected: st.subColor == e.value, onSelected: (_) => set('subColor', e.value)),
          ]),
        ),
        SwitchListTile(
          dense: true,
          title: const Text('Background box'),
          value: st.subBackground,
          onChanged: (v) => set('subBackground', v),
        ),
      ]);
    }));
  }

  void _qualityMenu() {
    unawaited(_sheet<void>('Quality', (ctx, _) => Column(children: [
          for (final q in s.qualities) _option(ctx, q.label, s.quality == q, () => unawaited(s.selectQuality(q))),
        ])));
  }

  void _speedMenu() {
    unawaited(_sheet<void>('Playback speed', (ctx, _) => Column(children: [
          for (final v in const [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0])
            _option(ctx, v == 1.0 ? 'Normal' : '$v×', s.speed == v, () => unawaited(s.setSpeed(v))),
        ])));
  }

  void _serverMenu() {
    unawaited(_sheet<void>('Server & audio', (ctx, _) {
      return Column(children: [
        if (!s.offline)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: SegmentedButton<AudioType>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: AudioType.sub, label: Text('Sub')),
                ButtonSegment(value: AudioType.dub, label: Text('Dub')),
              ],
              selected: {s.type},
              onSelectionChanged: (v) {
                Navigator.pop(ctx);
                unawaited(s.switchAudio(v.first));
              },
            ),
          ),
        if (s.offline)
          const ListTile(dense: true, leading: Icon(Icons.download_done_rounded), title: Text('Playing the downloaded copy')),
        if (!s.offline && s.servers.isEmpty) const ListTile(dense: true, title: Text('Looking for servers…')),
        for (final sv in s.servers) _option(ctx, sv.serverName, sv == s.current, () => unawaited(s.selectServer(sv))),
      ]);
    }));
  }

  void _anime4kMenu() {
    final st = ref.read(settingsProvider);
    unawaited(_sheet<void>('Anime4K upscaling', (ctx, _) {
      return Column(children: [
        for (final pr in Anime4K.presets)
          _option(ctx, pr.$2, s.anime4kPreset == pr.$1, () {
            unawaited(ref.read(settingsProvider.notifier).set('anime4k', pr.$1));
            unawaited(s.applyAnime4K(pr.$1));
            if (pr.$1 != 'off' && _mobile && !st.anime4kNoteShown) {
              unawaited(ref.read(settingsProvider.notifier).set('anime4kNoteShown', true));
              s.showToast('Anime4K is GPU-heavy on phones. Turn it off if playback stutters.');
            }
          }, subtitle: pr.$1 == 'a' ? 'Recommended' : null),
      ]);
    }));
  }
}

/// "+1250 ms", "-300 ms", "0 ms".
String formatOffsetMs(int ms) => '${ms > 0 ? '+' : ''}$ms ms';

/// Subtitle sync in milliseconds, saved per season and applied to Korean /
/// imported subtitles in every episode. Tap the value to type an exact one.
class _SyncControl extends StatelessWidget {
  const _SyncControl({required this.session, required this.onChanged});
  final PlayerSession session;
  final VoidCallback onChanged;

  Future<void> _set(int ms) async {
    await session.setSubtitleOffsetMs(ms);
    onChanged();
  }

  Future<void> _type(BuildContext context) async {
    final c = TextEditingController(text: '${session.subtitleOffsetMs}');
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Subtitle sync (ms)'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: const InputDecoration(helperText: 'Positive = subtitles later, negative = earlier'),
          onSubmitted: (t) => Navigator.pop(ctx, int.tryParse(t.trim())),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(c.text.trim())), child: const Text('Set')),
        ],
      ),
    );
    if (v != null) await _set(v);
  }

  @override
  Widget build(BuildContext context) {
    final ms = session.subtitleOffsetMs;
    final applies = session.isFansubTrack(session.subtitle);
    Widget step(String label, int delta) => TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(52, 36), padding: const EdgeInsets.symmetric(horizontal: 6)),
          onPressed: () => _set(ms + delta),
          child: Text(label),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Subtitle sync')),
          TextButton(onPressed: ms == 0 ? null : () => _set(0), child: const Text('Reset')),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          step('−1 s', -1000),
          step('−100', -100),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _type(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(formatOffsetMs(ms), style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
            ),
          ),
          step('+100', 100),
          step('+1 s', 1000),
        ]),
        Text(
          applies
              ? 'Saved for this season: every episode uses it. Keys: G / H (Shift for 1 s).'
              : 'Saved for this season. Applies to Korean and imported subtitles only; this track is already in sync.',
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ]),
    );
  }
}
