# Oobleck — Build Plan

A personal anime player for **Windows desktop** and **Android (APK)**, built from one Flutter codebase.
Source site: **anikototv.to**. Reference for direction and UI only: `frostnova721/animestream`
(Flutter). Its anikoto provider works, but its downloads for anikoto are unimplemented and it drops
every subtitle track except English.

## Non-negotiable UX requirements (from the owner — these override anything below)
1. **Offline Library of downloaded anime, inside the app.** A "Downloads / Library" tab shows downloaded
   shows as **poster cards** (cover art, title, number of episodes downloaded, total size). Tapping a show
   opens its episode list (thumbnail or poster, episode number/title, duration, watched/progress bar);
   tapping an episode **plays it immediately in the same in-app player**, with its subtitles auto-loaded
   and works with no internet at all.
   - Store metadata with each download (show id/title, poster image **cached to disk**, synopsis, episode
     number/title, subtitle files + languages, source quality) in the app database, so the Library never
     needs the network.
   - Manage from the Library: delete episode/show, see storage used, "Download next episodes".
   - **Never** make the user browse folders or pick files to watch their downloads. **No file/directory
     pickers** in the normal flow. The only file picker in the app is the optional "Import subtitle
     file…" action and the optional "change download location" setting.
2. **Continue watching / resume where you left off (local only for now).**
   - Save position per episode every ~5 s and on pause/exit/app background, in the local database (no account, no cloud sync yet).
   - Opening an episode resumes at the saved position (with a small "Resumed at 12:34 · Start over" toast).
   - Home screen starts with a **"Continue watching"** row: the last episode of each show with a progress
     bar. One tap resumes. If the episode is finished (>90%), the card points to the next episode instead.
   - Works for both streamed and downloaded episodes (shared history; downloaded copies are preferred when present).
   - Episode lists show watched ticks and partial-progress bars.
3. **Clean, polished UI. No "developer debug" look.** Material 3 dark theme with one accent colour,
   consistent spacing, real cover art everywhere, smooth transitions, skeleton loaders instead of spinners,
   friendly empty/error states with a retry button. The player is a proper full-screen player: auto-hiding
   controls, big centered play/pause, a clean bottom bar (seek, time, CC, quality, speed, Anime4K, server,
   next episode), and the title at the top. No raw URLs, server IDs or file paths shown to the user anywhere
   (except in Settings → Advanced → Source diagnostics).

## Feature goals
1. Browse, search, show details and episode list (sub/dub, filler marks)
2. **Ad-free playback**: native player (media_kit / libmpv) plays the raw HLS stream. The site's web player is never shown.
3. **Good player UI**: seek bar with preview time, play/pause, ±10 s, speed, server switch, quality switch, sub/dub switch, fullscreen, skip intro/outro (if timestamps are available), next-episode button, keyboard shortcuts on desktop, gestures on Android (double-tap seek, swipe brightness/volume)
4. **Selectable CC**: list **all** subtitle tracks the source returns (every language, not only English), plus imported external files. Subtitle styling (size, colour, outline, background, position) and a **sync offset** control (±0.1 s steps)
5. **Korean subtitle finder**: search the web for Korean subtitle files and import with one click (details below)
6. **Anime4K upscaling** toggle in the player, default preset "Mode A (Fast)"
7. **Individual download** of an episode (video, plus subtitle files alongside)
8. **Batch / season-wide download**: select a range or the whole season, queued with pause/resume/retry, a concurrency limit and server fallback
9. Watch history, resume position, settings

## Stack (decide versions at build time; pin them in pubspec.lock)
- Flutter stable, Dart 3
- Playback: `media_kit`, `media_kit_video`, `media_kit_libs_video`
- HTTP: `dio` (needs custom headers, retries, cancel tokens)
- HTML parsing: `html`
- Crypto: `encrypt` + `crypto` (megaplay AES-CBC + HMAC-SHA256)
- State: `flutter_riverpod`
- Storage: `hive_ce` or `sqflite` (+ `sqflite_common_ffi` on Windows). Pick one and record it in DECISIONS.md
- Paths/permissions: `path_provider`, `permission_handler` (Android storage/notifications)
- Background downloads on Android: foreground service (e.g. `flutter_foreground_task`) so batch downloads survive the app going to the background

