import 'package:flutter/widgets.dart';

import '../core/sync/sync_api.dart';

/// UI text in English and Korean. Each entry keeps both languages side by side
/// so neither can be missing. Pick with [Strings.of] in widgets or
/// [Strings.forCode] elsewhere (the player session).
class Strings {
  const Strings._(this.isKorean);

  static const en = Strings._(false);
  static const ko = Strings._(true);

  /// Languages offered in the picker, by settings code.
  static const languages = {'en': 'English', 'ko': '한국어'};

  final bool isKorean;
  String get code => isKorean ? 'ko' : 'en';
  Locale get locale => Locale(code);

  static Strings forCode(String? code) => code == 'ko' ? ko : en;

  /// Falls back to English where no app localizations are set up (tests).
  static Strings of(BuildContext context) => Localizations.of<Strings>(context, Strings) ?? en;

  String _(String english, String korean) => isKorean ? korean : english;

  // ---- common ----------------------------------------------------------------
  String get cancel => _('Cancel', '취소');
  String get delete => _('Delete', '삭제');
  String get save => _('Save', '저장');
  String get set => _('Set', '설정');
  String get change => _('Change', '변경');
  String get clear => _('Clear', '지우기');
  String get retry => _('Retry', '다시 시도');
  String get tryAgain => _('Try again', '다시 시도');
  String get reset => _('Reset', '초기화');
  String get off => _('Off', '끄기');
  String get notSet => _('Not set', '설정 안 됨');
  String get sub => _('Sub', '자막');
  String get dub => _('Dub', '더빙');
  String get play => _('Play', '재생');
  String get episodesWord => _('Episodes', '에피소드');
  String episode(String n) => _('Episode $n', '$n화');
  String episodeCount(int n) => _('$n ${n == 1 ? 'episode' : 'episodes'}', '$n화');
  String showCount(int n) => _('$n ${n == 1 ? 'show' : 'shows'}', '작품 $n개');
  String resumeEpisode(String n) => _('Resume episode $n', '$n화 이어보기');
  String playEpisode(String n) => _('Play episode $n', '$n화 재생');
  String get bestQuality => _('Best quality', '최고 화질');
  String get bestAvailable => _('Best available', '가능한 최고 화질');

  // ---- language ---------------------------------------------------------------
  String get languageTitle => _('Language', '언어');
  String get chooseLanguage => _('Choose your language', '언어를 선택하세요');
  String get chooseLanguageHint => _('You can change it later in Settings.', '나중에 설정에서 바꿀 수 있어요.');
  String get appLanguage => _('App language', '앱 언어');
  String get continueLabel => _('Continue', '계속');

  // ---- shell -------------------------------------------------------------------
  String get navHome => _('Home', '홈');
  String get navSearch => _('Search', '검색');
  String get navDownloaded => _('Downloaded', '다운로드');
  String get navSettings => _('Settings', '설정');

  // ---- errors ------------------------------------------------------------------
  String get couldntLoad => _("Couldn't load", '불러오지 못했어요');
  String get errNetwork => _('Check your internet connection and try again.', '인터넷 연결을 확인하고 다시 시도해 주세요.');
  String get errRefused => _('The site refused the request. Try again in a moment.', '사이트가 요청을 거부했어요. 잠시 후 다시 시도해 주세요.');
  String get errGeneric => _('Something went wrong while loading this. Try again.', '불러오는 중 문제가 생겼어요. 다시 시도해 주세요.');

  // ---- home --------------------------------------------------------------------
  String get continueWatching => _('Continue watching', '이어보기');
  String get nothingToShow => _('Nothing to show yet', '아직 표시할 작품이 없어요');
  String get pullToRefresh => _('Pull down to refresh.', '아래로 당겨 새로고침하세요.');
  String resumeLine(String ep) => _('Episode $ep · resume', '$ep화 · 이어보기');
  String upNextLine(String ep) => _('Up next · Episode $ep', '다음 화 · $ep화');
  String get resumeThisEpisode => _('Resume this episode', '이 에피소드 이어보기');
  String get seeAllEpisodes => _('See all episodes of this season', '이번 시즌 전체 에피소드 보기');
  /// Home section names come from the site in English.
  String section(String name) => switch (name) {
        'Latest Episode' => _(name, '최신 에피소드'),
        'Upcoming Anime' => _(name, '방영 예정'),
        'New Release' => _(name, '새로 공개'),
        'New Added' => _(name, '새로 추가'),
        'Just Completed' => _(name, '최근 완결'),
        'Top anime' => _(name, '인기 애니'),
        _ => name,
      };

