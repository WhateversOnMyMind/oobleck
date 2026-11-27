import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../ui/widgets.dart';
import '../manga/manga_providers.dart';
import '../manga/manga_strings.dart';
import 'paged_reader.dart';
import 'reader_controller.dart';
import 'reader_overlay.dart';
import 'reader_settings.dart';
import 'scroll_reader.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.mangaKey, required this.chapterId});
  final String mangaKey;
  final String chapterId;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  late final ReaderController c;
  final _focus = FocusNode();
  Object? _openError;
  bool _fullscreen = false;
  static const _desktopWindow = MethodChannel('com.alexmercerind/media_kit_video');

  bool get _mobile => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    final site = ref.read(mangaSourceProvider);
    final source = site.id == widget.mangaKey.split(':').first ? site : null;
    c = ReaderController(
      db: ref.read(dbProvider),
      source: source,
      cache: ref.read(pageCacheProvider),
      mangaKey: widget.mangaKey,
      settings: () => ref.read(readerSettingsProvider),
    )..addListener(_changed);
    unawaited(c.open(widget.chapterId).catchError((Object e) {
      if (mounted) setState(() => _openError = e);
    }));
    final s = ref.read(readerSettingsProvider);
    if (s.keepScreenOn) unawaited(WakelockPlus.enable().catchError((_) {}));
    if (s.fullscreen && _mobile) unawaited(_setFullscreen(true));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    c.dispose();
    _focus.dispose();
    unawaited(WakelockPlus.disable().catchError((_) {}));
    if (_fullscreen) unawaited(_setFullscreen(false));
    super.dispose();
  }

  Future<void> _setFullscreen(bool on) async {
    _fullscreen = on;
    try {
      if (_mobile) {
        await SystemChrome.setEnabledSystemUIMode(on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
      } else {
        await _desktopWindow.invokeMethod(on ? 'Utils.EnterNativeFullscreen' : 'Utils.ExitNativeFullscreen');
      }
    } catch (_) {
      // not available on this platform
    }
  }

  void _close() => Navigator.of(context).maybePop();

  void _onTap(TapAction a) {
    switch (a) {
      case TapAction.menu:
        c.toggleMenu();
        if (_mobile && ref.read(readerSettingsProvider).fullscreen) unawaited(_setFullscreen(!c.menuVisible));
      case TapAction.next:
        if (c.menuVisible) return c.toggleMenu(false);
        c.command(const PageStep(1));
      case TapAction.previous:
        if (c.menuVisible) return c.toggleMenu(false);
        c.command(const PageStep(-1));
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final s = ref.read(readerSettingsProvider);
    final rtl = c.mode == ReaderMode.rtl;
    if (k == LogicalKeyboardKey.audioVolumeDown || k == LogicalKeyboardKey.audioVolumeUp) {
      if (!s.volumeKeys) return KeyEventResult.ignored;
      c.command(PageStep(k == LogicalKeyboardKey.audioVolumeDown ? 1 : -1));
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.pageDown || k == LogicalKeyboardKey.space) {
      c.command(PageStep(HardwareKeyboard.instance.isShiftPressed && k == LogicalKeyboardKey.space ? -1 : 1));
    } else if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.pageUp) {
      c.command(const PageStep(-1));
    } else if (k == LogicalKeyboardKey.arrowRight) {
      c.command(PageStep(rtl ? -1 : 1));
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      c.command(PageStep(rtl ? 1 : -1));
    } else if (k == LogicalKeyboardKey.home) {
      c.command(const JumpTo(0));
    } else if (k == LogicalKeyboardKey.end) {
      final n = c.current?.pages.length ?? 0;
      if (n > 0) c.command(JumpTo(n - 1));
    } else if (k == LogicalKeyboardKey.keyN && c.nextChapter != null) {
      unawaited(c.goTo(c.nextChapter!));
    } else if (k == LogicalKeyboardKey.keyP && c.previousChapter != null) {
      unawaited(c.goTo(c.previousChapter!));
    } else if (k == LogicalKeyboardKey.keyM || k == LogicalKeyboardKey.enter) {
      c.toggleMenu();
    } else if (k == LogicalKeyboardKey.keyF || k == LogicalKeyboardKey.f11) {
      unawaited(_setFullscreen(!_fullscreen));
    } else if (k == LogicalKeyboardKey.escape) {
      if (c.menuVisible) {
        c.toggleMenu(false);
      } else if (_fullscreen && !_mobile) {
        unawaited(_setFullscreen(false));
      } else {
        _close();
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Future<void> _pageActions(Uint8List bytes) async {
    final tr = Strings.of(context);
    unawaited(HapticFeedback.mediumImpact());
    final save = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.save_alt_rounded),
          title: Text(tr.savePage),
          onTap: () => Navigator.pop(context, true),
        ),
      ),
    );
    if (save != true) return;
    final rc = c.current;
    final name = '${c.manga.title} ${rc?.chapter.title ?? ''} p${c.page + 1}.${_ext(bytes)}'.replaceAll(RegExp(r'[<>:"/\\|?*]'), '');
    try {
      // The picker writes the bytes itself (a content URI on phones).
      final saved = await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: 'image/${_ext(bytes)}');
      if (saved != null && saved.scheme == 'file' && !File.fromUri(saved).existsSync()) {
        await File.fromUri(saved).writeAsBytes(bytes);
      }
      if (saved != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr.pageSaved)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  static String _ext(Uint8List b) {
    if (b.length > 4 && b[0] == 0x89 && b[1] == 0x50) return 'png';
    if (b.length > 12 && b[8] == 0x57 && b[9] == 0x45) return 'webp';
    if (b.length > 3 && b[0] == 0x47 && b[1] == 0x49) return 'gif';
    return 'jpg';
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(readerSettingsProvider);
    final tr = Strings.of(context);
    final bg = s.background.color;
    final rc = _openError == null && c.segments.isNotEmpty ? c.current : null;

    Widget body;
    if (_openError != null) {
      body = ErrorState(error: _openError!, onRetry: () => Navigator.of(context).maybePop());
    } else if (rc == null || (rc.loading && rc.pages.isEmpty)) {
      body = const Center(child: SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2.5)));
    } else if (rc.error != null && rc.pages.isEmpty) {
      body = ErrorState(error: rc.error!, onRetry: c.retry);
    } else if (rc.pages.isEmpty) {
      body = EmptyState(icon: Icons.image_not_supported_outlined, title: tr.chapterEmpty);
    } else if (c.mode.isPaged) {
      body = PagedReader(
        key: ValueKey('paged-${c.generation}-${c.mode.name}'),
        c: c,
        settings: s,
        onTap: _onTap,
        onLongPressPage: _pageActions,
      );
    } else {
      body = ScrollReader(
        key: ValueKey('scroll-${c.generation}-${c.mode.name}'),
        c: c,
        settings: s,
        gaps: c.mode == ReaderMode.continuous,
        onTap: _onTap,
        onLongPressPage: _pageActions,
      );
    }

    if (s.grayscale) {
      body = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126, 0.7152, 0.0722, 0, 0, //
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: body,
      );
    }

    final total = rc?.pages.length ?? 0;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) c.flush();
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Scaffold(
          backgroundColor: bg,
          body: Stack(fit: StackFit.expand, children: [
            body,
            if (s.dim > 0) IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: s.dim))),
            if (s.showPageNumber && total > 0 && !c.menuVisible)
              Positioned(
                bottom: MediaQuery.paddingOf(context).bottom + 8,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                      child: Text('${(c.page + 1).clamp(1, total)} / $total',
                          style: const TextStyle(color: Colors.white70, fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
                    ),
                  ),
                ),
              ),
            // A back button stays reachable before the chapter has loaded.
            if (rc == null || rc.pages.isEmpty)
              SafeArea(child: Align(alignment: Alignment.topLeft, child: BackButton(color: bg == Colors.white ? Colors.black : Colors.white))),
            if (rc != null)
              IgnorePointer(
                ignoring: !c.menuVisible,
                child: AnimatedOpacity(
                  opacity: c.menuVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: ReaderOverlay(c: c, onClose: _close),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