Licensing: animestream's code may be read for reference. **Check its LICENSE before copying any code.**
If it is GPL, do not copy code verbatim unless this project also adopts GPL. Prefer writing our own.
Anime4K is MIT, so its shaders can be bundled with the MIT notice.

## Source layer: anikoto (as of 2026-11-11)
Keep everything site-specific behind an interface (`lib/core/sources/source.dart`) so a second site can be
added later as a fallback. Implementation: `lib/core/sources/anikoto/`.

Common headers: `Referer: https://anikototv.to/`, `X-Requested-With: XMLHttpRequest`, and a normal
desktop Chrome User-Agent.

| Step | Request | Parse |
|---|---|---|
| Search | `GET https://anikototv.to/ajax/anime/search?keyword=<q>` | JSON `result.html` → `div.scaff.items > a` : href (show URL), `.name.d-title`, `img[src]` |
| Browse/home | `GET https://anikototv.to/home`, plus filter pages | parse cards (`a[href*="/watch/"]`) |
| Show id | `GET <show url>` (e.g. `/watch/black-clover-season-2`) | `div#watch-main[data-id]` (e.g. `8839`) |
| Episode list | `GET /ajax/episode/list/<id>?vrf=` (vrf currently empty) | JSON `result` (HTML) → `div.episodes > ul > li` → `a[data-ids]` (opaque server key), `data-num`, `data-mal`, `data-dub` ("1" = dub available), class `filler`, li `title` |
| Server list | `GET /ajax/server/list?servers=<data-ids>` | JSON `result` (HTML) → `div.servers` groups → `div.type[data-type=sub|dub] ul li[data-link-id]`. Observed servers: HD-1, HD-2, Vidstream-1, Vidstream-2 |
| Embed URL | `GET /ajax/server?get=<data-link-id>` | JSON `result.url` → embed host, e.g. `https://megaplay.buzz/stream/s-2/181751/sub?s=tcdn` or `vidtube.site/...` |
| Extra server "Kiwi" (optional) | `GET https://mapper.nekostream.site/api/mal/<malId>/<ep>/<unixSeconds>` | JSON `["Kiwi-Stream-"].sub.url` |

### Megaplay extractor (`megaplay.buzz`)
- `GET <embed url>` **with `Referer: https://anikototv.to/`**. Opening it directly without that referer
  returns an error page. Parse `#megaplay-player[data-id]`.
- `GET https://megaplay.buzz/stream/getSources?id=<data-id>[&s=<s param from embed URL>]`
  (fallback endpoint `getSourcesNew`), headers `X-Requested-With: XMLHttpRequest`, `Referer: <embed url>`.
- The response either has `sources.file` (plain) or `enc` (encrypted):
  - `enc` = base64url, AES-256-CBC, PKCS7. Key = UTF-8 `i?LMTAx0Q6,:}50U` **zero-padded to 32 bytes**,
    IV = UTF-8 `W0;27ToaUpl_P%'c`. Plaintext JSON → `.file`.
- `tracks[]`: `{file, label, kind:"captions", default}`. **Keep all of them** (all languages).
- **URL signing**: if the file path contains `/<32hex>/<32hex>/`, append
  `token=<b64url(payload)>.<b64url(HMAC_SHA256(key, payload))>` (no padding), where
  `payload = "<expires>|<hex1>/<hex2>"` (lowercase), `expires = now_unix + 90`,
  HMAC key = `MpCdnT0k3n!9f2K#xQ7vL5mR8wN1pY4s`.
  **Tokens expire after about 90 s.** The player must re-sign on reload, and the downloader must re-sign
  and retry on 403 (for the playlist and, if needed, for segments).
- Playback headers: `Referer: https://megaplay.buzz/`, `Origin: https://megaplay.buzz`.
- **Self-healing keys**: these keys come from megaplay's `e1-player.min.js` and have changed before
  (last fix seen 2026-09-13). Implement `MegaplayKeys.refresh()`, which fetches the player JS and tries
  to regex out the AES key, IV and token key. If that fails, fall back to the bundled constants. Keys are
  also overridable in Settings → Advanced, so a fix needs no rebuild.