  // ---- search ------------------------------------------------------------------
  String get searchHint => _('Search anime', '애니 검색');
  String get findSomething => _('Find something to watch', '볼 작품을 찾아보세요');
  String get searchByTitle => _('Search by title. English or romaji titles work best.', '제목으로 검색하세요. 영어나 로마자 제목이 가장 잘 찾아져요.');
  String get noResults => _('No results', '검색 결과 없음');
  String nothingMatched(String q) => _('Nothing matched "$q". Try another spelling.', '"$q"에 맞는 작품이 없어요. 다른 철자로 검색해 보세요.');

  // ---- downloaded tab ----------------------------------------------------------
  String get downloadedTitle => _('Downloaded', '다운로드');
  String get pauseAll => _('Pause all', '모두 일시정지');
  String get nothingDownloaded => _('Nothing downloaded yet', '아직 다운로드한 작품이 없어요');
  String get nothingDownloadedHint => _('Download episodes from any show page and they will appear here, ready to watch offline.',
      '작품 페이지에서 에피소드를 다운로드하면 여기에 나타나요. 인터넷 없이 볼 수 있어요.');
  String libraryLine(int shows, int eps, String bytes) =>
      _('${showCount(shows)} · ${episodeCount(eps)} · $bytes used', '${showCount(shows)} · ${episodeCount(eps)} · $bytes 사용');
  String downloadingCount(int n) => _('Downloading · $n', '다운로드 중 · $n');
  String get waiting => _('Waiting…', '대기 중…');
  String pausedAt(int pct) => _('Paused · $pct%', '일시정지 · $pct%');
  String get failed => _('Failed', '실패');
  String get done => _('Done', '완료');
  String get pause => _('Pause', '일시정지');
  String get resume => _('Resume', '재개');
  String get nothingDownloadedShow => _('Nothing downloaded', '다운로드한 에피소드 없음');
  String get allRemoved => _('All episodes of this show were removed.', '이 작품의 에피소드를 모두 삭제했어요.');
  String deleteShowTitle(String t) => _('Delete $t?', '$t을(를) 삭제할까요?');
  String deleteShowBody(int n) => _('All $n downloaded episodes will be removed from this device.', '다운로드한 에피소드 $n개가 이 기기에서 삭제돼요.');
  String get deleteAllEpisodes => _('Delete all episodes', '에피소드 모두 삭제');
  String get getMore => _('Get more', '더 받기');
  String deleteEpisodeTitle(String n) => _('Delete episode $n?', '$n화를 삭제할까요?');
  String get deleteEpisodeBody => _('It will be removed from this device.', '이 기기에서 삭제돼요.');
  String get downloadTheNext => _('Download the next…', '다음 에피소드 다운로드…');
  String nextEpisodes(int n) => n == 1 ? _('Next episode', '다음 1화') : _('Next $n episodes', '다음 $n화');
  String get allCaughtUp => _("You're all caught up.", '모든 에피소드를 받았어요.');
  String addedToDownloads(int n) => _('Added $n to downloads', '$n개를 다운로드에 추가했어요');
  String get connectToDownload => _('Connect to the internet to download more episodes.', '에피소드를 더 받으려면 인터넷에 연결하세요.');
  String markWatched(bool watched) => watched ? _('Mark as unwatched', '안 본 것으로 표시') : _('Mark as watched', '본 것으로 표시');
  String get deleteEpisode => _('Delete episode', '에피소드 삭제');

