import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/downloads/download_manager.dart';
import '../features/settings/language_screen.dart';
import '../features/sync/sync_controller.dart';
import 'providers.dart';
import 'strings.dart';
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
    final language = ref.watch(settingsProvider.select((s) => s.language));
    return MaterialApp(
      title: 'Oobleck',
      locale: Strings.forCode(language).locale,
      supportedLocales: const [Locale('en'), Locale('ko')],
      localizationsDelegates: const [
        StringsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(),
      themeMode: ThemeMode.dark,
      // First launch asks for the language once; after that it is remembered.
      home: language == null ? const LanguageScreen() : const Shell(),
    );
  }
}
