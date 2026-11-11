import '../models.dart';

/// Everything the app needs from a streaming site. All site specific code
/// lives behind this interface (see `anikoto/`).
abstract class Source {
  String get id;
  String get name;

  Future<List<ShowSummary>> search(String query);

  /// Home page sections, e.g. "Latest updates" -> shows.
  Future<Map<String, List<ShowSummary>>> home();

  Future<ShowDetail> showDetail(String slugOrUrl);

  Future<List<EpisodeInfo>> episodes(ShowDetail show);

  Future<List<ServerOption>> servers(EpisodeInfo episode);

  /// Resolves every server for [type] in parallel and emits each working
  /// stream as soon as it is ready (completion order).
  Stream<StreamSource> resolveStreams(EpisodeInfo episode, AudioType type);

  /// Convenience: first working stream, honouring [preference] (server names
  /// in order) when several arrive close together.
  Future<StreamSource> resolveBest(
    EpisodeInfo episode,
    AudioType type, {
    List<String> preference = defaultServerPreference,
    Duration grace = const Duration(milliseconds: 1500),
  });
}

const List<String> defaultServerPreference = ['HD-1', 'HD-2', 'Vidstream-1', 'Vidstream-2', 'Kiwi'];

class SourceException implements Exception {
  SourceException(this.message);
  final String message;
  @override
  String toString() => message;
}
