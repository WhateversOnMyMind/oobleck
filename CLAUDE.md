# CLAUDE.md — standing instructions

Read `PLAN.md` first. It is the spec.

## Work autonomously
The owner is asleep while this runs and **cannot answer questions**. So:
- **Never stop to ask.** When a choice is ambiguous, pick the sensible option, record it in
  `DECISIONS.md` (one line: decision + why), and keep going.
- Work through the milestones in `PLAN.md` in order. When one is done, start the next one straight away.
- If something is blocked (a site unreachable, an API unknown, a package broken), stub it behind the
  interface, add a `TODO(blocked):` note plus an entry in `STATUS.md`, and move on to the next item.
  Do not spin on one problem for long.
- Keep CI green. If the build breaks, fixing it comes before new features.
- **Commit and push after every meaningful step**, at least once per milestone, with clear messages.
  Pushed work survives if the session ends early.
- Keep `STATUS.md` current: what's done, what's partial, what's blocked, and how to test each feature.
  This is the first thing the owner reads in the morning.
- When everything is done (or you run out of time), make sure the last push has a green CI build with
  downloadable Windows and Android artifacts, and open a pull request into the default branch summarizing
  STATUS.md (if you are working on a separate branch).

## Hard rules
- **Never try to get around bot protection.** No Cloudflare/Turnstile/CAPTCHA solving, TLS
  fingerprint impersonation, or proxy rotation. If a site blocks this machine, use fixtures and move on.
- Never commit secrets. Optional API keys (OpenSubtitles) are entered by the user in Settings.
- Don't copy code from `frostnova721/animestream` unless its license allows it for this project
  (check first). Reading it for reference is fine.
- Keep everything site-specific inside `lib/core/sources/<site>/`. The rest of the app talks to the `Source` interface only.

## Conventions
- Flutter stable, Dart 3, null safety, `flutter_lints` (plus stricter rules if cheap)
- Riverpod for state. Avoid global singletons except the logger.
- `flutter analyze` must be clean, and `flutter test` must pass before each push.
- Small files, clear names, and doc comments on anything site-specific (selectors, keys, endpoints) with the date they were observed.