  // ---- show page ---------------------------------------------------------------
  String selectedCount(int n) => _('$n selected', '$n개 선택');
  String get download => _('Download', '다운로드');
  String get downloadEpisodes => _('Download episodes', '에피소드 다운로드');
  String get offlineSavedInfo => _("You're offline. Showing saved info.", '오프라인 상태예요. 저장된 정보를 보여 드려요.');
  String get noEpisodes => _('No episodes', '에피소드 없음');
  String episodesHeader(int n) => _('Episodes · $n', '에피소드 · $n');
  String get noEpisodesYet => _('No episodes yet', '아직 에피소드가 없어요');
  String get checkBackLater => _('Check back later.', '나중에 다시 확인해 주세요.');
  String addedEpisodes(List<String> numbers) => numbers.length == 1
      ? _('Added episode ${numbers.first} to downloads', '${numbers.first}화를 다운로드에 추가했어요')
      : _('Added ${numbers.length} episodes to downloads', '에피소드 ${numbers.length}개를 다운로드에 추가했어요');
  String get wholeSeason => _('Whole season', '시즌 전체');
  String get unwatched => _('Unwatched', '안 본 에피소드');
  String get fromEpisode => _('From episode', '시작 화');
  String get toEpisode => _('To episode', '끝 화');
  String get addToDownloads => _('Add to downloads', '다운로드에 추가');
  String get filler => _('Filler', '필러');
  String get noDub => _('No dub', '더빙 없음');
  String get downloaded => _('Downloaded', '다운로드됨');
  String get queued => _('Queued', '대기 중');
  String downloadingPct(int pct) => _('Downloading $pct%', '다운로드 중 $pct%');
  String get paused => _('Paused', '일시정지');

  // ---- player ------------------------------------------------------------------
  String get back => _('Back', '뒤로');
  String playerSubtitle(String ep, {required bool offline, required bool isDub}) =>
      '${episode(ep)}${offline ? ' · $downloaded' : ''}${isDub ? ' · $dub' : ''}';
  String get back10 => _('Back 10 seconds', '10초 뒤로');
  String get forward10 => _('Forward 10 seconds', '10초 앞으로');
  String get subtitles => _('Subtitles', '자막');
  String get subtitlesOff => _('Subtitles off', '자막 끔');
  String get quality => _('Quality', '화질');
  String get speed => _('Speed', '속도');
  String get server => _('Server', '서버');
  String picture(String mode) => _('Picture: $mode (Z)', '화면: $mode (Z)');
  String get nextEpisode => _('Next episode', '다음 화');
  String get next => _('Next', '다음');
  String get fullscreen => _('Fullscreen', '전체 화면');
  String get skipIntro => _('Skip intro', '오프닝 건너뛰기');
  String get skipOutro => _('Skip outro', '엔딩 건너뛰기');
  String loadingEpisode(String n) => _('Loading episode $n…', '$n화 불러오는 중…');
  String get cantPlay => _("Can't play this episode", '이 에피소드를 재생할 수 없어요');
  String syncHud(String v) => _('Sync $v', '싱크 $v');
  String get importSubtitleFile => _('Import subtitle file…', '자막 파일 가져오기…');
  String get searchKoreanManually => _('Search Korean subs manually', '한국어 자막 직접 찾기');
  String get lookingForKorean => _('Looking for Korean subtitles automatically…', '한국어 자막을 자동으로 찾는 중…');
  String get styleAndTiming => _('Style & timing', '스타일 및 싱크');
  String get subtitleStyleTiming => _('Subtitle style & timing', '자막 스타일 및 싱크');
  String get size => _('Size', '크기');
  String get outline => _('Outline', '외곽선');
  String get position => _('Position', '위치');
  Map<String, String> get subColors => {
        _('White', '흰색'): 'FFFFFF',
        _('Yellow', '노란색'): 'FFE066',
        _('Cyan', '하늘색'): '7DF9FF',
        _('Green', '연두색'): '9BE564',
      };
  String get backgroundBox => _('Background box', '배경 상자');
  String get playbackSpeed => _('Playback speed', '재생 속도');
  String get normal => _('Normal', '보통');
  String get serverAndAudio => _('Server & audio', '서버 및 오디오');
  String get playingDownloaded => _('Playing the downloaded copy', '다운로드한 파일 재생 중');
  String get lookingForServers => _('Looking for servers…', '서버 찾는 중…');
  String get anime4kUpscaling => _('Anime4K upscaling', 'Anime4K 업스케일링');
  String get anime4kPhoneNote => _('Anime4K is GPU-heavy on phones. Turn it off if playback stutters.', 'Anime4K는 휴대폰 GPU에 부담이 커요. 끊기면 꺼 주세요.');
  String get recommended => _('Recommended', '추천');
  String anime4kMode(String id) => switch (id) {
        'off' => off,
        'a' => _('Mode A (Fast)', '모드 A (빠름)'),
        'b' => _('Mode B (Fast)', '모드 B (빠름)'),
        'c' => _('Mode C (Fast)', '모드 C (빠름)'),
        'a_hq' => _('Mode A (HQ)', '모드 A (고화질)'),
        'b_hq' => _('Mode B (HQ)', '모드 B (고화질)'),
        'c_hq' => _('Mode C (HQ)', '모드 C (고화질)'),
        _ => id,
      };
  String get subtitleSyncMs => _('Subtitle sync (ms)', '자막 싱크 (ms)');
  String get syncHelper => _('Positive = subtitles later, negative = earlier', '양수 = 자막을 늦게, 음수 = 빠르게');
  String get subtitleSync => _('Subtitle sync', '자막 싱크');
  String get syncSavedFansub => _('Saved for this season: every episode uses it. Keys: G / H (Shift for 1 s).',
      '이번 시즌에 저장돼 모든 에피소드에 적용돼요. 단축키: G / H (Shift는 1초).');
  String get syncSavedSite => _('Saved for this season. Applies to Korean and imported subtitles only; this track is already in sync.',
      '이번 시즌에 저장돼요. 한국어 자막과 가져온 자막에만 적용되고, 이 자막은 이미 싱크가 맞아요.');
  String fitMode(String name) => switch (name) {
        'fill' => _('Zoom to fill', '꽉 차게 확대'),
        'stretch' => _('Stretch', '늘이기'),
        _ => _('Fit', '맞춤'),
      };
  String get subtitlesLoaded => _('Subtitles loaded', '자막을 불러왔어요');
  String get cantReadSubtitle => _("Couldn't read that subtitle file.", '자막 파일을 읽지 못했어요.');

