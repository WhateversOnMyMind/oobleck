import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/strings.dart';
import '../manga/manga_strings.dart';
import 'page_paint.dart';
import 'reader_controller.dart';

/// Decoded page images are kept at most this tall; taller strips are scaled
/// down to stay inside GPU texture limits.
const _maxDecodeHeight = 16000;

/// One page: loads the bytes, decodes them no larger than needed, and draws
/// them (sharpened and upscaled when they are smaller than the screen).
class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.pageRef,
    required this.load,
    required this.number,
    this.fit = BoxFit.contain,
    this.displayWidth,
    this.onSize,
    this.upscale = false,
    this.sharpness = 0.5,
    this.onLongPress,
    this.placeholderAspect = 1.45,
  });

  final ReaderPageRef pageRef;
  final Future<Uint8List> Function(ReaderPageRef) load;

  /// 1-based number shown while loading.
  final int number;
  final BoxFit fit;

  /// Logical width the page will be drawn at (long-strip mode); decoding is
  /// capped to what that needs. Null: use the screen size.
  final double? displayWidth;

  /// Reports the page's real size once known.
  final void Function(Size size)? onSize;
  final bool upscale;
  final double sharpness;
  final void Function(Uint8List bytes)? onLongPress;

  /// Height / width used before the real size is known.
  final double placeholderAspect;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  ui.Image? _image;
  Uint8List? _bytes;
  Object? _error;
  int _attempt = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(ReaderPage old) {
    super.didUpdateWidget(old);
    if (old.pageRef.id != widget.pageRef.id) {
      _image?.dispose();
      _image = null;
      _bytes = null;
      _error = null;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final attempt = ++_attempt;
    final mq = MediaQuery.of(context);
    final dpr = mq.devicePixelRatio;
    // Decode up to 1.5x what the screen needs (room for zooming), never more than native.
    final targetW = ((widget.displayWidth ?? mq.size.width) * dpr * 1.5).round();
    try {
      final bytes = await widget.load(widget.pageRef);
      if (!mounted || attempt != _attempt) return;
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final codec = await ui.instantiateImageCodecWithSize(buffer, getTargetSize: (w, h) {
        var tw = w;
        if (w > targetW) tw = targetW;
        if (h * tw / w > _maxDecodeHeight) tw = (w * _maxDecodeHeight / h).floor();
        return tw == w ? ui.TargetImageSize(width: w, height: h) : ui.TargetImageSize(width: tw);
      });
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted || attempt != _attempt) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = frame.image;
        _bytes = bytes;
        _error = null;
      });
      widget.onSize?.call(Size(frame.image.width.toDouble(), frame.image.height.toDouble()));
    } catch (e) {
      if (!mounted || attempt != _attempt) return;
      setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _attempt++;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    if (img != null) {
      final child = paintPage(img, fit: widget.fit, upscale: widget.upscale, sharpness: widget.sharpness);
      final lp = widget.onLongPress;
      if (lp == null || _bytes == null) return child;
      return GestureDetector(onLongPress: () => lp(_bytes!), child: child);
    }
    final tr = Strings.of(context);
    final body = _error != null
        ? Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.broken_image_outlined, size: 40, color: Colors.white38),
            const SizedBox(height: 8),
            Text(tr.pageFailed, style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () {
                setState(() => _error = null);
                unawaited(_load());
              },
              icon: const Icon(Icons.refresh_rounded),
              label: Text(tr.retry),
            ),
          ])
        : Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${widget.number}', style: const TextStyle(color: Colors.white24, fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24)),
          ]);
    if (widget.displayWidth != null) {
      return SizedBox(
        width: widget.displayWidth,
        height: widget.displayWidth! * widget.placeholderAspect,
        child: Center(child: body),
      );
    }
    return Center(child: body);
  }
}
