/// Plain data types shared by every layer. Nothing here is site specific.
library;

enum AudioType {
  sub,
  dub;

  String get label => this == AudioType.sub ? 'Sub' : 'Dub';
}

class ShowSummary {
  const ShowSummary({
    required this.slug,
    required this.title,
    required this.url,
    this.poster,
    this.badge,
  });

  /// Stable id used across the app (the last path segment of the show URL).
  final String slug;
  final String title;
  final String url;
  final String? poster;

  /// Short label such as "EP 12" shown on cards when the site provides one.
  final String? badge;
}

class ShowDetail {
  const ShowDetail({
    required this.slug,
    required this.siteId,
    required this.title,
    required this.url,
    this.poster,
    this.synopsis = '',
    this.malId,
  });

  final String slug;

  /// Numeric id the site uses for AJAX calls.
  final String siteId;
  final String title;
  final String url;
  final String? poster;
  final String synopsis;
  final String? malId;
}

class EpisodeInfo {
  const EpisodeInfo({
    required this.number,
    required this.serverKey,
    this.title = '',
    this.malId,
    this.hasDub = false,
    this.isFiller = false,
  });

  /// Episode number as the site prints it ("1", "12", "12.5").
  final String number;

  /// Opaque key that the server list endpoint needs.
  final String serverKey;
  final String title;
  final String? malId;
  final bool hasDub;
  final bool isFiller;

  double get numeric => double.tryParse(number) ?? 0;

  String get displayTitle => title.isEmpty ? 'Episode $number' : title;
}

class ServerOption {
  const ServerOption({required this.name, required this.linkId, required this.type});
  final String name;
  final String linkId;
  final AudioType type;
}

class SubtitleTrackInfo {
  const SubtitleTrackInfo({required this.url, required this.label, this.isDefault = false});
  final String url;
  final String label;
  final bool isDefault;

  /// Best-effort language code derived from the label ("English" -> "en").
  String get language => languageCodeFor(label);
}

class SkipRange {
  const SkipRange(this.start, this.end);
  final double start;
  final double end;
  bool contains(double s) => s >= start && s < end;
}

/// A playable stream resolved from one server.
class StreamSource {
  StreamSource({
    required this.url,
    required this.serverName,
    required this.type,
    this.headers = const {},
    this.subtitles = const [],
    this.intro,
    this.outro,
    this.resign,
  });

  /// URL to hand to the player (already signed when the host needs it).
  final String url;
  final String serverName;
  final AudioType type;
  final Map<String, String> headers;
  final List<SubtitleTrackInfo> subtitles;
  final SkipRange? intro;
  final SkipRange? outro;

  /// Re-signs a URL belonging to this stream (token expiry). Null when the
  /// host does not sign URLs.
  final String Function(String url)? resign;

  bool get isHls => url.contains('.m3u8');

  /// Returns a copy that uses [intro]/[outro] where this source has none.
  StreamSource withFallbackSkips(SkipRange? intro, SkipRange? outro) {
    if ((this.intro != null || intro == null) && (this.outro != null || outro == null)) return this;
    return StreamSource(
      url: url,
      serverName: serverName,
      type: type,
      headers: headers,
      subtitles: subtitles,
      intro: this.intro ?? intro,
      outro: this.outro ?? outro,
      resign: resign,
    );
  }

  String signed(String u) => resign == null ? u : resign!(u);
}

String languageCodeFor(String label) {
  final l = label.toLowerCase();
  const map = <String, String>{
    'english': 'en',
    'korean': 'ko',
    'japanese': 'ja',
    'spanish': 'es',
    'portuguese': 'pt',
    'french': 'fr',
    'german': 'de',
    'italian': 'it',
    'russian': 'ru',
    'arabic': 'ar',
    'indonesian': 'id',
    'thai': 'th',
    'vietnamese': 'vi',
    'chinese': 'zh',
    'turkish': 'tr',
    'hindi': 'hi',
    'malay': 'ms',
  };
  for (final e in map.entries) {
    if (l.contains(e.key)) return e.value;
  }
  final m = RegExp(r'^[a-z]{2}\b').firstMatch(l);
  return m?.group(0) ?? 'und';
}