### Vidtube extractor (`vidtube.site`)
- `GET <embed url>` → `#megaplay-player[data-id]`. `type` = last path segment (sub/dub).
- `GET https://vidtube.site/stream/getSourcesNew?id=<id>&type=<type>` → `sources.file`, `tracks[]`.
- Headers: `Referer: https://vidtube.site/`, `Origin: https://vidtube.site`.

### Resolution strategy
Resolve servers in parallel and show the first working stream immediately. Rank by a user-set server
preference, defaulting to HD-1 > HD-2 > Vidstream-1 > Vidstream-2 > Kiwi. Unknown embed hosts are logged
and skipped.

## Player
- media_kit `Player` + `Video` with **our own Flutter controls** (not the default ones)
- Pass headers through media_kit `Media(url, httpHeaders: {...})`
- Subtitles: use mpv's own sub rendering (`player.setSubtitleTrack(SubtitleTrack.uri(...))`) so ASS styling works.
  Offset: mpv property `sub-delay`. Style: `sub-font-size`, `sub-color`, `sub-border-size`, `sub-back-color`, `sub-pos`.
- Anime4K (see below) uses mpv's `glsl-shaders` property via `(player.platform as NativePlayer).setProperty`
- Remember the last position per episode; auto-next; skip intro if timestamps exist (aniskip API by MAL id: `https://api.aniskip.com/v2/skip-times/<malId>/<ep>?types=op&types=ed&episodeLength=0`)

## Anime4K
- Bundle the GLSL shaders from `bloc97/Anime4K` (latest release zip, MIT) under `assets/shaders/anime4k/`.
  Copy them to the app support directory on first run, because mpv needs real file paths.
