# Status

Everything in PLAN.md M0 to M7 is implemented. Nothing could be run against the **live anikoto site** from the
build sandbox (probing it was blocked, and the plan says not to work around that), so the source layer is
verified only against hand-written `SYNTHETIC` fixtures. First thing to do: run **Settings > Advanced > Source
diagnostics** and check each step against the live site.

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

## Still needs a real device or the live site (cannot be automated here)
- Live anikoto/megaplay flow, including token expiry mid-playback (player re-signs and reloads on error;
  a stream whose segments need per-request tokens may need a local re-signing proxy)
- Android: foreground service notification, Anime4K with `mediacodec-copy`, Flutter-rendered subtitles
  (libass needs a bundled font on Android, so Android uses Flutter text; ASS styling is desktop-only for now)
- OpenSubtitles with a real API key (the account-login requirement for downloads is unconfirmed)
- Windows fullscreen toggling, and the custom controls' layout/gestures (no UI test drives them yet)

## How to test each feature
- Library: download an episode from a show page (download icon), open the Library tab, tap the poster, tap the episode, turn Wi-Fi off
- Resume: watch a minute, back out, reopen: toast "Resumed at …"; Home shows it under Continue watching
- Korean subs: in the player, CC > Find Korean subs
- Anime4K: CC bar sparkle icon

## Blocked / TODO
- `TODO(blocked)`: live verification of anikoto (see above); OpenSubtitles needs a user key
