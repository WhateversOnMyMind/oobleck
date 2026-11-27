import '../manga/manga_models.dart';

/// Storage key of a series: source id and site id, e.g. `toon11:2`.
String mangaKeyOf(String sourceId, String mangaId) => '$sourceId:$mangaId';

/// A series we have opened, added to the library or downloaded from.
class MangaRecord {
  MangaRecord({
    required this.sourceId,
    required this.mangaId,
    required this.title,
    this.cover,
    this.coverPath,
    this.author = '',
    this.genres = const [],
    this.status = MangaStatus.unknown,
    this.schedule = '',
    this.description = '',
    this.url = '',
    this.inLibrary = false,
    this.categories = const [],
    this.addedAt = 0,
    this.lastChecked = 0,
    this.readerMode,
    this.chapterSortDesc = true,
    this.chapterFilter = 'all',
  });

  final String sourceId;
  final String mangaId;
  final String title;
  final String? cover;

  /// Cover cached on disk so the library works offline.
  final String? coverPath;
  final String author;
  final List<String> genres;
  final MangaStatus status;
  final String schedule;
  final String description;
  final String url;
  final bool inLibrary;
  final List<String> categories;

  /// When it was added to the library (ms since epoch), 0 if never.
  final int addedAt;

  /// Last successful chapter-list refresh (ms since epoch).
  final int lastChecked;

  /// Per-series reader mode (`ReaderMode.name`), null = app default.
  final String? readerMode;
  final bool chapterSortDesc;

  /// all | unread | downloaded | bookmarked
  final String chapterFilter;

  String get key => mangaKeyOf(sourceId, mangaId);

  factory MangaRecord.fromDetail(String sourceId, MangaDetail d, {MangaRecord? existing}) => MangaRecord(
        sourceId: sourceId,
        mangaId: d.id,
        title: d.title,
        cover: d.cover ?? existing?.cover,
        coverPath: existing?.coverPath,
        author: d.author,
        genres: d.genres,
        status: d.status,
        schedule: d.schedule,
        description: d.description,
        url: d.url,
        inLibrary: existing?.inLibrary ?? false,
        categories: existing?.categories ?? const [],
        addedAt: existing?.addedAt ?? 0,
        lastChecked: existing?.lastChecked ?? 0,
        readerMode: existing?.readerMode,
        chapterSortDesc: existing?.chapterSortDesc ?? true,
        chapterFilter: existing?.chapterFilter ?? 'all',
      );

  factory MangaRecord.fromSummary(String sourceId, MangaSummary s) =>
      MangaRecord(sourceId: sourceId, mangaId: s.id, title: s.title, cover: s.cover);

  static const _unset = Object();

  MangaRecord copyWith({
    String? title,
    String? cover,
    Object? coverPath = _unset,
    bool? inLibrary,
    List<String>? categories,
    int? addedAt,
    int? lastChecked,
    Object? readerMode = _unset,
    bool? chapterSortDesc,
    String? chapterFilter,
  }) =>
      MangaRecord(
        sourceId: sourceId,
        mangaId: mangaId,
        title: title ?? this.title,
        cover: cover ?? this.cover,
        coverPath: identical(coverPath, _unset) ? this.coverPath : coverPath as String?,
        author: author,
        genres: genres,
        status: status,
        schedule: schedule,
        description: description,
        url: url,
        inLibrary: inLibrary ?? this.inLibrary,
        categories: categories ?? this.categories,
        addedAt: addedAt ?? this.addedAt,
        lastChecked: lastChecked ?? this.lastChecked,
        readerMode: identical(readerMode, _unset) ? this.readerMode : readerMode as String?,
        chapterSortDesc: chapterSortDesc ?? this.chapterSortDesc,
        chapterFilter: chapterFilter ?? this.chapterFilter,
      );

  Map<String, dynamic> toMap() => {
        'sourceId': sourceId,
        'mangaId': mangaId,
        'title': title,
        'cover': cover,
        'coverPath': coverPath,
        'author': author,
        'genres': genres,
        'status': status.name,
        'schedule': schedule,
        'description': description,
        'url': url,
        'inLibrary': inLibrary,
        'categories': categories,
        'addedAt': addedAt,
        'lastChecked': lastChecked,
        'readerMode': readerMode,
        'chapterSortDesc': chapterSortDesc,
        'chapterFilter': chapterFilter,
      };