  // player session (toasts and errors)
  String get errStart => _("Couldn't start this episode. Check your connection and try again.", '에피소드를 시작하지 못했어요. 연결을 확인하고 다시 시도해 주세요.');
  String get errEpisodeNotFound => _('Episode not found', '에피소드를 찾을 수 없어요');
  String get errNoServer => _('No working server found. Try again in a moment.', '작동하는 서버를 찾지 못했어요. 잠시 후 다시 시도해 주세요.');
  String resumedAt(String t) => _('Resumed at $t', '$t부터 이어서 재생');
  String get startOver => _('Start over', '처음부터');
  String noKoreanFor(String ep) => _('No Korean subtitles found for episode $ep', '$ep화 한국어 자막을 찾지 못했어요');
  String koreanSubsBy(String fansubber) => _('Korean subtitles · $fansubber', '한국어 자막 · $fansubber');
  String get auto => _('Auto', '자동');
  String get errServerNoResponse => _("That server didn't respond. Try another one.", '서버가 응답하지 않아요. 다른 서버를 선택해 보세요.');
  String get errCantPlayVideo => _("This video can't be played.", '이 영상은 재생할 수 없어요.');
  String get errPlaybackStopped => _('Playback stopped. Try again or switch server.', '재생이 멈췄어요. 다시 시도하거나 서버를 바꿔 보세요.');
  String get anime4kMissing => _('Anime4K shaders are missing from this build.', '이 빌드에 Anime4K 셰이더가 없어요.');
  String anime4kRunning(String mode, int passes) => _('$mode is running ($passes shader passes)', '$mode 작동 중 (셰이더 패스 $passes개)');
  String get anime4kDidntStart => _("Anime4K didn't start on this device. See Settings > Advanced > Source diagnostics.",
      '이 기기에서 Anime4K가 시작되지 않았어요. 설정 > 고급 > 소스 진단을 확인하세요.');

