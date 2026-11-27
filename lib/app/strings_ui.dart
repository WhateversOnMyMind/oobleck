import 'strings.dart';

/// UI text added with the comfort pass (shared widgets, search, show page,
/// Downloaded, settings descriptions, player lock). Same rule as [Strings]:
/// English and Korean side by side.
extension UiStrings on Strings {
  String _t(String english, String korean) => isKorean ? korean : english;

  // ---- common ------------------------------------------------------------------
  String get undo => _t('Undo', '실행 취소');
  String get refresh => _t('Refresh', '새로고침');
  String get more => _t('More', '더보기');

  // ---- home --------------------------------------------------------------------
  String get removeFromContinue => _t('Remove from Continue watching', '이어보기에서 제거');
  String removedFromContinue(String title) => _t('Removed "$title" from Continue watching', "'$title' 이어보기에서 제거했어요");
  String get openShowPage => _t('Open show page', '작품 페이지 열기');

  // ---- search ------------------------------------------------------------------
  String get recentSearches => _t('Recent searches', '최근 검색');
  String get clearAll => _t('Clear all', '모두 지우기');
  String get recentCleared => _t('Recent searches cleared', '최근 검색을 지웠어요');
  String get clearSearch => _t('Clear search', '검색어 지우기');
  String removeRecent(String q) => _t('Remove "$q"', "'$q' 지우기");

  // ---- show page ---------------------------------------------------------------
  String get jumpToEpisode => _t('Jump to episode', '에피소드로 이동');
  String get episodeNumber => _t('Episode number', '에피소드 번호');
  String get go => _t('Go', '이동');
  String episodeRangeHint(String first, String last) => _t('Between $first and $last', '$first화 ~ $last화');
  String get newestFirst => _t('Newest first', '최신순');
  String get oldestFirst => _t('Oldest first', '오래된순');
  String get selectEpisodes => _t('Select episodes', '에피소드 선택');
  String get selectAll => _t('Select all', '전체 선택');
  String get cancelSelection => _t('Cancel selection', '선택 취소');
  String get selectionHint =>
      _t('Tap to add episodes. Long-press another one to select everything in between.', '탭해서 에피소드를 추가하세요. 다른 에피소드를 길게 누르면 그 사이가 모두 선택돼요.');
  String get markAsWatched => _t('Mark as watched', '본 것으로 표시');
  String get markAsUnwatched => _t('Mark as unwatched', '안 본 것으로 표시');
  String markedWatched(int n) => _t('Marked ${n == 1 ? '1 episode' : '$n episodes'} as watched', '$n화를 본 것으로 표시했어요');
  String markedUnwatched(int n) => _t('Marked ${n == 1 ? '1 episode' : '$n episodes'} as unwatched', '$n화를 안 본 것으로 표시했어요');
  String get clearShowProgress => _t('Clear watch progress', '시청 기록 지우기');
  String get clearShowProgressQ => _t('Clear watch progress?', '시청 기록을 지울까요?');
  String get clearShowProgressBody =>
      _t('Watched marks and resume positions for this show will be removed. Downloads are kept.', '이 작품의 시청 표시와 이어보기 위치가 지워져요. 다운로드는 그대로 남아요.');
  String get showProgressCleared => _t('Watch progress cleared', '시청 기록을 지웠어요');
  String get showMore => _t('Show more', '더 보기');
  String get showLess => _t('Show less', '접기');
  String episodesToDownload(int n) => _t('Download ${n == 1 ? '1 episode' : '$n episodes'}', '$n화 다운로드');
  String get nothingInRange => _t('No episodes in this range', '이 범위에 에피소드가 없어요');
  String get alreadyDownloadedSkipped => _t('Episodes you already have are skipped.', '이미 받은 에피소드는 건너뛰어요.');
  String get qualityLabel => _t('Quality', '화질');

  // ---- downloaded --------------------------------------------------------------
  String get sortBy => _t('Sort by', '정렬');
  String get sortTitle => _t('Title', '제목');
  String get sortRecent => _t('Recently downloaded', '최근 다운로드');
  String get sortSize => _t('Size', '용량');
  String get resumeAll => _t('Resume all', '모두 재개');
  String get storageUsedOnDevice => _t('used on this device', '사용 중');
  String get cancelDownloadQ => _t('Cancel this download?', '이 다운로드를 취소할까요?');
  String get cancelDownloadBody => _t('The part downloaded so far will be removed.', '지금까지 받은 부분이 삭제돼요.');
  String get cancelDownload => _t('Cancel download', '다운로드 취소');
  String get keepDownloading => _t('Keep', '유지');
  String deletedEpisode(String n) => _t('Deleted episode $n', '$n화를 삭제했어요');
  String deletedShow(String title) => _t('Deleted "$title"', "'$title' 삭제했어요");
  String get deleteShow => _t('Delete show', '작품 삭제');
  String get openEpisodes => _t('Open episodes', '에피소드 목록 열기');

  // ---- settings ----------------------------------------------------------------
  String get autoNextHint => _t('Starts the next episode when one ends.', '한 화가 끝나면 다음 화를 바로 재생해요.');
  String get skipIntroHint => _t('Shows a Skip button during openings and endings.', '오프닝과 엔딩에서 건너뛰기 버튼을 보여줘요.');
  String get preferredServerHint => _t('Tried first. Others are used if it fails.', '먼저 시도하고, 실패하면 다른 서버를 써요.');
  String get episodesAtOnceHint => _t('How many episodes download at the same time.', '동시에 다운로드할 에피소드 수예요.');
  String get clearHistoryHint => _t('Removes watched marks and resume positions.', '시청 표시와 이어보기 위치를 지워요.');
  String get historyCleared => _t('Watch history cleared', '시청 기록을 지웠어요');
  String get useKiwiHint => _t('An extra server to try when the others fail.', '다른 서버가 실패할 때 시도하는 추가 서버예요.');
  String get advancedHint => _t('Server keys and diagnostics. Rarely needed.', '서버 키와 진단 도구예요. 거의 쓸 일이 없어요.');

  // ---- player ------------------------------------------------------------------
  String get lockControls => _t('Lock screen controls', '화면 잠금');
  String get unlockControls => _t('Unlock', '잠금 해제');
  String get lockedHint => _t('Touches are ignored until you unlock.', '잠금을 해제할 때까지 터치가 무시돼요.');
}
