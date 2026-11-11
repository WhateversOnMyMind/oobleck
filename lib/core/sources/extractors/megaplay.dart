import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:html/parser.dart' as html;

import '../../log.dart';
import '../../models.dart';
import 'megaplay_keys.dart';

/// Resolves megaplay.buzz embeds (observed 2026-11-11, see PLAN.md).
class MegaplayExtractor {
  MegaplayExtractor(this.dio, this.keys, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Dio dio;
  final MegaplayKeys keys;
  final DateTime Function() _clock;

  static const String siteReferer = 'https://anikototv.to/';
  static const String playbackReferer = 'https://megaplay.buzz/';

  static bool handles(Uri embed) => embed.host.contains('megaplay');

  Map<String, String> get playbackHeaders =>
      {'Referer': playbackReferer, 'Origin': 'https://megaplay.buzz'};

  Future<StreamSource> extract(String embedUrl, {required String serverName, required AudioType type}) async {
    final embed = Uri.parse(embedUrl);
    final page = await dio.get<String>(embedUrl,
        options: Options(headers: {'Referer': siteReferer}, responseType: ResponseType.plain));
    final doc = html.parse(page.data ?? '');
    final id = doc.querySelector('#megaplay-player')?.attributes['data-id'];
    if (id == null) throw FormatException('megaplay: #megaplay-player[data-id] missing');
    final s = embed.queryParameters['s'];
    final origin = '${embed.scheme}://${embed.host}';

    Map<String, dynamic>? data;
    Object? lastError;
    for (final ep in ['getSources', 'getSourcesNew']) {
      try {
        final q = {'id': id, 's': ?s};
        final r = await dio.get<String>('$origin/stream/$ep',
            queryParameters: q,
            options: Options(
                headers: {'X-Requested-With': 'XMLHttpRequest', 'Referer': embedUrl},
                responseType: ResponseType.plain));
        data = jsonDecode(r.data ?? '{}') as Map<String, dynamic>;
        if (_fileOf(data) != null) break;
      } catch (e) {
        lastError = e;
        Log.d('megaplay', '$ep failed: $e');
      }
    }
    final file = data == null ? null : _fileOf(data);
    if (file == null) throw FormatException('megaplay: no stream file ($lastError)');

    return StreamSource(
      url: signUrl(file),
      serverName: serverName,
      type: type,
      headers: playbackHeaders,
      subtitles: parseTracks(data!['tracks']),
      intro: _range(data['intro']),
      outro: _range(data['outro']),
      resign: signUrl,
    );
  }

  String? _fileOf(Map<String, dynamic> data) {
    final sources = data['sources'];
    if (sources is Map && sources['file'] is String && (sources['file'] as String).isNotEmpty) {
      return sources['file'] as String;
    }
    if (sources is List && sources.isNotEmpty && sources.first is Map) {
      final f = (sources.first as Map)['file'];
      if (f is String && f.isNotEmpty) return f;
    }
    final e = data['enc'] ?? (sources is String ? sources : null);
    if (e is String && e.isNotEmpty) {
      try {
        final j = jsonDecode(decrypt(e));
        if (j is Map && j['file'] is String) return j['file'] as String;
        if (j is List && j.isNotEmpty && j.first is Map) return (j.first as Map)['file'] as String?;
      } catch (err) {
        Log.d('megaplay', 'decrypt failed: $err');
      }
    }
    return null;
  }

  SkipRange? _range(Object? o) {
    if (o is Map && o['start'] is num && o['end'] is num) {
      final r = SkipRange((o['start'] as num).toDouble(), (o['end'] as num).toDouble());
      return r.end > r.start ? r : null;
    }
    return null;
  }

  static List<SubtitleTrackInfo> parseTracks(Object? tracks) {
    final out = <SubtitleTrackInfo>[];
    if (tracks is List) {
      for (final t in tracks) {
        if (t is! Map) continue;
        final kind = t['kind'];
        final file = t['file'];
        if (file is! String || file.isEmpty) continue;
        if (kind != null && kind != 'captions' && kind != 'subtitles') continue;
        out.add(SubtitleTrackInfo(
          url: file,
          label: (t['label'] as String?) ?? 'Unknown',
          isDefault: t['default'] == true,
        ));
      }
    }
    return out;
  }

  /// Decrypts `enc` payloads: base64url, AES-256-CBC, PKCS7.
  String decrypt(String encoded) {
    var b64 = encoded.replaceAll('-', '+').replaceAll('_', '/').trim();
    while (b64.length % 4 != 0) {
      b64 += '=';
    }
    final e = enc.Encrypter(enc.AES(enc.Key(keys.aesKeyBytes), mode: enc.AESMode.cbc, padding: 'PKCS7'));
    return e.decrypt(enc.Encrypted.fromBase64(b64), iv: enc.IV(keys.ivBytes));
  }

  /// Inverse of [decrypt]; used by tests and fixtures.
  String encrypt(String plain) {
    final e = enc.Encrypter(enc.AES(enc.Key(keys.aesKeyBytes), mode: enc.AESMode.cbc, padding: 'PKCS7'));
    return base64Url.encode(e.encrypt(plain, iv: enc.IV(keys.ivBytes)).bytes).replaceAll('=', '');
  }

  static final RegExp _pathHex = RegExp(r'/([0-9a-fA-F]{32})/([0-9a-fA-F]{32})/');

  /// Appends `token=<payload>.<hmac>` (valid ~90 s) when the path carries the
  /// `/<32hex>/<32hex>/` pair; otherwise returns the URL unchanged.
  String signUrl(String url) {
    final m = _pathHex.firstMatch(Uri.parse(url).path);
    if (m == null) return url;
    final expires = _clock().millisecondsSinceEpoch ~/ 1000 + 90;
    final payload = '$expires|${m.group(1)!.toLowerCase()}/${m.group(2)!.toLowerCase()}';
    final mac = Hmac(sha256, utf8.encode(keys.tokenKey)).convert(utf8.encode(payload)).bytes;
    String b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');
    final token = '${b64(utf8.encode(payload))}.${b64(mac)}';
    final clean = url.replaceAll(RegExp(r'([?&])token=[^&]*&?'), r'$1').replaceAll(RegExp(r'[?&]$'), '');
    return '$clean${clean.contains('?') ? '&' : '?'}token=$token';
  }
}
