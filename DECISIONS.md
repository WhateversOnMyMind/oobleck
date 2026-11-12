# Decisions

- Storage: `hive_ce` (pure Dart, no native sqlite to bundle on Windows/Android; I can't build those targets locally, so the lowest-risk option wins). Entities are JSON maps in boxes.
- State: `flutter_riverpod` v3.
- Flutter stable 3.47.9 / Dart 3.13 installed to /opt/flutter in the build sandbox.
- Live anikoto probing from the build sandbox was blocked by the sandbox policy; source layer is developed against fixtures (SYNTHETIC where noted). Use Settings > Advanced > Source diagnostics against the live site.
- Android release signing uses the debug keystore (sideloading only).
- Dropped permission_handler: it requires compileSdk 37 (AGP max 36) and the foreground-service plugin handles the notification permission itself.
- Anime4K is off until the user picks a preset in the player; 'Mode A (Fast)' is the recommended/default preset when enabling (heavy on phones). Shaders from bloc97/Anime4K (MIT) bundled with its licence.
- 2026-11-12: Live captures go in `test/fixtures/anikoto/live/` next to the SYNTHETIC ones; the synthetic tests stay because they cover cases the live show lacks (fillers, vidtube, Kiwi, plain sources).
- 2026-11-12: Show slugs come from the URL segment after `/watch/` because home cards link to episode pages (`/watch/<slug>/ep-N`).
- 2026-11-12: CI pins Flutter 3.47.9. Unpinned `stable` moved to 3.50.0, which deprecates `package:flutter/material.dart` (analyze fails) and needs AGP 9.1.1+. Upgrade deliberately later (material_ui migration + AGP bump).
- 2026-11-12: Android release signing uses a fixed PKCS12 key (alias `oobleck`) from CI secrets, kept outside the repo; falls back to the debug key with a CI warning. versionCode = CI run number so newer builds always install as updates.
- 2026-11-12: The Korean finder looks up the Japanese title (and Korean synonyms) on AniList by MAL id, because Anissia rarely matches English titles; season markers are stripped when the full title has no match.
- 2026-11-12: Korean subtitles load automatically. Anissia only lists each fansubber's latest post, so the finder reads the fansubber's blog feed (Tistory RSS, Blogspot JSON) for the "<show> N화" post, then falls back to the latest post's season pack. Show matching must agree on season and title, otherwise nothing loads (no wrong-season subtitles). Naver blogs are skipped (empty feeds, redirecting posts).
- 2026-11-12: The subtitle sync offset is stored per show (= per season) in ms and applies only to Korean/imported tracks; the site's own tracks are already in sync and always play with no offset.
- 2026-11-12: Android (Flutter-drawn) subtitle size = size setting x screen height / 720 x 0.75, matching mpv's 720p-relative font size on desktop; the default 46 gives ~20 dp on a phone. Fit mode is per show because only old 4:3 shows need it.
