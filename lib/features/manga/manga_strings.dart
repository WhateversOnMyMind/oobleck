import '../../app/strings.dart';
import '../../core/manga/manga_models.dart';

/// Text for the manga tab and reader, English and Korean side by side.
extension MangaStrings on Strings {
  // ---- tab & sections -----------------------------------------------------------
  String get navManga => pick('Manga', '만화');
  String get mangaLibrary => pick('Library', '서재');
  String get mangaUpdates => pick('Updates', '업데이트');
  String get mangaHistory => pick('History', '기록');
  String get mangaBrowse => pick('Browse', '탐색');
  String get mangaDownloads => pick('Downloads', '다운로드');
  String get searchManga => pick('Search manga and webtoons', '만화, 웹툰 검색');
  String get searchMangaHint => pick('Title or author', '제목 또는 작가');
  String get allGenres => pick('All genres', '전체 장르');
  String get genres => pick('Genres', '장르');
  String get loadMore => pick('Load more', '더 보기');
  String get noResults => pick('Nothing found', '검색 결과가 없어요');
  String get noResultsHint => pick('Try a shorter title or the author name.', '제목을 짧게 하거나 작가 이름으로 찾아보세요.');

  // ---- library ---------------------------------------------------------------------
  String get libraryEmpty => pick('Your library is empty', '서재가 비어 있어요');
  String get libraryEmptyHint =>
      pick('Find something in Browse and tap the heart to keep it here.', '탐색에서 작품을 찾아 하트를 누르면 여기에 모여요.');
  String get goBrowse => pick('Browse', '탐색하기');
  String get checkForUpdates => pick('Check for new chapters', '새 화 확인');
  String checkingUpdates(int done, int total) => pick('Checking $done / $total…', '확인 중 $done / $total…');
  String newChaptersFound(int n) =>
      n == 0 ? pick('No new chapters', '새 화가 없어요') : pick('$n new ${n == 1 ? 'chapter' : 'chapters'}', '새 화 $n개');
  String get searchLibrary => pick('Search library', '서재 검색');
  String get sortBy => pick('Sort by', '정렬');
  String get sortLastRead => pick('Last read', '최근 읽음');
  String get sortLastUpdate => pick('Latest chapter', '최신 화');
  String get sortTitle => pick('Title', '제목');
  String get sortUnread => pick('Unread count', '안 읽은 화');
  String get sortAdded => pick('Date added', '추가한 날짜');
  String get filter => pick('Filter', '필터');
  String get filterUnread => pick('Unread', '안 읽음');
  String get filterStarted => pick('Started', '읽는 중');
  String get filterDownloaded => pick('Downloaded', '다운로드됨');
  String get filterCompleted => pick('Completed series', '완결');
  String get display => pick('Display', '보기');
  String get displayGrid => pick('Covers', '표지');
  String get displayCompact => pick('Compact covers', '작은 표지');
  String get displayList => pick('List', '목록');
  String get showUnreadBadge => pick('Unread badges', '안 읽은 화 배지');
  String get showContinueButton => pick('Continue reading button', '이어 읽기 버튼');
  String get categories => pick('Categories', '카테고리');
  String get allCategory => pick('All', '전체');
  String get editCategories => pick('Edit categories', '카테고리 편집');
  String get newCategory => pick('New category', '새 카테고리');
  String get categoryName => pick('Name', '이름');
  String get setCategories => pick('Set categories', '카테고리 지정');
  String get rename => pick('Rename', '이름 바꾸기');
  String get removeFromLibrary => pick('Remove from library', '서재에서 빼기');
  String removedFromLibrary(String t) => pick('Removed “$t”', '“$t”을(를) 뺐어요');
  String addedToLibrary(String t) => pick('Added “$t” to your library', '“$t”을(를) 서재에 담았어요');
  String get undo => pick('Undo', '되돌리기');
  String selectedCount(int n) => pick('$n selected', '$n개 선택');
  String unreadCount(int n) => pick('$n unread', '안 읽음 $n');