  // ---- Korean subtitle sheet ---------------------------------------------------
  String get errAnissia => _("Couldn't reach Anissia. Check your connection.", '애니시아에 연결하지 못했어요. 연결을 확인해 주세요.');
  String get errSubPosts => _("Couldn't load subtitle posts.", '자막 게시물을 불러오지 못했어요.');
  String get chooseFile => _('Choose a file', '파일 선택');
  String whichFileForEpisode(String n) => _('Which file is episode $n?', '어느 파일이 $n화인가요?');
  String get whichFile => _('Which file?', '어느 파일인가요?');
  String get cantImportAuto => _("Can't import this automatically", '자동으로 가져올 수 없어요');
  String get cantImportAutoBody => _('Open the post in your browser, download the subtitle file, then import it from your files.',
      '브라우저에서 게시물을 열어 자막 파일을 받은 다음, 파일에서 가져오세요.');
  String get openPost => _('Open post', '게시물 열기');
  String get importFromFile => _('Import from file…', '파일에서 가져오기…');
  String get errOpenSubtitles => _("OpenSubtitles didn't respond. Check your API key in Settings.", 'OpenSubtitles가 응답하지 않아요. 설정에서 API 키를 확인하세요.');
  String get errOsDownload => _("Couldn't download that file. OpenSubtitles may need your account login in Settings.",
      '파일을 받지 못했어요. 설정에서 OpenSubtitles 계정 로그인이 필요할 수 있어요.');
  String get findKoreanSubs => _('Find Korean subtitles', '한국어 자막 찾기');
  String anissiaHeader(String ep) => _('Episode $ep · fansub posts from Anissia', '$ep화 · 애니시아 자막 게시물');
  String get titleHint => _('Title (Korean or Japanese works best)', '제목 (한국어나 일본어가 가장 잘 찾아져요)');
  String get noMatch => _('No match. Try the Japanese or Korean title.', '찾지 못했어요. 일본어나 한국어 제목으로 검색해 보세요.');
  String subtitlePosts(int n) => _(n == 1 ? '1 subtitle post' : '$n subtitle posts', '자막 게시물 $n개');
  String get pickShowOnce => _("Pick the right show once. We'll remember it.", '맞는 작품을 한 번만 고르면 기억해 둘게요.');
  String get showAllEpisodes => _('Show all episodes', '모든 에피소드 보기');
  String get noFansubYet => _('No Korean fansub post for this episode yet. Subtitles are often released a few hours after broadcast.',
      '이 에피소드의 한국어 자막 게시물이 아직 없어요. 보통 방영 몇 시간 뒤에 올라와요.');
  String get unknownFansubber => _('Unknown fansubber', '알 수 없는 자막 제작자');
  String get subFileTypes => _('.smi, .srt, .ass, .vtt or a .zip', '.smi, .srt, .ass, .vtt 또는 .zip');
  String get searchOpenSubtitles => _('Search OpenSubtitles', 'OpenSubtitles 검색');
  String downloadsCount(int n) => _('$n downloads', '다운로드 $n회');
  String get addOsKey => _('Add a free OpenSubtitles API key in Settings to search there too.', '설정에서 무료 OpenSubtitles API 키를 추가하면 거기서도 찾아요.');
  String get koreanImported => _('Korean · imported', '한국어 · 가져옴');

