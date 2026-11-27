/// Site-independent manga / webtoon models. Sources fill these in; the rest of
/// the app (library, reader, downloads) only ever sees these types.
library;

enum MangaStatus {
  ongoing,
  completed,
  hiatus,
  unknown;

  static MangaStatus parse(String? s) => values.asNameMap()[s] ?? unknown;
}

/// A card in a listing or search result.
class MangaSummary {
  const MangaSummary({
    required this.id,
    required this.title,
    this.cover,
    this.subtitle = '',
    this.adult = false,
  });

  /// Source-specific id, stable across sessions (11toon: the `is` number).
  final String id;
  final String title;
  final String? cover;

  /// Short line under the title (genres, last update, rank).
  final String subtitle;
  final bool adult;

  @override
  bool operator ==(Object other) => other is MangaSummary && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

/// One page of a listing. [hasNext] tells the UI whether to load more.
class MangaListing {
  const MangaListing(this.items, {this.hasNext = false});
  final List<MangaSummary> items;
  final bool hasNext;

  static const empty = MangaListing([]);
}

class MangaDetail {
  const MangaDetail({
    required this.id,
    required this.title,
    this.cover,
    this.author = '',
    this.genres = const [],
    this.status = MangaStatus.unknown,
    this.schedule = '',
    this.description = '',
    this.url = '',
  });

  final String id;
  final String title;
  final String? cover;
  final String author;
  final List<String> genres;
  final MangaStatus status;

  /// Release schedule as the site shows it, e.g. "주간" (weekly).
  final String schedule;
  final String description;

  /// Web page of the series (for "Open in browser").
  final String url;
}

class ChapterInfo {
  const ChapterInfo({
    required this.id,
    required this.mangaId,
    required this.title,
    this.number,
    this.uploaded,
    this.thumbnail,
    this.views,
  });

  /// Source-specific chapter id (11toon: `wr_id`).
  final String id;
  final String mangaId;
  final String title;

  /// Chapter number when it can be read from the title (1199화 -> 1199).
  final double? number;
  final DateTime? uploaded;
  final String? thumbnail;
  final int? views;
}

/// Series detail plus its full chapter list, oldest chapter first.
class MangaBundle {
  const MangaBundle(this.detail, this.chapters);
  final MangaDetail detail;
  final List<ChapterInfo> chapters;
}

/// One image of a chapter. [fallback] is a mirror to try when [url] fails.
class MangaPage {
  const MangaPage(this.index, this.url, {this.fallback});
  final int index;
  final String url;
  final String? fallback;
}

/// A browsable list a source offers (latest, popular, completed...).
class MangaCatalog {
  const MangaCatalog(this.id, this.titleEn, this.titleKo, {this.supportsGenres = false, this.paged = true});
  final String id;
  final String titleEn;
  final String titleKo;
  final bool supportsGenres;
  final bool paged;

  String title(bool korean) => korean ? titleKo : titleEn;
}

/// Genre filter option. [value] is what the site expects, [label] what we show.
class MangaGenre {
  const MangaGenre(this.value, this.label);
  final String value;
  final String label;
}
