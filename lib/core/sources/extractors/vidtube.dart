import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html;

import '../../models.dart';
import 'megaplay.dart';

/// Resolves vidtube.site embeds (observed 2026-11-11, see PLAN.md).
class VidtubeExtractor {
  VidtubeExtractor(this.dio);
  final Dio dio;

  static bool handles(Uri embed) => embed.host.contains('vidtube');

  Future<StreamSource> extract(String embedUrl, {required String serverName, required AudioType type}) async {
    final embed = Uri.parse(embedUrl);
    final page = await dio.get<String>(embedUrl,
        options: Options(headers: {'Referer': MegaplayExtractor.siteReferer}, responseType: ResponseType.plain));
    final id = html.parse(page.data ?? '').querySelector('#megaplay-player')?.attributes['data-id'];
    if (id == null) throw const FormatException('vidtube: #megaplay-player[data-id] missing');
    final segs = embed.pathSegments.where((s) => s.isNotEmpty).toList();
    final t = segs.isNotEmpty ? segs.last : type.name;
    final r = await dio.get<String>('https://vidtube.site/stream/getSourcesNew',
        queryParameters: {'id': id, 'type': t},
        options: Options(
            headers: {'X-Requested-With': 'XMLHttpRequest', 'Referer': embedUrl},
            responseType: ResponseType.plain));
    final data = jsonDecode(r.data ?? '{}') as Map<String, dynamic>;
    final sources = data['sources'];
    final file = sources is Map ? sources['file'] : (sources is List && sources.isNotEmpty ? (sources.first as Map)['file'] : null);
    if (file is! String || file.isEmpty) throw const FormatException('vidtube: no stream file');
    return StreamSource(
      url: file,
      serverName: serverName,
      type: type,
      headers: const {'Referer': 'https://vidtube.site/', 'Origin': 'https://vidtube.site'},
      subtitles: MegaplayExtractor.parseTracks(data['tracks']),
    );
  }
}
