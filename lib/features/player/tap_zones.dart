import 'package:flutter/material.dart';

enum TapZone { back, middle, forward }

/// Left 40 % skips back, right 40 % skips forward, the middle plays/pauses.
TapZone zoneAt(double x, double width) {
  if (x < width * 0.4) return TapZone.back;
  if (x > width * 0.6) return TapZone.forward;
  return TapZone.middle;
}

/// The player's touch layer: tap shows/hides the controls, double tap skips
/// by side, holding the right half plays fast until released.
///
/// The side comes from the double tap's own position (`onDoubleTapDown`).
/// It used to come from `onTapDown`, which belongs to the single-tap
/// recognizer: when the double tap wins, that callback does not fire, so a
/// stale position from an earlier tap decided the direction and every double
/// tap skipped forward (reported 2026-11-23).
class TapZones extends StatefulWidget {
  const TapZones({
    super.key,
    required this.onTap,
    required this.onDoubleTap,
    this.onHoldRight,
    this.onVerticalDragStart,
    this.onVerticalDragUpdate,
  });

  final VoidCallback onTap;
  final ValueChanged<TapZone> onDoubleTap;

  /// True when a press on the right half is held, false when it ends.
  final ValueChanged<bool>? onHoldRight;
  final GestureDragStartCallback? onVerticalDragStart;
  final GestureDragUpdateCallback? onVerticalDragUpdate;

  @override
  State<TapZones> createState() => _TapZonesState();
}

class _TapZonesState extends State<TapZones> {
  TapZone _zone = TapZone.middle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTapDown: (d) => _zone = zoneAt(d.localPosition.dx, box.maxWidth),
        onDoubleTap: () => widget.onDoubleTap(_zone),
        onLongPressStart: (d) {
          if (d.localPosition.dx > box.maxWidth / 2) widget.onHoldRight?.call(true);
        },
        onLongPressEnd: (_) => widget.onHoldRight?.call(false),
        onLongPressCancel: () => widget.onHoldRight?.call(false),
        onVerticalDragStart: widget.onVerticalDragStart,
        onVerticalDragUpdate: widget.onVerticalDragUpdate,
        child: const SizedBox.expand(),
      ),
    );
  }
}
