import '../manga/manga_models.dart';

/// Everything the app needs from a manga / webtoon site. Site-specific code
/// lives behind this interface (see `toon11/`).
abstract class MangaSource {
  /// Stable id used in storage keys, e.g. `toon11`.
  String get id;
  String get name;

  /// Headers the image hosts expect (referer etc.).
  Map<String, String> get imageHeaders;

  /// Lists shown on the Browse screen, first one is the default.
  List<MangaCatalog> get catalogs;

  /// Genres usable with catalogs whose [MangaCatalog.supportsGenres] is true.
  List<MangaGenre> get genres;

  Future<MangaListing> browse(String catalogId, {int page = 1, Set<String> genres = const {}});

  /// Title search (and author search where the site has one), merged.
  Future<MangaListing> search(String query, {int page = 1});

  /// Series detail and every chapter, oldest first.
  Future<MangaBundle> fetch(String mangaId);

  Future<List<MangaPage>> pages(ChapterInfo chapter);

  /// Web page for a series, for "Open in browser".
  String mangaUrl(String mangaId);
}
