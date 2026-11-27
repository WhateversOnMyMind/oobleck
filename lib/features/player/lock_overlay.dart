import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/strings.dart';
import '../../app/strings_ui.dart';
import '../../app/theme.dart';

/// Covers the player while the screen is locked: stray touches (a hand
/// holding the phone, a pocket) do nothing. Any tap shows an Unlock button
/// for a few seconds; only that button unlocks.
class LockOverlay extends StatefulWidget {
  const LockOverlay({super.key, required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  State<LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends State<LockOverlay> {
  bool _visible = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _show();
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  void _show() {
    _hide?.cancel();
    if (!_visible) setState(() => _visible = true);
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tr = Strings.of(context);
    final pad = MediaQuery.paddingOf(context);
    return Stack(fit: StackFit.expand, children: [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _show,
        // Swallow drags and double taps too, so nothing seeks or changes volume.
        onDoubleTap: _show,
        onVerticalDragStart: (_) => _show(),
        onHorizontalDragStart: (_) => _show(),
        child: const SizedBox.expand(),
      ),
      Positioned(
        top: Gap.m + pad.top,
        left: 0,
        right: 0,
        child: IgnorePointer(
          ignoring: !_visible,
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    minimumSize: const Size(kMinTouch, kMinTouch),
                  ),
                  onPressed: widget.onUnlock,
                  icon: const Icon(Icons.lock_open_rounded),
                  label: Text(tr.unlockControls),
                ),
                const SizedBox(height: Gap.s),
                Text(tr.lockedHint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70, shadows: const [Shadow(blurRadius: 4)])),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}
