import '../models.dart';

/// A show we have seen or downloaded. Poster is cached to disk for the
/// offline Library ([posterPath]).
class ShowRecord {
  ShowRecord({
    required this.slug,
    required this.title,
    this.siteId = '',
    this.url = '',
    this.poster,
    this.posterPath,
    this.synopsis = '',
    this.malId,
  });

  final String slug;
  final String title;
  final String siteId;
  final String url;
  final String? poster;
  final String? posterPath;
  final String synopsis;
  final String? malId;

  factory ShowRecord.fromDetail(ShowDetail d, {String? posterPath}) => ShowRecord(
        slug: d.slug,
        title: d.title,
        siteId: d.siteId,
        url: d.url,
        poster: d.poster,
        posterPath: posterPath,
        synopsis: d.synopsis,
        malId: d.malId,
      );

  ShowRecord copyWith({String? posterPath}) => ShowRecord(
        slug: slug,
        title: title,
        siteId: siteId,
        url: url,
        poster: poster,
        posterPath: posterPath ?? this.posterPath,
        synopsis: synopsis,
        malId: malId,
      );

  Map<String, dynamic> toMap() => {
        'slug': slug,
        'title': title,
        'siteId': siteId,
        'url': url,
        'poster': poster,
        'posterPath': posterPath,
        'synopsis': synopsis,
        'malId': malId,
      };

  factory ShowRecord.fromMap(Map<dynamic, dynamic> m) => ShowRecord(
        slug: m['slug'] as String,
        title: m['title'] as String? ?? '',
        siteId: m['siteId'] as String? ?? '',
        url: m['url'] as String? ?? '',
        poster: m['poster'] as String?,
        posterPath: m['posterPath'] as String?,
        synopsis: m['synopsis'] as String? ?? '',
        malId: m['malId'] as String?,
      );
}

/// Cached episode row so lists and "next episode" work without the network.
class EpisodeRecord {
  EpisodeRecord({
    required this.number,
    this.title = '',
    this.serverKey = '',
    this.malId,
    this.hasDub = false,
    this.isFiller = false,
  });
  final String number;
  final String title;
  final String serverKey;
  final String? malId;
  final bool hasDub;
  final bool isFiller;

  double get numeric => double.tryParse(number) ?? 0;

  factory EpisodeRecord.fromInfo(EpisodeInfo e) => EpisodeRecord(
        number: e.number,
        title: e.title,
        serverKey: e.serverKey,
        malId: e.malId,
        hasDub: e.hasDub,
        isFiller: e.isFiller,
      );

  EpisodeInfo toInfo() => EpisodeInfo(
        number: number,
        serverKey: serverKey,
        title: title,
        malId: malId,
        hasDub: hasDub,
        isFiller: isFiller,
      );

  Map<String, dynamic> toMap() => {
        'number': number,
        'title': title,
        'serverKey': serverKey,
        'malId': malId,
        'hasDub': hasDub,
        'isFiller': isFiller,
      };

  factory EpisodeRecord.fromMap(Map<dynamic, dynamic> m) => EpisodeRecord(
        number: m['number'] as String,
        title: m['title'] as String? ?? '',
        serverKey: m['serverKey'] as String? ?? '',
        malId: m['malId'] as String?,
        hasDub: m['hasDub'] as bool? ?? false,
        isFiller: m['isFiller'] as bool? ?? false,
      );
}

/// Watch progress for one episode (shared by streamed and downloaded copies).
class HistoryEntry {
  HistoryEntry({
    required this.slug,
    required this.episode,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });

  final String slug;
  final String episode;
  final int positionMs;
  final int durationMs;
  final int updatedAt;