  factory MangaRecord.fromMap(Map<dynamic, dynamic> m) => MangaRecord(
        sourceId: m['sourceId'] as String,
        mangaId: m['mangaId'] as String,
        title: m['title'] as String? ?? '',
        cover: m['cover'] as String?,
        coverPath: m['coverPath'] as String?,
        author: m['author'] as String? ?? '',
        genres: (m['genres'] as List?)?.cast<String>() ?? const [],
        status: MangaStatus.parse(m['status'] as String?),
        schedule: m['schedule'] as String? ?? '',
        description: m['description'] as String? ?? '',
        url: m['url'] as String? ?? '',
        inLibrary: m['inLibrary'] as bool? ?? false,
        categories: (m['categories'] as List?)?.cast<String>() ?? const [],
        addedAt: m['addedAt'] as int? ?? 0,
        lastChecked: m['lastChecked'] as int? ?? 0,
        readerMode: m['readerMode'] as String?,
        chapterSortDesc: m['chapterSortDesc'] as bool? ?? true,
        chapterFilter: m['chapterFilter'] as String? ?? 'all',
      );
}

/// A cached chapter. [firstSeen] is when this app first saw it, which drives
/// the Updates feed.
class ChapterRecord {
  ChapterRecord({
    required this.id,
    required this.title,
    this.number,
    this.uploaded,
    this.thumbnail,
    this.views,
    this.firstSeen = 0,
  });

  final String id;
  final String title;
  final double? number;
  final int? uploaded;
  final String? thumbnail;
  final int? views;
  final int firstSeen;

  factory ChapterRecord.fromInfo(ChapterInfo c, {required int firstSeen}) => ChapterRecord(
        id: c.id,
        title: c.title,
        number: c.number,
        uploaded: c.uploaded?.millisecondsSinceEpoch,
        thumbnail: c.thumbnail,
        views: c.views,
        firstSeen: firstSeen,
      );

  ChapterInfo toInfo(String mangaId) => ChapterInfo(
        id: id,
        mangaId: mangaId,
        title: title,
        number: number,
        uploaded: uploaded == null ? null : DateTime.fromMillisecondsSinceEpoch(uploaded!),
        thumbnail: thumbnail,
        views: views,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'number': number,
        'uploaded': uploaded,
        'thumbnail': thumbnail,
        'views': views,
        'firstSeen': firstSeen,
      };

  factory ChapterRecord.fromMap(Map<dynamic, dynamic> m) => ChapterRecord(
        id: m['id'] as String,
        title: m['title'] as String? ?? '',
        number: (m['number'] as num?)?.toDouble(),
        uploaded: m['uploaded'] as int?,
        thumbnail: m['thumbnail'] as String?,
        views: m['views'] as int?,
        firstSeen: m['firstSeen'] as int? ?? 0,
      );
}

/// Reading state of one chapter.
class ChapterState {
  ChapterState({
    required this.mangaKey,
    required this.chapterId,
    this.read = false,
    this.bookmarked = false,
    this.page = 0,
    this.pageCount = 0,
    this.offset = 0,
    this.readAt,
    this.updatedAt = 0,
  });

  final String mangaKey;
  final String chapterId;
  final bool read;
  final bool bookmarked;

  /// Last page shown (0-based).
  final int page;
  final int pageCount;

  /// How far into [page] the long-strip reader was scrolled (0..1).
  final double offset;

  /// Last time the chapter was opened, null when removed from history.
  final int? readAt;
  final int updatedAt;

  static String keyOf(String mangaKey, String chapterId) => '$mangaKey|$chapterId';
  String get key => keyOf(mangaKey, chapterId);

  bool get started => !read && (page > 0 || offset > 0);
  double get fraction => read ? 1 : (pageCount <= 0 ? 0 : ((page + offset) / pageCount).clamp(0.0, 1.0));

  static const _unset = Object();

  ChapterState copyWith({
    bool? read,
    bool? bookmarked,
    int? page,
    int? pageCount,
    double? offset,
    Object? readAt = _unset,
    int? updatedAt,
  }) =>
      ChapterState(
        mangaKey: mangaKey,
        chapterId: chapterId,
        read: read ?? this.read,
        bookmarked: bookmarked ?? this.bookmarked,
        page: page ?? this.page,
        pageCount: pageCount ?? this.pageCount,
        offset: offset ?? this.offset,
        readAt: identical(readAt, _unset) ? this.readAt : readAt as int?,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        'mangaKey': mangaKey,
        'chapterId': chapterId,
        'read': read,
        'bookmarked': bookmarked,
        'page': page,
        'pageCount': pageCount,
        'offset': offset,
        'readAt': readAt,
        'updatedAt': updatedAt,
      };

