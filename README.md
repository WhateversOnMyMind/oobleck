# Oobleck

A personal anime player for **Windows** and **Android**, built from one Flutter codebase.
Plays the raw stream in a native player (libmpv), so there are no ads and no web player.

## Features
- Offline **Library**: downloaded shows as poster cards, then episodes, one tap plays in the app with subtitles, no internet needed
- **Continue watching** on Home, with resume positions saved locally
- Custom full-screen player: auto-hiding controls, seek, speed, quality, server, sub/dub, next episode, skip intro/outro
- All subtitle tracks the source provides (every language), plus import, styling and a sync offset
- Korean subtitle finder (Anissia, optional OpenSubtitles) with SMI / CP949 support
- Anime4K real-time upscaling (Mode A/B/C, Fast and HQ)
- Single and batch downloads with a persistent queue (pause, resume, retry, server fallback)

## Install
Every push builds artifacts in GitHub Actions (`build` workflow):
- `oobleck-windows`: unzip and run `oobleck.exe`
- `oobleck-android`: sideload an APK (the universal one, or the one for your CPU)

The Android release build is signed with the **debug keystore**, which is fine for sideloading.
Tagging `v*` attaches the artifacts to a GitHub Release.

## Develop
```bash
flutter pub get
flutter analyze
flutter test
flutter run -d windows   # or an Android device
```
Site-specific code lives in `lib/core/sources/anikoto/` and `lib/core/sources/extractors/`.
Everything else talks to the `Source` interface. If the site changes, use
**Settings > Advanced > Source diagnostics** to see each step's raw result. Megaplay keys can be
overridden there without a rebuild.

## Keyboard shortcuts (desktop player)
Space/K play, ←/→ ±5 s, J/L ±10 s, ↑/↓ volume, M mute, F fullscreen, N next, C cycle subtitles,
[ / ] speed, G/H subtitle sync −/+0.1 s, Esc back.

## Licences
Anime4K shaders (MIT, bloc97/Anime4K) are bundled in `assets/shaders/anime4k/` with their licence.
