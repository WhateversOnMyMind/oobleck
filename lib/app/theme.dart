import 'package:flutter/material.dart';

/// The single accent colour used across the app.
const Color kAccent = Color(0xFF8E7CFF);
const Color kBackground = Color(0xFF0D0D12);
const Color kSurface = Color(0xFF16161E);
const Color kSurfaceHigh = Color(0xFF1E1E28);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kAccent,
    brightness: Brightness.dark,
    surface: kBackground,
  ).copyWith(
    primary: kAccent,
    // Near-black on the accent reads better than the generated dark purple.
    onPrimary: kBackground,
    surfaceContainer: kSurface,
    surfaceContainerHigh: kSurfaceHigh,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark);
  final cardShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card));
  return base.copyWith(
    scaffoldBackgroundColor: kBackground,
    // Keep full-size (48 dp) hit targets on desktop too; the default there is compact.
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: const AppBarTheme(
      backgroundColor: kBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    textTheme: base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
    cardTheme: CardThemeData(color: kSurface, elevation: 0, margin: EdgeInsets.zero, shape: cardShape),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kSurface,
      indicatorColor: kAccent.withValues(alpha: 0.25),
      surfaceTintColor: Colors.transparent,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: kSurface,
      indicatorColor: kAccent.withValues(alpha: 0.25),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      // One step lighter than sheets and dialogs, so a field is visible on them too.
      fillColor: kSurfaceHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.card), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        borderSide: BorderSide(color: kAccent.withValues(alpha: 0.7), width: 1.5),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kSurface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kSurface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.dialog)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: kSurfaceHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.small)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF2A2A36),
      contentTextStyle: base.textTheme.bodyMedium?.copyWith(color: Colors.white),
      actionTextColor: kAccent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.small)),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      decoration: BoxDecoration(color: const Color(0xF22A2A36), borderRadius: BorderRadius.circular(8)),
      textStyle: base.textTheme.bodySmall?.copyWith(color: Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 48), shape: cardShape, textStyle: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48), shape: cardShape),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(minimumSize: const Size(48, 40))),
    chipTheme: ChipThemeData(
      backgroundColor: kSurface,
      side: const BorderSide(color: Colors.white12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.small)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: Colors.white70,
      subtitleTextStyle: base.textTheme.bodyMedium?.copyWith(color: Colors.white60, fontSize: 13, height: 1.3),
    ),
    dividerTheme: const DividerThemeData(color: Colors.white10, space: 1, thickness: 1),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: kAccent),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => Colors.white.withValues(alpha: s.contains(WidgetState.hovered) || s.contains(WidgetState.dragged) ? 0.45 : 0.22),
      ),
      radius: const Radius.circular(8),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}

/// Shared spacing scale.
class Gap {
  static const double xs = 4, s = 8, m = 16, l = 24, xl = 32;
}

/// Shared corner radii: cards, covers, buttons and inputs use [card];
/// chips, menus, snackbars and thumbnails use [small].
class Radii {
  static const double small = 10, card = 14, dialog = 20;
}

/// Smallest comfortable touch target (Material / Android guideline).
const double kMinTouch = 48;
