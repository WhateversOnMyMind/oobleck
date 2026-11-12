import 'dart:async';

import 'package:dio/dio.dart';

import '../../http.dart';
import '../../log.dart';
import '../../models.dart';
import '../extractors/kiwi.dart';
import '../extractors/megaplay.dart';
import '../extractors/megaplay_keys.dart';
import '../extractors/vidtube.dart';
import '../source.dart';
import 'anikoto_parsers.dart';

/// anikototv.to source. Request shapes are documented in PLAN.md
/// (observed 2026-11-11).
class AnikotoSource implements Source {
  AnikotoSource({Dio? dio, MegaplayKeys? keys, DateTime Function()? clock})
      : dio = dio ?? buildDio(),
        keys = keys ?? MegaplayKeys() {
    megaplay = MegaplayExtractor(this.dio, this.keys, clock: clock);
    vidtube = VidtubeExtractor(this.dio, megaplay);
    kiwi = KiwiExtractor(this.dio, clock: clock);
  }

  final Dio dio;
  final MegaplayKeys keys;
  late final MegaplayExtractor megaplay;
  late final VidtubeExtractor vidtube;
  late final KiwiExtractor kiwi;

  /// Whether to query the optional Kiwi server.
  bool enableKiwi = true;

  @override
  String get id => 'anikoto';
  @override
  String get name => 'Anikoto';

  static const Map<String, String> _ajax = {
    'Referer': '$anikotoBase/',
    'X-Requested-With': 'XMLHttpRequest',
  };

  Future<String> _get(String url, {Map<String, dynamic>? query, bool ajax = false}) {
    return withRetry(() async {
      final r = await dio.get<String>(url,
          queryParameters: query,
          options: Options(
              headers: ajax ? _ajax : {'Referer': '$anikotoBase/'},
              responseType: ResponseType.plain));
      return r.data ?? '';
    });
  }

  @override
  Future<List<ShowSummary>> search(String query) async =>
      parseSearch(await _get('$anikotoBase/ajax/anime/search', query: {'keyword': query}, ajax: true));

  @override
  Future<Map<String, List<ShowSummary>>> home() async => parseHome(await _get('$anikotoBase/home'));

  @override
  Future<ShowDetail> showDetail(String slugOrUrl) async {
    final url = slugOrUrl.startsWith('http') ? slugOrUrl : '$anikotoBase/watch/$slugOrUrl';
    return parseShow(await _get(url), url);
  }

  @override
  Future<List<EpisodeInfo>> episodes(ShowDetail show) async => parseEpisodes(
      await _get('$anikotoBase/ajax/episode/list/${show.siteId}', query: {'vrf': ''}, ajax: true));

  @override
  Future<List<ServerOption>> servers(EpisodeInfo episode) async => parseServers(
      await _get('$anikotoBase/ajax/server/list', query: {'servers': episode.serverKey}, ajax: true));

  Future<String> embedUrl(ServerOption s) async =>
      parseEmbedUrl(await _get('$anikotoBase/ajax/server', query: {'get': s.linkId}, ajax: true));

  Future<StreamSource> resolveServer(ServerOption s) async {
    final body = await _get('$anikotoBase/ajax/server', query: {'get': s.linkId}, ajax: true);
    final embed = parseEmbedUrl(body);
    final skips = parseEmbedSkips(body);
    final uri = Uri.parse(embed);
    final StreamSource out;
    // Megaplay also serves "Vidstream-1" from `/videojs/stream/...` (2026-11-12);
    // its getSources endpoint is the same.
    if (MegaplayExtractor.handles(uri)) {
      out = await megaplay.extract(embed, serverName: s.name, type: s.type);
    } else if (VidtubeExtractor.handles(uri)) {
      out = await vidtube.extract(embed, serverName: s.name, type: s.type);
    } else {
      Log.d('anikoto', 'unknown embed host ${uri.host}, skipping');
      throw SourceException('Unsupported server host');
    }
    return out.withFallbackSkips(skips.intro, skips.outro);
  }

  @override
  Stream<StreamSource> resolveStreams(EpisodeInfo episode, AudioType type) {
    final controller = StreamController<StreamSource>();
    () async {
      try {
        final all = (await servers(episode)).where((s) => s.type == type).toList();
        final futures = <Future<void>>[];
        for (final s in all) {
          futures.add(resolveServer(s).then((v) {
            if (!controller.isClosed) controller.add(v);
          }).catchError((Object e) {
            Log.d('anikoto', '${s.name} failed: $e');
          }));
        }
        if (enableKiwi && episode.malId != null && episode.malId!.isNotEmpty) {
          futures.add(kiwi.extract(episode.malId!, episode.number, type).then((v) {
            if (v != null && !controller.isClosed) controller.add(v);
          }).catchError((Object e) {
            Log.d('anikoto', 'Kiwi failed: $e');
          }));
        }
        await Future.wait(futures);
      } catch (e, st) {
        if (!controller.isClosed) controller.addError(e, st);
      } finally {
        await controller.close();
      }
    }();
    return controller.stream;
  }

  @override
  Future<StreamSource> resolveBest(
    EpisodeInfo episode,
    AudioType type, {
    List<String> preference = defaultServerPreference,
    Duration grace = const Duration(milliseconds: 1500),
  }) async {
    int rank(StreamSource s) {
      final i = preference.indexWhere((p) => p.toLowerCase() == s.serverName.toLowerCase());
      return i < 0 ? 999 : i;
    }

    final completer = Completer<StreamSource>();
    final arrived = <StreamSource>[];
    Timer? timer;
    void finish() {
      if (completer.isCompleted || arrived.isEmpty) return;
      arrived.sort((a, b) => rank(a).compareTo(rank(b)));
      completer.complete(arrived.first);
    }

    late StreamSubscription<StreamSource> sub;
    sub = resolveStreams(episode, type).listen((s) {
      arrived.add(s);
      if (rank(s) == 0) {
        finish();
      } else {
        timer ??= Timer(grace, finish);
      }
    }, onError: (Object e) {
      if (!completer.isCompleted && arrived.isEmpty) completer.completeError(e);
    }, onDone: () {
      timer?.cancel();
      if (arrived.isEmpty) {
        if (!completer.isCompleted) {
          completer.completeError(SourceException('No working server found'));
        }
      } else {
        finish();
      }
    });
    try {
      return await completer.future;
    } finally {
      timer?.cancel();
      unawaited(sub.cancel());
    }
  }
}
