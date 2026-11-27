import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Desktop ways to go back, everywhere in the app: Esc, Alt+Left, the
/// keyboard's Back key and the mouse's back button. They pop the top route
/// (page, sheet, dialog or menu) and do nothing on the first screen.
///
/// Wrap the app's content with it in `MaterialApp.builder`. A screen that
/// handles Esc itself (the player) wins, because it is closer to the focus.
class BackShortcuts extends StatelessWidget {
  const BackShortcuts({super.key, required this.navigatorKey, required this.child});
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  void _back() => navigatorKey.currentState?.maybePop();

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) {
        if (e.kind == PointerDeviceKind.mouse && e.buttons == kBackMouseButton) _back();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _back,
          const SingleActivator(LogicalKeyboardKey.browserBack): _back,
          const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _back,
        },
        child: child,
      ),
    );
  }
}
