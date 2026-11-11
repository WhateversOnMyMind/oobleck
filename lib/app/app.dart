import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/downloads/download_manager.dart';
import 'shell.dart';
import 'theme.dart';

class OobleckApp extends ConsumerStatefulWidget {
  const OobleckApp({super.key});
  @override
  ConsumerState<OobleckApp> createState() => _OobleckAppState();
}

class _OobleckAppState extends ConsumerState<OobleckApp> {
  @override
  void initState() {
    super.initState();
    // Start the download queue so interrupted downloads resume on launch.
    ref.read(downloadManagerProvider);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Oobleck',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(),
      themeMode: ThemeMode.dark,
      home: const Shell(),
    );
  }
}
