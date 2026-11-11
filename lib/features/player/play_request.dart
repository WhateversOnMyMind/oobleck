import '../../core/models.dart';

/// Everything the player needs to start an episode.
class PlayRequest {
  const PlayRequest({
    required this.slug,
    required this.showTitle,
    required this.episode,
    this.type = AudioType.sub,
    this.preferOffline = true,
  });

  final String slug;
  final String showTitle;
  final String episode;
  final AudioType type;

  /// Use a downloaded copy when present (default).
  final bool preferOffline;

  PlayRequest copyWith({String? episode, AudioType? type}) => PlayRequest(
        slug: slug,
        showTitle: showTitle,
        episode: episode ?? this.episode,
        type: type ?? this.type,
        preferOffline: preferOffline,
      );
}
