import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Anime4K (MIT, bloc97/Anime4K) real-time upscaling presets for mpv.
/// Shader chains follow the repository's GLSL_Instructions (verified against
/// the bundled files in `assets/shaders/anime4k/`).
class Anime4K {
  static const List<(String id, String label)> presets = [
    ('off', 'Off'),
    ('a', 'Mode A (Fast)'),
    ('b', 'Mode B (Fast)'),
    ('c', 'Mode C (Fast)'),
    ('a_hq', 'Mode A (HQ)'),
    ('b_hq', 'Mode B (HQ)'),
    ('c_hq', 'Mode C (HQ)'),
  ];

  static const String defaultPreset = 'a';

  static String label(String id) => presets.firstWhere((e) => e.$1 == id, orElse: () => presets.first).$2;

  /// Ordered shader file names for a preset.
  static List<String> chain(String id) {
    const tail = ['Anime4K_AutoDownscalePre_x2.glsl', 'Anime4K_AutoDownscalePre_x4.glsl'];
    switch (id) {
      case 'a':
        return ['Anime4K_Clamp_Highlights.glsl', 'Anime4K_Restore_CNN_M.glsl', 'Anime4K_Upscale_CNN_x2_M.glsl', ...tail, 'Anime4K_Upscale_CNN_x2_S.glsl'];
      case 'b':
        return ['Anime4K_Clamp_Highlights.glsl', 'Anime4K_Restore_CNN_Soft_M.glsl', 'Anime4K_Upscale_CNN_x2_M.glsl', ...tail, 'Anime4K_Upscale_CNN_x2_S.glsl'];
      case 'c':
        return ['Anime4K_Clamp_Highlights.glsl', 'Anime4K_Upscale_Denoise_CNN_x2_M.glsl', ...tail, 'Anime4K_Upscale_CNN_x2_S.glsl'];
      case 'a_hq':
        return ['Anime4K_Clamp_Highlights.glsl', 'Anime4K_Restore_CNN_VL.glsl', 'Anime4K_Upscale_CNN_x2_VL.glsl', ...tail, 'Anime4K_Upscale_CNN_x2_M.glsl'];
      case 'b_hq':
        return ['Anime4K_Clamp_Highlights.glsl', 'Anime4K_Restore_CNN_Soft_VL.glsl', 'Anime4K_Upscale_CNN_x2_VL.glsl', ...tail, 'Anime4K_Upscale_CNN_x2_M.glsl'];
      case 'c_hq':
        return ['Anime4K_Clamp_Highlights.glsl', 'Anime4K_Upscale_Denoise_CNN_x2_VL.glsl', ...tail, 'Anime4K_Upscale_CNN_x2_M.glsl'];
      default:
        return const [];
    }
  }

  /// Every shader file used by any preset.
  static List<String> get allFiles => {for (final e in presets) ...chain(e.$1)}.toList();

  static String get separator => Platform.isWindows ? ';' : ':';

  /// mpv `glsl-shaders` value for a preset ('' for off).
  static String shaderList(String id, String dir) =>
      chain(id).map((f) => p.join(dir, f)).join(separator);

  /// Copies the bundled shaders to [supportDir]/shaders (mpv needs real
  /// paths). Idempotent. Returns the directory.
  static Future<String> install(String supportDir) async {
    final dir = Directory(p.join(supportDir, 'shaders'))..createSync(recursive: true);
    for (final f in allFiles) {
      final out = File(p.join(dir.path, f));
      if (out.existsSync() && out.lengthSync() > 0) continue;
      try {
        final data = await rootBundle.load('assets/shaders/anime4k/$f');
        await out.writeAsBytes(data.buffer.asUint8List(), flush: true);
      } catch (_) {
        // Missing asset: preset will simply be unavailable.
      }
    }
    return dir.path;
  }

  /// Whether every file of [id] is present in [dir].
  static bool available(String id, String dir) => chain(id).every((f) => File(p.join(dir, f)).existsSync());
}
