# Oobleck

A personal anime player for **Windows** and **Android**, built from one Flutter codebase.
Plays the raw stream in a native player (libmpv), so there are no ads and no web player.

## Features
- **Downloaded** tab: downloaded shows as poster cards, then episodes, one tap plays in the app with subtitles, no internet needed
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

Android APKs are signed with a fixed release key, so a newer build installs over an older one and keeps your
downloads and history. Stick to one APK type (`app-arm64-v8a-release.apk` for most phones): the per-CPU APKs carry a
higher version code than the universal one, so switching from per-CPU to universal counts as a downgrade.
The build number is the CI run number.

Signing setup (once): the key lives outside the repo (keep a backup; without it, updates need a reinstall).
Add two repository secrets under Settings > Secrets and variables > Actions:
- `ANDROID_KEYSTORE_BASE64`: the keystore file, base64-encoded
- `ANDROID_KEYSTORE_PASSWORD`: its password (store and key use the same one, alias `oobleck`)

Without the secrets, CI falls back to a throwaway debug key and shows a warning. For local release builds, put
`storeFile=<path to .jks>` and `storePassword=<password>` in `android/key.properties` (git-ignored).

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

## Watch-history sync (optional)
Settings → Sync signs in with a user ID and password and keeps resume positions and Continue watching the same on
every device. The server is a small Cloudflare Worker + D1 database you deploy once on the free plan:
see [server/README.md](server/README.md).

## Keyboard shortcuts (desktop player)
Space/K play, ←/→ ±5 s, J/L ±10 s, ↑/↓ volume, M mute, F fullscreen, N next, C cycle subtitles,
[ / ] speed, G/H subtitle sync −/+0.1 s (Shift: 1 s), Z picture fit / zoom / stretch, Esc back.

## Licences
Anime4K shaders (MIT, bloc97/Anime4K) are bundled in `assets/shaders/anime4k/` with their licence.