  double get fraction => durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);

  /// Finished means more than 90% watched.
  bool get isFinished => fraction > 0.9;

  /// Started but not finished (worth showing a progress bar and resuming).
  bool get isPartial => positionMs > 5000 && !isFinished;

  static String keyOf(String slug, String episode) => '$slug|$episode';
  String get key => keyOf(slug, episode);

  Map<String, dynamic> toMap() => {
        'slug': slug,
        'episode': episode,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedAt': updatedAt,
      };

  factory HistoryEntry.fromMap(Map<dynamic, dynamic> m) => HistoryEntry(
        slug: m['slug'] as String,
        episode: m['episode'] as String,
        positionMs: m['positionMs'] as int? ?? 0,
        durationMs: m['durationMs'] as int? ?? 0,
        updatedAt: m['updatedAt'] as int? ?? 0,
      );
}

enum DownloadStatus { queued, downloading, paused, done, failed }

class DownloadedSub {
  DownloadedSub({required this.path, required this.label, required this.language});
  final String path;
  final String label;
  final String language;
  Map<String, dynamic> toMap() => {'path': path, 'label': label, 'language': language};
  factory DownloadedSub.fromMap(Map<dynamic, dynamic> m) => DownloadedSub(
        path: m['path'] as String,
        label: m['label'] as String? ?? '',
        language: m['language'] as String? ?? 'und',
      );
}

class DownloadRecord {
  DownloadRecord({
    required this.slug,
    required this.episode,
    required this.type,
    this.episodeTitle = '',
    this.status = DownloadStatus.queued,
    this.progress = 0,
    this.bytes = 0,
    this.totalBytes = 0,
    this.speedBps = 0,
    this.filePath,
    this.subs = const [],
    this.quality = '',
    this.durationMs = 0,
    this.error,
    this.serverKey = '',
    this.malId,
    this.preferredQuality = 'best',
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  final String slug;
  final String episode;
  final AudioType type;
  String episodeTitle;
  DownloadStatus status;
  double progress; // 0..1
  int bytes;
  int totalBytes;
  int speedBps;
  String? filePath;
  List<DownloadedSub> subs;
  String quality;
  int durationMs;
  String? error;
  String serverKey;
  String? malId;
  String preferredQuality;
  final int createdAt;

  String get key => keyOf(slug, episode, type);
  static String keyOf(String slug, String episode, AudioType type) => '$slug|$episode|${type.name}';

  bool get isDone => status == DownloadStatus.done && filePath != null;
  double get numeric => double.tryParse(episode) ?? 0;

  Map<String, dynamic> toMap() => {
        'slug': slug,
        'episode': episode,
        'type': type.name,
        'episodeTitle': episodeTitle,
        'status': status.name,
        'progress': progress,
        'bytes': bytes,
        'totalBytes': totalBytes,
        'filePath': filePath,
        'subs': subs.map((s) => s.toMap()).toList(),
        'quality': quality,
        'durationMs': durationMs,
        'error': error,
        'serverKey': serverKey,
        'malId': malId,
        'preferredQuality': preferredQuality,
        'createdAt': createdAt,
      };

  factory DownloadRecord.fromMap(Map<dynamic, dynamic> m) => DownloadRecord(
        slug: m['slug'] as String,
        episode: m['episode'] as String,
        type: m['type'] == 'dub' ? AudioType.dub : AudioType.sub,
        episodeTitle: m['episodeTitle'] as String? ?? '',
        status: DownloadStatus.values.firstWhere((s) => s.name == m['status'], orElse: () => DownloadStatus.queued),
        progress: (m['progress'] as num?)?.toDouble() ?? 0,
        bytes: m['bytes'] as int? ?? 0,
        totalBytes: m['totalBytes'] as int? ?? 0,
        filePath: m['filePath'] as String?,
        subs: ((m['subs'] as List?) ?? const []).map((e) => DownloadedSub.fromMap(e as Map)).toList(),
        quality: m['quality'] as String? ?? '',
        durationMs: m['durationMs'] as int? ?? 0,
        error: m['error'] as String?,
        serverKey: m['serverKey'] as String? ?? '',
        malId: m['malId'] as String?,
        preferredQuality: m['preferredQuality'] as String? ?? 'best',
        createdAt: m['createdAt'] as int?,
      );
}