  factory ChapterState.fromMap(Map<dynamic, dynamic> m) => ChapterState(
        mangaKey: m['mangaKey'] as String,
        chapterId: m['chapterId'] as String,
        read: m['read'] as bool? ?? false,
        bookmarked: m['bookmarked'] as bool? ?? false,
        page: m['page'] as int? ?? 0,
        pageCount: m['pageCount'] as int? ?? 0,
        offset: (m['offset'] as num?)?.toDouble() ?? 0,
        readAt: m['readAt'] as int?,
        updatedAt: m['updatedAt'] as int? ?? 0,
      );
}

/// A new chapter found by a library refresh.
class MangaUpdate {
  MangaUpdate({required this.mangaKey, required this.chapterId, required this.foundAt});
  final String mangaKey;
  final String chapterId;
  final int foundAt;

  String get key => ChapterState.keyOf(mangaKey, chapterId);

  Map<String, dynamic> toMap() => {'mangaKey': mangaKey, 'chapterId': chapterId, 'foundAt': foundAt};
  factory MangaUpdate.fromMap(Map<dynamic, dynamic> m) =>
      MangaUpdate(mangaKey: m['mangaKey'] as String, chapterId: m['chapterId'] as String, foundAt: m['foundAt'] as int);
}

enum MangaDownloadStatus {
  queued,
  running,
  paused,
  done,
  failed;

  static MangaDownloadStatus parse(String? s) => values.asNameMap()[s] ?? queued;
}

/// A chapter saved for offline reading: one image file per page in [dir].
class MangaDownloadRecord {
  MangaDownloadRecord({
    required this.mangaKey,
    required this.chapterId,
    required this.chapterTitle,
    this.number,
    this.status = MangaDownloadStatus.queued,
    this.pagesDone = 0,
    this.pagesTotal = 0,
    this.bytes = 0,
    this.dir = '',
    this.files = const [],
    this.error,
    this.createdAt = 0,
  });

  final String mangaKey;
  final String chapterId;
  final String chapterTitle;
  final double? number;
  final MangaDownloadStatus status;
  final int pagesDone;
  final int pagesTotal;
  final int bytes;
  final String dir;

  /// Page files in reading order (absolute paths), filled when done.
  final List<String> files;
  final String? error;
  final int createdAt;

  String get key => ChapterState.keyOf(mangaKey, chapterId);
  bool get isDone => status == MangaDownloadStatus.done;
  double get progress => pagesTotal <= 0 ? 0 : pagesDone / pagesTotal;

  static const _unset = Object();

  MangaDownloadRecord copyWith({
    MangaDownloadStatus? status,
    int? pagesDone,
    int? pagesTotal,
    int? bytes,
    String? dir,
    List<String>? files,
    Object? error = _unset,
  }) =>
      MangaDownloadRecord(
        mangaKey: mangaKey,
        chapterId: chapterId,
        chapterTitle: chapterTitle,
        number: number,
        status: status ?? this.status,
        pagesDone: pagesDone ?? this.pagesDone,
        pagesTotal: pagesTotal ?? this.pagesTotal,
        bytes: bytes ?? this.bytes,
        dir: dir ?? this.dir,
        files: files ?? this.files,
        error: identical(error, _unset) ? this.error : error as String?,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'mangaKey': mangaKey,
        'chapterId': chapterId,
        'chapterTitle': chapterTitle,
        'number': number,
        'status': status.name,
        'pagesDone': pagesDone,
        'pagesTotal': pagesTotal,
        'bytes': bytes,
        'dir': dir,
        'files': files,
        'error': error,
        'createdAt': createdAt,
      };

  factory MangaDownloadRecord.fromMap(Map<dynamic, dynamic> m) => MangaDownloadRecord(
        mangaKey: m['mangaKey'] as String,
        chapterId: m['chapterId'] as String,
        chapterTitle: m['chapterTitle'] as String? ?? '',
        number: (m['number'] as num?)?.toDouble(),
        status: MangaDownloadStatus.parse(m['status'] as String?),
        pagesDone: m['pagesDone'] as int? ?? 0,
        pagesTotal: m['pagesTotal'] as int? ?? 0,
        bytes: m['bytes'] as int? ?? 0,
        dir: m['dir'] as String? ?? '',
        files: (m['files'] as List?)?.cast<String>() ?? const [],
        error: m['error'] as String?,
        createdAt: m['createdAt'] as int? ?? 0,
      );
}
