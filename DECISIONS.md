# Decisions

- Storage: `hive_ce` (pure Dart, no native sqlite to bundle on Windows/Android; I can't build those targets locally, so the lowest-risk option wins). Entities are JSON maps in boxes.
- State: `flutter_riverpod` v3.
- Flutter stable 3.47.9 / Dart 3.13 installed to /opt/flutter in the build sandbox.
- Live anikoto probing from the build sandbox was blocked by the sandbox policy; source layer is developed against fixtures (SYNTHETIC where noted). Use Settings > Advanced > Source diagnostics against the live site.
- Android release signing uses the debug keystore (sideloading only).
- Dropped permission_handler: it requires compileSdk 37 (AGP max 36) and the foreground-service plugin handles the notification permission itself.
