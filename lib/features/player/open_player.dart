import 'package:flutter/material.dart';

import 'play_request.dart';
import 'player_screen.dart';

Future<void> openPlayer(BuildContext context, PlayRequest request) {
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, _, _) => PlayerScreen(request: request),
    transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
  ));
}
