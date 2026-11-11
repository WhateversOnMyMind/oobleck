import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../log.dart';

/// AES key / IV / token HMAC key used by megaplay's player.
///
/// Bundled constants were observed 2026-11-11 (last upstream change 2026-09-13).
/// They can be overridden in Settings > Advanced, and [refresh] tries to
/// re-extract them from the live player script.
class MegaplayKeys {
  MegaplayKeys({
    this.aesKey = defaultAesKey,
    this.iv = defaultIv,
    this.tokenKey = defaultTokenKey,
  });

  static const String defaultAesKey = r'i?LMTAx0Q6,:}50U';
  static const String defaultIv = r"W0;27ToaUpl_P%'c";
  static const String defaultTokenKey = r'MpCdnT0k3n!9f2K#xQ7vL5mR8wN1pY4s';

  String aesKey;
  String iv;
  String tokenKey;

  /// UTF-8 key zero-padded (or truncated) to 32 bytes.
  Uint8List get aesKeyBytes {
    final raw = Uint8List.fromList(aesKey.codeUnits.length > 32
        ? aesKey.codeUnits.sublist(0, 32)
        : aesKey.codeUnits);
    final out = Uint8List(32)..setRange(0, raw.length, raw);
    return out;
  }

  Uint8List get ivBytes {
    final raw = iv.codeUnits;
    final out = Uint8List(16)..setRange(0, raw.length > 16 ? 16 : raw.length, raw);
    return out;
  }

  void reset() {
    aesKey = defaultAesKey;
    iv = defaultIv;
    tokenKey = defaultTokenKey;
  }

  /// Best effort: fetch the player script referenced by the embed page and
  /// regex out the key material. Returns true when something was updated.
  /// On any failure the existing (bundled or overridden) values stay.
  Future<bool> refresh(Dio dio, {String embedUrl = 'https://megaplay.buzz/'}) async {
    try {
      final page = await dio.get<String>(embedUrl,
          options: Options(headers: {'Referer': 'https://anikototv.to/'}, responseType: ResponseType.plain));
      final m = RegExp(r'''src=["']([^"']*e1-player[^"']*\.js[^"']*)["']''').firstMatch(page.data ?? '');
      if (m == null) {
        Log.d('keys', 'player script not found in embed page');
        return false;
      }
      final scriptUrl = Uri.parse(embedUrl).resolve(m.group(1)!).toString();
      final js = (await dio.get<String>(scriptUrl,
              options: Options(headers: {'Referer': embedUrl}, responseType: ResponseType.plain)))
          .data ??
          '';
      return applyFromScript(js);
    } catch (e) {
      Log.d('keys', 'refresh failed: $e');
      return false;
    }
  }

  /// Heuristic extraction, exposed for tests.
  bool applyFromScript(String js) {
    var changed = false;
    String? find(List<RegExp> res) {
      for (final r in res) {
        final m = r.firstMatch(js);
        if (m != null) return m.group(1);
      }
      return null;
    }

    final k = find([
      RegExp(r'''(?:aesKey|secretKey|\bkey)\s*[:=]\s*["']([^"'\n]{16,32})["']'''),
      RegExp(r'''parse\(["']([^"'\n]{16,32})["']\)[^;]{0,80}?\bAES\b'''),
    ]);
    final i = find([
      RegExp(r'''(?:\biv|aesIv)\s*[:=]\s*["']([^"'\n]{16})["']'''),
    ]);
    final t = find([
      RegExp(r'''(?:tokenKey|hmacKey|signKey)\s*[:=]\s*["']([^"'\n]{16,64})["']'''),
      RegExp(r'''Hmac\w*\([^)]*,\s*["']([^"'\n]{16,64})["']'''),
    ]);
    if (k != null && k != aesKey) {
      aesKey = k;
      changed = true;
    }
    if (i != null && i != iv) {
      iv = i;
      changed = true;
    }
    if (t != null && t != tokenKey) {
      tokenKey = t;
      changed = true;
    }
    if (changed) Log.d('keys', 'updated key material from player script');
    return changed;
  }
}
