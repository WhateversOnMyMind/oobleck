import 'dart:convert';

import 'package:dio/dio.dart';

import '../../models.dart';

/// Optional extra "Kiwi" server via the nekostream mapper (observed 2026-11-11).
class KiwiExtractor {
  KiwiExtractor(this.dio, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final Dio dio;
  final DateTime Function() _clock;

  Future<StreamSource?> extract(String malId, String episode, AudioType type) async {
    final ts = _clock().millisecondsSinceEpoch ~/ 1000;
    final r = await dio.get<String>('https://mapper.nekostream.site/api/mal/$malId/$episode/$ts',
        options: Options(responseType: ResponseType.plain));
    final j = jsonDecode(r.data ?? '{}');
    final kiwi = j is Map ? j['Kiwi-Stream-'] : null;
    final entry = kiwi is Map ? kiwi[type.name] : null;
    final url = entry is Map ? entry['url'] : null;
    if (url is! String || url.isEmpty) return null;
    return StreamSource(url: url, serverName: 'Kiwi', type: type);
  }
}