  // ---- updates & history -----------------------------------------------------------
  String get updatesEmpty => pick('No new chapters yet', '아직 새 화가 없어요');
  String get updatesEmptyHint =>
      pick('Pull down or tap refresh to check the series in your library.', '아래로 당기거나 새로고침을 눌러 서재 작품을 확인하세요.');
  String get today => pick('Today', '오늘');
  String get yesterday => pick('Yesterday', '어제');
  String daysAgo(int n) => pick('$n days ago', '$n일 전');
  String get clearUpdates => pick('Clear updates', '업데이트 비우기');
  String get historyEmpty => pick('Nothing read yet', '아직 읽은 작품이 없어요');
  String get historyEmptyHint => pick('Chapters you open show up here.', '읽은 화가 여기에 표시돼요.');
  String get clearMangaHistory => pick('Clear reading history', '읽은 기록 지우기');
  String get clearMangaHistoryBody =>
      pick('Read marks and page positions are kept.', '읽음 표시와 읽던 위치는 그대로예요.');
  String get removeFromHistory => pick('Remove from history', '기록에서 삭제');
  String get resume => pick('Resume', '이어 읽기');
  String agoMinutes(int n) => pick('$n min ago', '$n분 전');
  String agoHours(int n) => pick('$n h ago', '$n시간 전');

  // ---- detail ------------------------------------------------------------------------
  String get inLibrary => pick('In library', '서재에 있음');
  String get addToLibrary => pick('Add to library', '서재에 담기');
  String get startReading => pick('Start reading', '처음부터 읽기');
  String continueChapter(String c) => pick('Continue $c', '$c 이어 읽기');
  String readChapter(String c) => pick('Read $c', '$c 읽기');
  String get openInBrowser => pick('Open in browser', '브라우저에서 열기');
  String get readerModeForSeries => pick('Reading mode for this series', '이 작품의 읽기 방식');
  String get useDefault => pick('App default', '앱 기본값');
  String chapterCount(int n) => pick('$n ${n == 1 ? 'chapter' : 'chapters'}', '$n화');
  String get author => pick('Author', '작가');
  String get more => pick('More', '더 보기');
  String get less => pick('Less', '접기');
  String status(MangaStatus s) => switch (s) {
        MangaStatus.ongoing => pick('Ongoing', '연재 중'),
        MangaStatus.completed => pick('Completed', '완결'),
        MangaStatus.hiatus => pick('On hiatus', '휴재'),
        MangaStatus.unknown => pick('Unknown', '알 수 없음'),
      };
  String get chaptersFilterAll => pick('All chapters', '전체');
  String get chaptersFilterUnread => pick('Unread', '안 읽음');
  String get chaptersFilterDownloaded => pick('Downloaded', '다운로드됨');
  String get chaptersFilterBookmarked => pick('Bookmarked', '북마크');
  String get newestFirst => pick('Newest first', '최신 화부터');
  String get oldestFirst => pick('Oldest first', '1화부터');
  String get markRead => pick('Mark as read', '읽음으로 표시');
  String get markUnread => pick('Mark as unread', '안 읽음으로 표시');
  String get markPreviousRead => pick('Mark previous as read', '이전 화 모두 읽음');
  String get bookmark => pick('Bookmark', '북마크');
  String get removeBookmark => pick('Remove bookmark', '북마크 해제');
  String get download => pick('Download', '다운로드');
  String get deleteDownload => pick('Delete download', '다운로드 삭제');
  String get downloadNext5 => pick('Next 5 unread', '안 읽은 다음 5화');
  String get downloadUnread => pick('All unread', '안 읽은 화 모두');
  String get downloadAll => pick('All chapters', '전체 화');
  String get selectAll => pick('Select all', '모두 선택');
  String get jumpToChapter => pick('Go to chapter', '화로 이동');
  String pageOf(int page, int total) => pick('Page $page of $total', '$total쪽 중 $page쪽');
  String pagesLeft(int n) => pick('$n pages left', '$n쪽 남음');
  String get seriesGone => pick('This series could not be loaded.', '작품을 불러오지 못했어요.');
  String get showingSaved => pick('Offline: showing the saved copy', '오프라인: 저장된 정보를 보여 드려요');

  // ---- downloads -------------------------------------------------------------------
  String get downloadsEmpty => pick('No chapters downloaded', '다운로드한 화가 없어요');
  String get downloadsEmptyHint =>
      pick('Use the download button on a series to read offline.', '작품 화면의 다운로드 버튼으로 오프라인에서도 읽을 수 있어요.');
  String downloadQueued(int n) => pick('$n ${n == 1 ? 'chapter' : 'chapters'} queued', '$n화 대기열에 추가');
  String get pause => pick('Pause', '일시정지');
  String get resumeDownload => pick('Resume', '재개');
  String get failed => pick('Failed', '실패');
  String get waiting => pick('Waiting', '대기 중');
  String get deleteRead => pick('Delete read chapters', '읽은 화 삭제');

