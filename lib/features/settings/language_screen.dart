import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';

/// Shown once on first launch: pick the UI language. Saved in settings, so
/// it is not asked again (Settings > Language changes it later).
class LanguageScreen extends ConsumerStatefulWidget {
  const LanguageScreen({super.key});
  @override
  ConsumerState<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends ConsumerState<LanguageScreen> {
  late String _code = _systemDefault();

  static String _systemDefault() {
    final locales = WidgetsBinding.instance.platformDispatcher.locales;
    return locales.any((l) => l.languageCode == 'ko') ? 'ko' : 'en';
  }

  @override
  Widget build(BuildContext context) {
    // Preview the screen in the highlighted language.
    final s = Strings.forCode(_code);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.translate_rounded, size: 48, color: kAccent),
                const SizedBox(height: Gap.m),
                Text(s.chooseLanguage, textAlign: TextAlign.center, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: Gap.s),
                Text(s.chooseLanguageHint, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: Colors.white60)),
                const SizedBox(height: Gap.l),
                for (final e in Strings.languages.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.s),
                    child: _LanguageOption(
                      label: e.value,
                      selected: _code == e.key,
                      onTap: () => setState(() => _code = e.key),
                    ),
                  ),
                const SizedBox(height: Gap.m),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () => ref.read(settingsProvider.notifier).set('language', _code),
                  child: Text(s.continueLabel),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? kAccent.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? kAccent : Colors.white12, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(children: [
            Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? kAccent : Colors.white38),
          ]),
        ),
      ),
    );
  }
}
