import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/downloads/download_manager.dart';
import '../features/sync/sync_controller.dart';
import 'shell.dart';
import 'theme.dart';

class OobleckApp extends ConsumerStatefulWidget {
  const OobleckApp({super.key});
  @override
  ConsumerState<OobleckApp> createState() => _OobleckAppState();
}

class _OobleckAppState extends ConsumerState<OobleckApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // Start the download queue so interrupted downloads resume on launch.
    ref.read(downloadManagerProvider);
    WidgetsBinding.instance.addObserver(this);
    // Pull history from other devices on launch (no-op when signed out).
    ref.read(syncProvider.notifier).syncSoon();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.read(syncProvider.notifier).syncSoon();
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
