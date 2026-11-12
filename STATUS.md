# Status

Everything in PLAN.md M0 to M7 is implemented. The cloud build sandbox could not reach the live site, so the
first run was built against hand-written `SYNTHETIC` fixtures.

**2026-11-12 (local run):** the live site *is* reachable with plain HTTP from the owner's machine. The source
chain was checked live up to the decrypted stream URL, real responses are saved in `test/fixtures/anikoto/live/`
(see its README), and `test/anikoto_live_fixtures_test.dart` runs the parsers and extractors against them.
- Live chain: search → show page → episode list → server list → embed URL → megaplay embed → `getSources`
  → AES decrypt with the bundled key → `master.m3u8` URL. **All match PLAN.md.**
- Fixed: home cards link to episodes (`/watch/<show>/ep-7`), so every card got the slug `ep-7`. Sections
  collapsed to a few cards, and tapping one opened a non-existent show. Slugs now come from the segment after `/watch/`.
- Fixed: the synopsis included the "[more]" toggle text.
- Added: intro/outro from `skip_data` in `/ajax/server?get=` as a fallback when the extractor gives none.
- Seen live: all four servers (HD-1, HD-2, Vidstream-1, Vidstream-2) are on megaplay.buzz; Vidstream-1 uses a
  `/videojs/` embed with the same `getSources` endpoint. No vidtube.site embed was seen, and Kiwi was not checked.
- **Verified on Windows (owner's PC, CI build of `4c915c2`):** streaming playback from megaplay works, and Anime4K
  runs (the player reads mpv's `vo-passes` after a preset is picked and reports it in a toast).
- Fixed: downloads were 13-second "videos" that ended at once, so auto-next skipped to the following episode.
  Megaplay's CDN puts a 1x1 PNG header before each TS segment; ffmpeg then remuxed the joined file as PNG frames.
  Segments are now unwrapped to the first TS packet and the remux forces MPEG-TS input. Downloads made before
  this fix are broken: delete and re-download them
- Fixed: re-signing an already signed URL left a literal `$1` in the path (`master.m3u8$1?token=`), so every stream
  failed with 404. Found from the in-app log.

## Done (with tests: `flutter test`, all passing)
- **M0** Scaffold, lints, CI (`test`, `windows`, `android`, release on `v*` tags), README
- **M1** Source layer: search / show / episodes / servers / embed; Megaplay (AES, URL signing, key refresh),
  Vidtube, Kiwi; server preference; diagnostics screen. Fixtures in `test/fixtures/anikoto/` (all SYNTHETIC)
- **M2** Home (Continue watching + sections), search, show page (sub/dub, watched ticks, progress bars, filler tags,
  downloaded marks, multi-select and batch download sheet), skeleton loaders and error/empty states
- **M3** Player: custom controls, resume + "Resumed at … · Start over", progress saved every 5 s and on pause/exit/background,
  quality (HLS variants), server, sub/dub, speed, all subtitle tracks, style + sync offset (saved per show),
  aniskip + source intro/outro, auto-next, gestures (Android) and keyboard shortcuts (desktop)
- **M4** Downloads: own HLS downloader (AES-128, retries, re-sign on 403, resumable parts), plain MP4 ranged resume,
  persistent queue, concurrency limit, server fallback, Android foreground service, optional ffmpeg remux.
  **Library tab**: poster grid, show page with episodes, one tap plays offline, delete, storage used, "Get more".
  Posters are cached to disk and metadata is stored in the database
- **M5** Subtitles: file import, SMI to SRT, CP949 decoding, Anissia finder (endpoints verified live 2026-11-11),
  attachment importer (direct, zip, Tistory-style links, Google Drive), browser + file fallback, OpenSubtitles (optional)
- **M6** Anime4K: bundled shaders, presets A/B/C Fast and HQ (chains verified against the repo)
- **M7** Settings, empty/error states, README

## Verified automatically (beyond unit tests)
- `playback` CI job (real libmpv): plays a public HLS stream, seeks, changes speed, accepts the subtitle and Anime4K
  mpv properties; and drives the real `PlayerSession` through the **offline path** (downloaded file, sidecar
  subtitles auto-selected, resume at the saved position with the toast, per-show sync offset, progress saved).
  Run locally with `OOBLECK_PLAYBACK=1 flutter test test/playback_smoke_test.dart test/player_session_test.dart`.
- ffmpeg remux test (real ffmpeg); OpenSubtitles request/login/download flow against fixtures shaped like the v1 docs.

Note: the `playback` CI job has not yet completed on a GitHub runner (its apt step could not reach Ubuntu's mirrors
in two attempts). The same tests pass locally with libmpv 0.37 + ffmpeg. The job is non-blocking.

## Still needs a real device or the live site (cannot be automated here)
- Long sessions on the live CDN: playback works on Windows; if a stream ever stops mid-episode with HTTP 403 in the
  log, segments need per-request tokens and the player needs a local re-signing proxy
- Android: foreground service notification, Anime4K with `mediacodec-copy`, Flutter-rendered subtitles
  (libass needs a bundled font on Android, so Android uses Flutter text; ASS styling is desktop-only for now)
- OpenSubtitles with a real API key (the account-login requirement for downloads is unconfirmed)
- Windows fullscreen toggling, and the custom controls' layout/gestures (no UI test drives them yet)

## How to test each feature
- Library: download an episode from a show page (download icon), open the Library tab, tap the poster, tap the episode, turn Wi-Fi off
- Resume: watch a minute, back out, reopen: toast "Resumed at …"; Home shows it under Continue watching
- Korean subs: in the player, CC > Find Korean subs. The search box starts with the Korean title found via the show's Japanese title (AniList by MAL id)
- Anime4K: CC bar sparkle icon

## Blocked / TODO
- `TODO(blocked)`: Kiwi not checked live; OpenSubtitles needs a user key
- Android signing: add the `ANDROID_KEYSTORE_BASE64` and `ANDROID_KEYSTORE_PASSWORD` repository secrets (see README); until then CI warns and uses a throwaway key
- CI is pinned to Flutter 3.47.9. Flutter 3.50 (stable since 2026-11-11) broke `analyze` (material.dart
  deprecated in favour of `material_ui`) and the Android build (needs AGP 9.1.1+); upgrading is a separate task
- Local dev: Flutter 3.47.9 is installed at `C:\Users\PC\flutter` (analyze + test work). A local Windows build
  also needs Visual Studio with "Desktop development with C++" and Windows Developer Mode (plugin symlinks);
  CI builds the Windows and Android artifacts