- Presets (follow the repo's GLSL_Instructions for the exact chains; verify against the files):
  - **Mode A (Fast)** *(default)*: Clamp_Highlights → Restore_CNN_M → Upscale_CNN_x2_M → AutoDownscalePre_x2 → AutoDownscalePre_x4 → Upscale_CNN_x2_S
  - Mode B (Fast), Mode C (Fast), and an "Off" option. Optionally HQ variants on desktop.
- The path-list separator for `glsl-shaders` is `;` on Windows and `:` elsewhere.
- Android: shaders need the GPU video output, with hardware decoding that copies frames back
  (`hwdec=mediacodec-copy`) or software decoding. Set those mpv options when Anime4K is on. Show a
  one-time note that it is GPU-heavy on phones.
- Upscaling is real-time only. Downloads keep their original quality.

## Downloads
- Our own HLS downloader in Dart: fetch the master playlist → choose a variant (user quality preference)
  → fetch the media playlist → download segments with a concurrency of 4–8, retry with backoff, re-sign
  on 403 → handle `EXT-X-KEY` AES-128 decryption if present → concatenate into `.ts`.
- Container: if `ffmpeg` is on PATH (desktop), remux to `.mp4`/`.mkv` with subtitles muxed in.
  Otherwise keep `.ts` plus sidecar subtitle files (`.vtt`/`.ass`/`.srt` with a language tag in the
  file name). mpv plays these fine. Downloads play offline inside the app.
- Plain MP4 sources: ranged download with resume.
- Queue: persistent across restarts, pause/resume/cancel, per-item progress and speed, global
  concurrency (default 2 episodes at once), and server fallback when a source fails.
- **Batch**: on the episode list, choose "Download season", a range (e.g. 1–12) or multi-select; pick sub/dub and quality once.
- Save location configurable. Defaults: Windows `Videos\Oobleck\<Show>\<Show> - E01.ts`, Android app-specific Movies dir (no special permission needed).
- Android: run the queue inside a foreground service with a progress notification.

## Korean subtitle finder
Goal: from the player or the episode page, tap "Find Korean subs" → see candidates → one click → loaded into the player and saved for that episode.
1. **Anissia** (Korean anime subtitle schedule; lists Korean fansubbers' release posts per anime and episode).
   Find the current public API from its open-source repo (`anissia-net`, e.g. anissia-core) or by inspecting the website.
   Do **not** guess endpoints; verify them. Match the show by title (Japanese/English/Korean). Let the user confirm
   the match once per show and store the mapping.
2. **OpenSubtitles** REST API v1 (`api.opensubtitles.com`, `languages=ko`): optional. The user enters their own free API key in Settings.
3. Importer for a chosen link:
   - Direct file links (`.smi/.ass/.srt/.vtt/.zip`): download → unzip if needed → pick the file for this episode number.
   - Tistory / Google Drive / other blog posts: fetch the page and find attachment links by extension; if several, show a picker.
   - Naver Blog and anything not parseable: open the post in the system browser and offer "Import from file…".
4. **SMI (SAMI) parser** → convert to SRT/ASS internally. Handle EUC-KR/CP949 encoding as well as UTF-8.
5. Timing: fansubs are often timed to TV broadcasts. The sync offset control is essential, and the offset is saved per show.
6. Also: a manual "Import subtitle file…" (file picker) on both platforms.

## UI (direction like animestream, but cleaner)
- Home: continue watching, latest updates, popular; search
- Show page: poster, synopsis, sub/dub toggle, episode grid (fillers marked, watched marked, downloaded marked), batch-download button
- Player as described; Downloads page; Settings (player, subtitles, Anime4K, downloads, advanced keys, source preference)
- Dark theme, responsive: side navigation rail on desktop, bottom navigation on mobile.

## CI / builds (`.github/workflows/build.yml`)
- Triggers: push to any branch, plus `workflow_dispatch`.
- Job `windows` (windows-latest): `flutter build windows --release` → zip `build/windows/x64/runner/Release` → upload artifact `oobleck-windows`.
- Job `android` (ubuntu-latest): Java 17, `flutter build apk --release --split-per-abi` plus a universal APK → upload artifact `oobleck-android`.
  Release signing: use the debug keystore for now (fine for sideloading) and note it in the README.
- Job `test` (ubuntu): `flutter analyze` + `flutter test`.
- On tags `v*`: attach the artifacts to a GitHub Release.

## Testing (the cloud environment may not reach anikoto)
- First try live requests from the cloud machine with plain HTTP. If anikoto or megaplay is blocked
  (403 or a Cloudflare challenge), **do not try to get around it**. Work from fixtures instead.
- Fixtures under `test/fixtures/anikoto/` (search, watch page, episode list, server list, server get,
  megaplay embed, getSources plain + enc). Where live samples are unavailable, hand-write them to match
  the selectors above and mark them `SYNTHETIC` in the file.
- Unit tests: parsers, megaplay decrypt (encrypt→decrypt round trip with the known key/IV), URL signing
  (deterministic with a fixed clock), SMI parser (UTF-8 and CP949), m3u8 parsing, downloader against a
  local `shelf` server serving a generated HLS stream (including AES-128), queue persistence.
- Playback smoke test against a public HLS test stream, e.g. `https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8`.
- Add a hidden debug screen (Settings → Advanced → Source diagnostics) that runs search → episodes → servers → stream for a typed title and shows each step's raw result. This is how the owner will debug against the live site.

## Milestones (do them in order; commit and push after each)
- **M0** Flutter scaffold (Windows + Android targets), lints, CI workflow green, README
- **M1** Source layer: anikoto + megaplay + vidtube + Kiwi, with tests and fixtures; diagnostics screen
- **M2** UI: home, search, show page, episode list
- **M3** Player with custom controls, server/quality/sub-dub switching, all subtitle tracks, styling, offset, aniskip; **resume position + "Continue watching" row + watched/progress marks** (local DB)
- **M4** Downloads: single + batch, queue, Android foreground service; **offline Library tab (poster grid → episodes → one tap plays in-app, fully offline, subtitles auto-loaded)**
- **M5** Subtitles: manual import, SMI, Korean finder (Anissia, then OpenSubtitles)
- **M6** Anime4K presets
- **M7** Polish: settings, error states, empty states, icons, README with screenshots/instructions
