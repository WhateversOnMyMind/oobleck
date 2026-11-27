import 'strings.dart';

/// UI text added with the comfort pass (shared widgets, search, show page,
/// Downloaded, settings descriptions, player lock). Same rule as [Strings]:
/// English and Korean side by side.
extension UiStrings on Strings {
  // ---- common ------------------------------------------------------------------
  String get undo => pick('Undo', '실행 취소');
  String get refresh => pick('Refresh', '새로고침');
  String get more => pick('More', '더보기');

  // ---- home --------------------------------------------------------------------
  String get removeFromContinue => pick('Remove from Continue watching', '이어보기에서 제거');
  String removedFromContinue(String title) => pick('Removed "$title" from Continue watching', "'$title' 이어보기에서 제거했어요");
  String get openShowPage => pick('Open show page', '작품 페이지 열기');

  // ---- search ------------------------------------------------------------------
  String get recentSearches => pick('Recent searches', '최근 검색');
  String get clearAll => pick('Clear all', '모두 지우기');
  String get recentCleared => pick('Recent searches cleared', '최근 검색을 지웠어요');
  String get clearSearch => pick('Clear search', '검색어 지우기');
  String removeRecent(String q) => pick('Remove "$q"', "'$q' 지우기");

  // ---- show page ---------------------------------------------------------------
  String get jumpToEpisode => pick('Jump to episode', '에피소드로 이동');
  String get episodeNumber => pick('Episode number', '에피소드 번호');
  String get go => pick('Go', '이동');
  String episodeRangeHint(String first, String last) => pick('Between $first and $last', '$first화 ~ $last화');
  String get newestFirst => pick('Newest first', '최신순');
  String get oldestFirst => pick('Oldest first', '오래된순');
  String get selectEpisodes => pick('Select episodes', '에피소드 선택');
  String get selectAll => pick('Select all', '전체 선택');
  String get cancelSelection => pick('Cancel selection', '선택 취소');
  String get selectionHint =>
      pick('Tap to add episodes. Long-press another one to select everything in between.', '탭해서 에피소드를 추가하세요. 다른 에피소드를 길게 누르면 그 사이가 모두 선택돼요.');
  String get markAsWatched => pick('Mark as watched', '본 것으로 표시');
  String get markAsUnwatched => pick('Mark as unwatched', '안 본 것으로 표시');
  String markedWatched(int n) => pick('Marked ${n == 1 ? '1 episode' : '$n episodes'} as watched', '$n화를 본 것으로 표시했어요');
  String markedUnwatched(int n) => pick('Marked ${n == 1 ? '1 episode' : '$n episodes'} as unwatched', '$n화를 안 본 것으로 표시했어요');
  String get clearShowProgress => pick('Clear watch progress', '시청 기록 지우기');
  String get clearShowProgressQ => pick('Clear watch progress?', '시청 기록을 지울까요?');
  String get clearShowProgressBody =>
      pick('Watched marks and resume positions for this show will be removed. Downloads are kept.', '이 작품의 시청 표시와 이어보기 위치가 지워져요. 다운로드는 그대로 남아요.');
  String get showProgressCleared => pick('Watch progress cleared', '시청 기록을 지웠어요');
  String get showMore => pick('Show more', '더 보기');
  String get showLess => pick('Show less', '접기');
  String episodesToDownload(int n) => pick('Download ${n == 1 ? '1 episode' : '$n episodes'}', '$n화 다운로드');
  String get nothingInRange => pick('No episodes in this range', '이 범위에 에피소드가 없어요');
  String get alreadyDownloadedSkipped => pick('Episodes you already have are skipped.', '이미 받은 에피소드는 건너뛰어요.');
  String get qualityLabel => pick('Quality', '화질');

  // ---- downloaded --------------------------------------------------------------
  String get sortBy => pick('Sort by', '정렬');
  String get sortTitle => pick('Title', '제목');
  String get sortRecent => pick('Recently downloaded', '최근 다운로드');
  String get sortSize => pick('Size', '용량');
  String get resumeAll => pick('Resume all', '모두 재개');
  String get storageUsedOnDevice => pick('used on this device', '사용 중');
  String get cancelDownloadQ => pick('Cancel this download?', '이 다운로드를 취소할까요?');
  String get cancelDownloadBody => pick('The part downloaded so far will be removed.', '지금까지 받은 부분이 삭제돼요.');
  String get cancelDownload => pick('Cancel download', '다운로드 취소');
  String get keepDownloading => pick('Keep', '유지');
  String deletedEpisode(String n) => pick('Deleted episode $n', '$n화를 삭제했어요');
  String deletedShow(String title) => pick('Deleted "$title"', "'$title' 삭제했어요");
  String get deleteShow => pick('Delete show', '작품 삭제');
  String get openEpisodes => pick('Open episodes', '에피소드 목록 열기');

  // ---- settings ----------------------------------------------------------------
  String get autoNextHint => pick('Starts the next episode when one ends.', '한 화가 끝나면 다음 화를 바로 재생해요.');
  String get skipIntroHint => pick('Shows a Skip button during openings and endings.', '오프닝과 엔딩에서 건너뛰기 버튼을 보여줘요.');
  String get preferredServerHint => pick('Tried first. Others are used if it fails.', '먼저 시도하고, 실패하면 다른 서버를 써요.');
  String get episodesAtOnceHint => pick('How many episodes download at the same time.', '동시에 다운로드할 에피소드 수예요.');
  String get clearHistoryHint => pick('Removes watched marks and resume positions.', '시청 표시와 이어보기 위치를 지워요.');
  String get historyCleared => pick('Watch history cleared', '시청 기록을 지웠어요');
  String get useKiwiHint => pick('An extra server to try when the others fail.', '다른 서버가 실패할 때 시도하는 추가 서버예요.');
  String get advancedHint => pick('Server keys and diagnostics. Rarely needed.', '서버 키와 진단 도구예요. 거의 쓸 일이 없어요.');

  // ---- player ------------------------------------------------------------------
  String get lockControls => pick('Lock screen controls', '화면 잠금');
  String get unlockControls => pick('Unlock', '잠금 해제');
  String get lockedHint => pick('Touches are ignored until you unlock.', '잠금을 해제할 때까지 터치가 무시돼요.');
}
