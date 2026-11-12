import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../core/storage/app_db.dart';

/// Typed view over the settings box.
class AppSettings {
  const AppSettings({
    this.audio = AudioType.sub,
    this.quality = 'best',
    this.serverOrder = const ['HD-1', 'HD-2', 'Vidstream-1', 'Vidstream-2', 'Kiwi'],
    this.autoNext = true,
    this.skipIntroButton = true,
    this.autoKoreanSubs = true,
    this.subtitleLanguage = 'en',
    this.subSize = 46,
    this.subColor = 'FFFFFF',
    this.subOutline = 2.5,
    this.subBackground = false,
    this.subPos = 100,
    this.anime4k = 'off',
    this.anime4kNoteShown = false,
    this.maxConcurrent = 2,
    this.segmentConcurrency = 6,
    this.downloadDir,
    this.openSubtitlesKey = '',
    this.openSubtitlesUser = '',
    this.openSubtitlesPass = '',
    this.megaplayAesKey = '',
    this.megaplayIv = '',
    this.megaplayTokenKey = '',
    this.enableKiwi = true,
  });

  final AudioType audio;
  final String quality; // 'best' | '1080' | '720' | '480' | '360'
  final List<String> serverOrder;
  final bool autoNext;
  final bool skipIntroButton;

  /// Find, save and turn on a Korean fansub for each episode without asking.
  final bool autoKoreanSubs;
  final String subtitleLanguage;
  final double subSize;
  final String subColor; // RRGGBB
  final double subOutline;
  final bool subBackground;
  final double subPos;
  final String anime4k; // off | a | b | c
  final bool anime4kNoteShown;
  final int maxConcurrent;
  final int segmentConcurrency;
  final String? downloadDir;
  final String openSubtitlesKey;
  final String openSubtitlesUser;
  final String openSubtitlesPass;
  final String megaplayAesKey;
  final String megaplayIv;
  final String megaplayTokenKey;
  final bool enableKiwi;

  static AppSettings load(AppDb db) {
    T g<T>(String k, T d) => db.setting<T>(k) ?? d;
    return AppSettings(
      audio: g<String>('audio', 'sub') == 'dub' ? AudioType.dub : AudioType.sub,
      quality: g('quality', 'best'),
      serverOrder: (db.setting<List>('serverOrder')?.cast<String>()) ?? const AppSettings().serverOrder,
      autoNext: g('autoNext', true),
      skipIntroButton: g('skipIntroButton', true),
      autoKoreanSubs: g('autoKoreanSubs', true),
      subtitleLanguage: g('subtitleLanguage', 'en'),
      subSize: g<num>('subSize', 46).toDouble(),
      subColor: g('subColor', 'FFFFFF'),
      subOutline: g<num>('subOutline', 2.5).toDouble(),
      subBackground: g('subBackground', false),
      subPos: g<num>('subPos', 100).toDouble(),
      anime4k: g('anime4k', 'off'),
      anime4kNoteShown: g('anime4kNoteShown', false),
      maxConcurrent: g('maxConcurrent', 2),
      segmentConcurrency: g('segmentConcurrency', 6),
      downloadDir: db.setting<String>('downloadDir'),
      openSubtitlesKey: g('openSubtitlesKey', ''),
      openSubtitlesUser: g('openSubtitlesUser', ''),
      openSubtitlesPass: g('openSubtitlesPass', ''),
      megaplayAesKey: g('megaplayAesKey', ''),
      megaplayIv: g('megaplayIv', ''),
      megaplayTokenKey: g('megaplayTokenKey', ''),
      enableKiwi: g('enableKiwi', true),
    );
  }
}

class SettingsNotifier extends Notifier<AppSettings> {
  late AppDb _db;

  @override
  AppSettings build() {
    _db = ref.watch(dbProvider);
    return AppSettings.load(_db);
  }

  Future<void> set(String key, Object? value) async {
    await _db.setSetting(key, value);
    state = AppSettings.load(_db);
  }
}

/// Overridden in `main()` once the database is open.
final dbProvider = Provider<AppDb>((ref) => throw UnimplementedError('dbProvider not overridden'));

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