  // ---- settings ----------------------------------------------------------------
  String get settingsTitle => _('Settings', '설정');
  String get playback => _('Playback', '재생');
  String get defaultAudio => _('Default audio', '기본 오디오');
  String get subbed => _('Subbed', '자막');
  String get dubbed => _('Dubbed', '더빙');
  String get preferredServer => _('Preferred server', '선호 서버');
  String get autoNextSetting => _('Play next episode automatically', '다음 화 자동 재생');
  String get skipIntroSetting => _('Show "Skip intro" button', "'오프닝 건너뛰기' 버튼 표시");
  String get autoKoreanSetting => _('Korean subtitles automatically', '한국어 자막 자동 적용');
  String get autoKoreanHint => _('Finds a Korean fansub for each episode and turns it on', '에피소드마다 한국어 자막을 찾아 켜 줘요');
  String get anime4kHint => _('Real-time only. Downloads keep their original quality.', '재생할 때만 적용돼요. 다운로드는 원본 화질 그대로예요.');
  String get preferredLanguage => _('Preferred language', '선호 언어');
  Map<String, String> get subtitleLanguages => {
        'en': _('English', '영어'),
        'ko': _('Korean', '한국어'),
        'ja': _('Japanese', '일본어'),
        'es': _('Spanish', '스페인어'),
        'pt': _('Portuguese', '포르투갈어'),
        'fr': _('French', '프랑스어'),
        'de': _('German', '독일어'),
        'ar': _('Arabic', '아랍어'),
        'id': _('Indonesian', '인도네시아어'),
      };
  String get styleHint => _('Open CC > Style & timing while watching to adjust size, colour, outline and sync.',
      '시청 중 CC > 스타일 및 싱크에서 크기, 색, 외곽선, 싱크를 조절하세요.');
  String get osKey => _('OpenSubtitles API key', 'OpenSubtitles API 키');
  String get osKeyHint => _('Optional. Enables searching OpenSubtitles for Korean subs.', '선택 사항. OpenSubtitles에서 한국어 자막을 검색할 수 있어요.');
  String get osUser => _('OpenSubtitles username', 'OpenSubtitles 사용자 이름');
  String get osPass => _('OpenSubtitles password', 'OpenSubtitles 비밀번호');
  String get downloads => _('Downloads', '다운로드');
  String get downloadQuality => _('Download quality', '다운로드 화질');
  String get episodesAtOnce => _('Episodes at once', '동시 다운로드 수');
  String get downloadLocation => _('Download location', '다운로드 위치');
  String get storageUsed => _('Storage used by downloads', '다운로드 사용 용량');
  String get syncHeader => _('Sync', '동기화');
  String get data => _('Data', '데이터');
  String get clearHistory => _('Clear watch history', '시청 기록 지우기');
  String get clearHistoryQ => _('Clear watch history?', '시청 기록을 지울까요?');
  String get clearHistoryBody => _('Resume positions and Continue watching will be reset. Downloads are kept.', '이어보기 위치와 이어보기 목록이 초기화돼요. 다운로드는 그대로예요.');
  String get advanced => _('Advanced', '고급');
  String get useKiwi => _('Use Kiwi server', 'Kiwi 서버 사용');
  String get megaplayKeyHint => _('Leave empty to use the built-in key.', '비워 두면 내장 키를 써요.');
  String get sourceDiagnostics => _('Source diagnostics', '소스 진단');
  String get sourceDiagnosticsHint => _('Step through search, episodes, servers and streams.', '검색, 에피소드, 서버, 스트림을 단계별로 확인해요.');
  String get deleteSyncAccount => _('Delete sync account', '동기화 계정 삭제');
  String get deleteSyncAccountHint => _('Removes the account and its history from the server. History on this device is kept.',
      '서버에서 계정과 기록을 삭제해요. 이 기기의 기록은 그대로예요.');
  String get deleteSyncAccountQ => _('Delete sync account?', '동기화 계정을 삭제할까요?');
  String get deleteSyncAccountBody => _('The account and the history stored on the server are deleted for good. Other devices get signed out.',
      '계정과 서버에 저장된 기록이 영구 삭제돼요. 다른 기기는 로그아웃돼요.');
  String get about => _('About', '정보');
  String aboutLine(String platform) => _('Personal anime player · $platform', '개인용 애니 플레이어 · $platform');

  // ---- diagnostics (output stays English: it's a developer log) ----------------
  String get title => _('Title', '제목');
  String get run => _('Run', '실행');
  String get refreshKeys => _('Refresh keys', '키 새로고침');
  String get recentLog => _('Recent log', '최근 로그');

