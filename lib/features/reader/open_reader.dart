import 'package:flutter/material.dart';

import 'reader_screen.dart';

/// Opens the reader at [chapterId] of the series [mangaKey].
Future<void> openReader(BuildContext context, {required String mangaKey, required String chapterId}) =>
    Navigator.of(context).push(PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => ReaderScreen(mangaKey: mangaKey, chapterId: chapterId),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      transitionDuration: const Duration(milliseconds: 180),
    ));
