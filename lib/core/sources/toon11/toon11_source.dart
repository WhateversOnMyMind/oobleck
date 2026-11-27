import 'dart:async';

import 'package:dio/dio.dart';

import '../../http.dart';
import '../../manga/manga_models.dart';
import '../manga_source.dart';
import '../source.dart';
import 'toon11_parsers.dart';

/// 11toon.com ("일일툰") manga / webtoon source. Plain Gnuboard pages over
/// HTTP, no login. Request shapes observed 2026-11-27:
///
/// * lists: `/bbs/board.php?bo_table=toon_c` plus `type=upd` (latest, 35 per
///   page with a normal pager), `is_over=0` (ranked by views) or `is_over=1`
///   (completed) - both give 101 cards on page 1 and 32 on each later page,
///   behind a "더보기" button instead of a pager - or `type=today` (daily
///   picks, a single page of 100 that ignores `sca` and `page`).
///   `sca=<genre>` filters; several genres are joined with `||` and must all
///   match.
/// * search: `/bbs/search_stx.php?stx=` (HTML, every match on one page) and
///   `/bbs/ajax.searchauthor.php?search_key=` (JSON).
/// * series: `/bbs/board.php?bo_table=toons&is=<id>`, chapters newest first,
///   100 per page (`&page=N`).
/// * chapter: `/bbs/board.php?bo_table=toons&wr_id=<chapter>&is=<id>`. Without
///   `is` the image paths come back malformed.
///
/// The site changes domain from time to time, hence [baseUrl].
class Toon11Source implements MangaSource {
  Toon11Source({required this.dio, String baseUrl = defaultBaseUrl})
      : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), '');

  static const String defaultBaseUrl = 'https://11toon.com';

  /// Chapter list pages fetched at the same time.
  static const int chapterListConcurrency = 4;

  static const String latest = 'latest';
  static const String popular = 'popular';
  static const String completed = 'completed';
  static const String recommended = 'recommended';

  /// Ranked lists: cards on the first page and on each later page.
  static const int _rankedFirstPage = 101;
  static const int _rankedNextPage = 32;

  final Dio dio;
  final String baseUrl;

  @override
  String get id => 'toon11';
  @override
  String get name => '11toon';

  /// The image hosts answer without a referer today; the site's own reader
  /// sends this one.
  @override
  Map<String, String> get imageHeaders => {'Referer': '$baseUrl/', 'User-Agent': kUserAgent};

  @override
  List<MangaCatalog> get catalogs => const [
        MangaCatalog(latest, 'Latest updates', '최신 업데이트', supportsGenres: true),
        MangaCatalog(popular, 'Popular', '인기', supportsGenres: true),
        MangaCatalog(completed, 'Completed', '완결', supportsGenres: true),
        MangaCatalog(recommended, 'Daily picks', '매일 추천 100', paged: false),
      ];

  /// Genre tabs of the "latest" list plus the two extra tabs (게임, 일상) of
  /// the ranked lists; every value works on all three filterable lists.
  /// "일상+치유" is stored with a space on the site.
  @override
  List<MangaGenre> get genres => const [
        MangaGenre('SF', 'SF'),
        MangaGenre('무협', '무협'),
        MangaGenre('TS', 'TS'),
        MangaGenre('개그', '개그'),
        MangaGenre('드라마', '드라마'),
        MangaGenre('러브코미디', '러브코미디'),
        MangaGenre('먹방', '먹방'),
        MangaGenre('백합', '백합'),
        MangaGenre('붕탁', '붕탁'),
        MangaGenre('스릴러', '스릴러'),
        MangaGenre('스포츠', '스포츠'),
        MangaGenre('시대', '시대'),
        MangaGenre('액션', '액션'),
        MangaGenre('순정', '순정'),
        MangaGenre('일상 치유', '일상+치유'),
        MangaGenre('추리', '추리'),
        MangaGenre('판타지', '판타지'),
        MangaGenre('학원', '학원'),
        MangaGenre('호러', '호러'),
        MangaGenre('BL', 'BL'),
        MangaGenre('17', '17'),
        MangaGenre('이세계', '이세계'),
        MangaGenre('전생', '전생'),
        MangaGenre('라노벨', '라노벨'),
        MangaGenre('애니화', '애니화'),
        MangaGenre('TL', 'TL'),
        MangaGenre('공포', '공포'),
        MangaGenre('하렘', '하렘'),
        MangaGenre('요리', '요리'),
        MangaGenre('게임', '게임'),
        MangaGenre('일상', '일상'),
      ];

  Future<String> _get(String path, Map<String, String> query) async {
    try {
      return await withRetry(() async {
        final r = await dio.get<String>('$baseUrl$path',
            queryParameters: query,
            options: Options(headers: {'Referer': '$baseUrl/'}, responseType: ResponseType.plain));
        return r.data ?? '';
      });
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code != null) throw SourceException('11toon: request failed (HTTP $code)');
      // Keep the cause (DNS, reset, certificate): a network that blocks the
      // site fails differently from one that is offline.
      final cause = (e.error?.toString() ?? e.message ?? '').split('\n').first;
      final detail = cause.isEmpty ? e.type.name : '${e.type.name}: $cause';
      throw SourceException('11toon: cannot reach the site ($detail)');
    }
  }

  Future<String> _board(Map<String, String> query) => _get('/bbs/board.php', query);

  @override
  Future<MangaListing> browse(String catalogId, {int page = 1, Set<String> genres = const {}}) async {
    final query = <String, String>{'bo_table': 'toon_c'};
    switch (catalogId) {
      case latest:
        query['type'] = 'upd';
      case popular:
        query['is_over'] = '0';
      case completed:
        query['is_over'] = '1';
      case recommended:
        if (page > 1) return MangaListing.empty;
        return MangaListing(parseToon11Cards(await _board({...query, 'type': 'today'}), baseUrl));
      default:
        throw SourceException('11toon: unknown list "$catalogId"');
    }
    if (genres.isNotEmpty) query['sca'] = genres.join('||');
    if (page > 1) query['page'] = '$page';
    final body = await _board(query);

    if (catalogId == latest) {
      return MangaListing(parseToon11Cards(body, baseUrl), hasNext: page < parseToon11LastPage(body));
    }
    final offset = page > 1 ? _rankedFirstPage + (page - 2) * _rankedNextPage : 0;
    final items = parseToon11Cards(body, baseUrl, rankOffset: offset);
    // No pager here; a short page is the last one.
    return MangaListing(items, hasNext: items.length >= (page > 1 ? _rankedNextPage : _rankedFirstPage));
  }

  /// Title matches first, then series by a matching author. The site returns
  /// every match at once, so there is no second page.
  @override
  Future<MangaListing> search(String query, {int page = 1}) async {
    final q = query.trim();
    if (q.isEmpty || page > 1) return MangaListing.empty;
    final byAuthor = _get('/bbs/ajax.searchauthor.php', {'search_key': q})
        .then(parseToon11AuthorSearch)
        .catchError((Object _) => const <MangaSummary>[], test: (e) => e is SourceException);
    final byTitle = parseToon11Cards(await _get('/bbs/search_stx.php', {'stx': q}), baseUrl);
    final seen = byTitle.map((m) => m.id).toSet();
    return MangaListing([...byTitle, ...(await byAuthor).where((m) => seen.add(m.id))]);
  }

  @override
  Future<MangaBundle> fetch(String mangaId) async {
    Future<String> listPage(int page) =>
        _board({'bo_table': 'toons', 'is': mangaId, if (page > 1) 'page': '$page'});

    final first = await listPage(1);
    final detail = parseToon11Detail(first, mangaId, baseUrl);
    final lastPage = parseToon11LastPage(first);

    // The pager on page 1 already tells how many pages there are, so the rest
    // can be fetched side by side instead of walking "next" links.
    final bodies = List<String?>.filled(lastPage + 1, null)..[1] = first;
    var next = 2;
    Future<void> worker() async {
      while (next <= lastPage) {
        final page = next++;
        bodies[page] = await listPage(page);
      }
    }

    await Future.wait([for (var i = 0; i < chapterListConcurrency; i++) worker()]);

    // A chapter published mid-fetch shifts the pages by one; drop the repeats.
    final seen = <String>{};
    final newestFirst = [
      for (final body in bodies.skip(1))
        ...parseToon11Chapters(body!, mangaId, detail.title, baseUrl).where((c) => seen.add(c.id)),
    ];
    return MangaBundle(detail, newestFirst.reversed.toList());
  }

  @override
  Future<List<MangaPage>> pages(ChapterInfo chapter) async => parseToon11Pages(
      await _board({'bo_table': 'toons', 'wr_id': chapter.id, 'is': chapter.mangaId}), baseUrl);

  @override
  String mangaUrl(String mangaId) => '$baseUrl/bbs/board.php?bo_table=toons&is=$mangaId';
}