  // ---- sync --------------------------------------------------------------------
  String get signIn => _('Sign in', '로그인');
  String get createAccount => _('Create account', '계정 만들기');
  String get syncWatchHistory => _('Sync watch history', '시청 기록 동기화');
  String get syncPitch => _('Sign in with a user ID and password to keep Continue watching the same on every device.',
      '아이디와 비밀번호로 로그인하면 모든 기기에서 이어보기가 똑같이 유지돼요.');
  String signedInAs(String u) => _('Signed in as $u', '$u(으)로 로그인됨');
  String get syncing => _('Syncing…', '동기화 중…');
  String get syncNow => _('Sync now', '지금 동기화');
  String get signOut => _('Sign out', '로그아웃');
  String get signOutHint => _('History on this device is kept.', '이 기기의 기록은 그대로예요.');
  String tapToSync(String ago) => _('$ago · tap to sync now', '$ago · 눌러서 지금 동기화');
  String get notSyncedYet => _('Not synced yet', '아직 동기화 안 됨');
  String get syncedJustNow => _('Synced just now', '방금 동기화됨');
  String syncedMinAgo(int m) => _('Synced $m min ago', '$m분 전 동기화됨');
  String syncedHoursAgo(int h) => _('Synced $h h ago', '$h시간 전 동기화됨');
  String syncedOn(String date) => _('Synced $date', '$date 동기화됨');
  String get userId => _('User ID', '아이디');
  String get password => _('Password', '비밀번호');
  String get passwordAgain => _('Password again', '비밀번호 확인');
  String get syncServer => _('Sync server', '동기화 서버');
  String get noReset => _("There is no password reset: if you forget it, create a new account. Use a password you don't use anywhere else.",
      '비밀번호 찾기 기능이 없어요. 잊어버리면 새 계정을 만들어야 해요. 다른 곳에서 쓰지 않는 비밀번호를 사용하세요.');
  String get errServerAddress => _('Enter the sync server address.', '동기화 서버 주소를 입력하세요.');
  String get errServerScheme => _('The server address should start with https://', '서버 주소는 https://로 시작해야 해요');
  String get errUserId => _('User ID: 3-32 letters, numbers, dot, dash or underscore.', '아이디: 영문, 숫자, 점(.), 대시(-), 밑줄(_) 3~32자.');
  String get errPassword => _('Password: at least 8 characters.', '비밀번호: 8자 이상.');
  String get errPasswordsDiffer => _("Passwords don't match.", '비밀번호가 서로 달라요.');
  String get errSignIn => _("Couldn't sign in.", '로그인하지 못했어요.');
  String get errSyncFailed => _('Sync failed.', '동기화에 실패했어요.');
  String get errSignedOut => _('Signed out. Sign in again.', '로그아웃됐어요. 다시 로그인하세요.');
  String get errNoSyncServer => _('No sync server set.', '동기화 서버가 설정되지 않았어요.');
  String get errSyncUnreachable => _("Can't reach the sync server.", '동기화 서버에 연결할 수 없어요.');
  String get errUserTaken => _('That user ID is taken', '이미 사용 중인 아이디예요');
  String get errWrongPassword => _('Wrong user ID or password', '아이디 또는 비밀번호가 틀렸어요');
  String get errLocked => _('Too many wrong passwords. Try again in 15 minutes.', '비밀번호를 너무 많이 틀렸어요. 15분 뒤에 다시 시도하세요.');
  String syncError(Object e) {
    if (e is! SyncException) return errSyncFailed;
    return switch (e.kind) {
      SyncError.noServer => errNoSyncServer,
      SyncError.unreachable => errSyncUnreachable,
      SyncError.signedOut => errSignedOut,
      SyncError.taken => errUserTaken,
      SyncError.wrongPassword => errWrongPassword,
      SyncError.locked => errLocked,
      SyncError.invalid => isKorean ? errUserId : e.message,
      SyncError.server => syncServerError(e.status),
    };
  }

  String syncServerError(int? code) => _('Sync server error${code == null ? '' : ' ($code)'}.', '동기화 서버 오류${code == null ? '' : ' ($code)'}.');
}

/// Hooks [Strings] into Flutter's localizations so [Strings.of] follows
/// `MaterialApp.locale`.
class StringsDelegate extends LocalizationsDelegate<Strings> {
  const StringsDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en' || locale.languageCode == 'ko';
  @override
  Future<Strings> load(Locale locale) async => Strings.forCode(locale.languageCode);
  @override
  bool shouldReload(StringsDelegate old) => false;
}
