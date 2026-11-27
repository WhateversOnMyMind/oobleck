import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings.dart';
import '../../core/storage/app_db.dart';

/// How chapters are laid out.
enum ReaderMode {
  /// Webtoon for long strips, paged for single pages (decided per chapter).
  auto,

  /// One continuous strip, no gaps.
  webtoon,

  /// Vertical scrolling with a small gap between pages.
  continuous,
  ltr,
  rtl,

  /// One page at a time, turned by swiping up and down.
  vertical;

  bool get isPaged => this == ltr || this == rtl || this == vertical;
  bool get isScroll => this == webtoon || this == continuous;

  static ReaderMode parse(String? s, [ReaderMode fallback = auto]) => values.where((v) => v.name == s).firstOrNull ?? fallback;

  IconData get icon => switch (this) {
        auto => Icons.auto_awesome_motion_rounded,
        webtoon => Icons.view_day_rounded,
        continuous => Icons.view_agenda_rounded,
        ltr => Icons.arrow_forward_rounded,
        rtl => Icons.arrow_back_rounded,
        vertical => Icons.swap_vert_rounded,
      };
}

/// Page fit for paged modes.
enum PageScale {
  fitScreen,
  fitWidth,
  fitHeight,
  original;

  static PageScale parse(String? s) => values.where((v) => v.name == s).firstOrNull ?? fitScreen;

  BoxFit get boxFit => switch (this) {
        fitScreen => BoxFit.contain,
        fitWidth => BoxFit.fitWidth,
        fitHeight => BoxFit.fitHeight,
        original => BoxFit.none,
      };
}

/// Where taps go: previous page, next page or toggle the menu.
enum TapLayout {
  lShape,
  kindle,
  edges,
  leftRight,
  off;

  static TapLayout parse(String? s) => values.where((v) => v.name == s).firstOrNull ?? lShape;
}

enum ReaderBackground {
  black,
  gray,
  white;

  static ReaderBackground parse(String? s) => values.where((v) => v.name == s).firstOrNull ?? black;

  Color get color => switch (this) {
        black => Colors.black,
        gray => const Color(0xFF202024),
        white => Colors.white,
      };
}

/// App-wide reader preferences, stored in the settings box as `reader.*`.
class ReaderSettings {
  const ReaderSettings({
    this.mode = ReaderMode.auto,
    this.scale = PageScale.fitScreen,
    this.tapLayout = TapLayout.lShape,
    this.invertTaps = false,
    this.background = ReaderBackground.black,
    this.upscale = true,
    this.sharpness = 0.5,
    this.webtoonPadding = 0,
    this.keepScreenOn = true,
    this.showPageNumber = true,
    this.volumeKeys = true,
    this.fullscreen = true,
    this.dim = 0,
    this.brightness,
    this.grayscale = false,
    this.autoNextChapter = true,
    this.incognito = false,
    this.dualPage = false,
    this.preload = 4,
  });

  final ReaderMode mode;
  final PageScale scale;
  final TapLayout tapLayout;
  final bool invertTaps;
  final ReaderBackground background;
  final bool upscale;

  /// Sharpening strength for the upscaler, 0..1.
  final double sharpness;

  /// Webtoon side padding as a fraction of the width on each side, 0..0.3.
  final double webtoonPadding;
  final bool keepScreenOn;
  final bool showPageNumber;
  final bool volumeKeys;
  final bool fullscreen;

  /// Extra darkening on top of the pages, 0..0.8.
  final double dim;

  /// Reader brightness on phones, [Dimming.darkest]..1; null keeps the phone's own.
  final double? brightness;
  final bool grayscale;
  final bool autoNextChapter;
  final bool incognito;
  final bool dualPage;

  /// Pages decoded ahead of the current one.
  final int preload;

  static const prefix = 'reader.';

  static ReaderSettings load(AppDb db) {
    T g<T>(String k, T d) => db.setting<T>('$prefix$k') ?? d;
    double n(String k, double d) => (db.setting<num>('$prefix$k') ?? d).toDouble();
    return ReaderSettings(
      mode: ReaderMode.parse(db.setting<String>('${prefix}mode')),
      scale: PageScale.parse(db.setting<String>('${prefix}scale')),
      tapLayout: TapLayout.parse(db.setting<String>('${prefix}tapLayout')),
      invertTaps: g('invertTaps', false),
      background: ReaderBackground.parse(db.setting<String>('${prefix}background')),
      upscale: g('upscale', true),
      sharpness: n('sharpness', 0.5),
      webtoonPadding: n('webtoonPadding', 0),
      keepScreenOn: g('keepScreenOn', true),
      showPageNumber: g('showPageNumber', true),
      volumeKeys: g('volumeKeys', true),
      fullscreen: g('fullscreen', true),
      dim: n('dim', 0),
      brightness: db.setting<num>('${prefix}brightness')?.toDouble(),
      grayscale: g('grayscale', false),
      autoNextChapter: g('autoNextChapter', true),
      incognito: g('incognito', false),
      dualPage: g('dualPage', false),
      preload: g('preload', 4),
    );
  }
}

class ReaderSettingsNotifier extends Notifier<ReaderSettings> {
  @override
  ReaderSettings build() => ReaderSettings.load(ref.watch(dbProvider));

  /// [value] is a bool, num or enum (stored by name).
  Future<void> set(String key, Object? value) async {
    final db = ref.read(dbProvider);
    await db.setSetting('${ReaderSettings.prefix}$key', value is Enum ? value.name : value);
    state = ReaderSettings.load(db);
  }
}

final readerSettingsProvider = NotifierProvider<ReaderSettingsNotifier, ReaderSettings>(ReaderSettingsNotifier.new);

/// What a tap at [x],[y] (fractions of the viewport) should do.
enum TapAction { previous, next, menu }

TapAction tapActionAt(TapLayout layout, double x, double y, {bool invert = false, bool rtl = false}) {
  TapAction raw;
  switch (layout) {
    case TapLayout.off:
      return TapAction.menu;
    case TapLayout.leftRight:
      raw = x < 0.5 ? TapAction.previous : TapAction.next;
    case TapLayout.edges:
      raw = x < 0.25 ? TapAction.previous : (x > 0.75 ? TapAction.next : TapAction.menu);
    case TapLayout.kindle:
      // Narrow left strip goes back; most of the screen goes forward; top is the menu.
      raw = y < 0.25 ? TapAction.menu : (x < 0.33 ? TapAction.previous : TapAction.next);
    case TapLayout.lShape:
      // Top third and left third (minus the bottom) go back; right and bottom go forward.
      if (x > 0.33 && x < 0.66 && y > 0.33 && y < 0.66) return TapAction.menu;
      raw = (y < 0.33 || (x < 0.33 && y < 0.66)) ? TapAction.previous : TapAction.next;
  }
  if (raw == TapAction.menu) return raw;
  // In right-to-left books the left side moves forward.
  final flip = invert != (rtl && (layout == TapLayout.leftRight || layout == TapLayout.edges || layout == TapLayout.kindle));
  if (!flip) return raw;
  return raw == TapAction.previous ? TapAction.next : TapAction.previous;
}