  // ---- reader --------------------------------------------------------------------------
  String get readerSettings => pick('Reader settings', '뷰어 설정');
  String get readingMode => pick('Reading mode', '읽기 방식');
  String readerModeLabel(String name) => switch (name) {
        'auto' => pick('Automatic', '자동'),
        'webtoon' => pick('Webtoon (long strip)', '웹툰 (세로 스크롤)'),
        'continuous' => pick('Vertical with gaps', '세로 (간격 있음)'),
        'ltr' => pick('Left to right', '왼쪽에서 오른쪽'),
        'rtl' => pick('Right to left (manga)', '오른쪽에서 왼쪽 (일본 만화)'),
        'vertical' => pick('Vertical pages', '세로 페이지'),
        _ => name,
      };
  String get readerAutoHint => pick('Long strips scroll, single pages turn like a book.', '긴 이미지는 스크롤, 한 쪽짜리는 책처럼 넘겨요.');
  String get scaleType => pick('Page fit', '페이지 맞춤');
  String scaleLabel(String name) => switch (name) {
        'fitScreen' => pick('Fit screen', '화면에 맞춤'),
        'fitWidth' => pick('Fit width', '너비에 맞춤'),
        'fitHeight' => pick('Fit height', '높이에 맞춤'),
        'original' => pick('Original size', '원본 크기'),
        _ => name,
      };
  String get tapZones => pick('Tap zones', '탭 영역');
  String tapLayoutLabel(String name) => switch (name) {
        'lShape' => pick('L shape', 'L자'),
        'kindle' => pick('Kindle', '킨들'),
        'edges' => pick('Edges', '가장자리'),
        'leftRight' => pick('Left and right', '좌우'),
        'off' => pick('Off', '끄기'),
        _ => name,
      };
  String get invertTaps => pick('Invert tap zones', '탭 방향 반대로');
  String get background => pick('Background', '배경');
  String backgroundLabel(String name) => switch (name) {
        'black' => pick('Black', '검정'),
        'gray' => pick('Gray', '회색'),
        'white' => pick('White', '흰색'),
        _ => name,
      };
  String get upscale => pick('Sharpen and upscale', '선명하게 확대');
  String get upscaleHint =>
      pick('Makes low-resolution pages crisp on big screens (GPU).', '저해상도 이미지를 큰 화면에서 선명하게 보여요 (GPU).');
  String get sharpness => pick('Sharpness', '선명도');
  String get webtoonPadding => pick('Side padding (webtoon)', '좌우 여백 (웹툰)');
  String get keepScreenOn => pick('Keep screen on', '화면 켜짐 유지');
  String get showPageNumber => pick('Show page number', '쪽 번호 표시');
  String get volumeKeys => pick('Volume keys turn pages', '볼륨 버튼으로 넘기기');
  String get fullscreenReader => pick('Fullscreen', '전체 화면');
  String get dimPages => pick('Dim pages', '화면 어둡게');
  String get grayscale => pick('Grayscale', '흑백');
  String get autoNextChapter => pick('Continue into the next chapter', '다음 화로 이어서 보기');
  String get incognito => pick('Incognito (no history)', '시크릿 모드 (기록 안 남김)');
  String get dualPage => pick('Two pages side by side in landscape', '가로 화면에서 두 쪽 보기');
  String get previousChapter => pick('Previous chapter', '이전 화');
  String get nextChapter => pick('Next chapter', '다음 화');
  String get noNextChapter => pick('This is the latest chapter', '마지막 화예요');
  String get noPreviousChapter => pick('This is the first chapter', '첫 화예요');
  String finishedChapter(String c) => pick('Finished $c', '$c 끝');
  String upNext(String c) => pick('Next: $c', '다음: $c');
  String get pageFailed => pick('This page did not load', '이 쪽을 불러오지 못했어요');
  String get savePage => pick('Save page', '이미지 저장');
  String get pageSaved => pick('Page saved', '이미지를 저장했어요');
  String get chapterEmpty => pick('This chapter has no pages', '이 화에는 이미지가 없어요');
  String get readerHelpDesktop => pick(
      'Arrows / Page Up / Page Down / Space turn pages · F fullscreen · M menu · Esc close',
      '방향키 / Page Up / Page Down / 스페이스로 넘기기 · F 전체 화면 · M 메뉴 · Esc 닫기');

  // ---- settings -------------------------------------------------------------------
  String get mangaSettings => pick('Manga reader', '만화 뷰어');
  String get mangaSiteAddress => pick('11toon address', '11toon 주소');
  String get mangaSiteAddressHint =>
      pick('Change this if the site moves to a new domain.', '사이트 주소가 바뀌면 여기서 고쳐 주세요.');
  String get pageCache => pick('Page cache', '이미지 캐시');
  String pageCacheSize(String size) => pick('$size used', '$size 사용 중');
  String get clearPageCache => pick('Clear page cache', '이미지 캐시 지우기');
}
