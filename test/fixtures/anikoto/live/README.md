# Live captures (2026-11-12)

Real responses from anikototv.to and megaplay.buzz, fetched with plain HTTP and the headers in PLAN.md
(Referer `https://anikototv.to/`, `X-Requested-With: XMLHttpRequest`, desktop Chrome User-Agent).
Show: *Black Clover Season 2* (`/watch/black-clover-season-2`, site id 8839, MAL 61967), episode 1.

| File | Request |
|---|---|
| `search.json` | `GET /ajax/anime/search?keyword=black clover` |
| `watch.html` | `GET /watch/black-clover-season-2` |
| `home.html` | `GET /home` |
| `episodes.json` | `GET /ajax/episode/list/8839?vrf=` |
| `servers.json` | `GET /ajax/server/list?servers=<episode 1 data-ids>` |
| `server_hd1.json` | `GET /ajax/server?get=<HD-1 sub link id>` (includes `skip_data`) |
| `server_vs1.json` | `GET /ajax/server?get=<Vidstream-1 sub link id>` (megaplay `/videojs/` embed) |
| `megaplay_embed.html` | `GET https://megaplay.buzz/stream/s-2/181751/sub?s=tcdn` |
| `megaplay_videojs_embed.html` | `GET https://megaplay.buzz/videojs/stream/s-2/181751/sub` |
| `getsources_enc.json` | `GET https://megaplay.buzz/stream/getSources?id=180105&s=tcdn` (encrypted `enc`) |

Observations:
- `div#watch-main` has `data-id` but no `data-mal`; the MAL id is on each episode link (`data-mal`).
- Servers seen: HD-1, HD-2, Vidstream-1, Vidstream-2, all on megaplay.buzz (Vidstream-1 via `/videojs/`).
  No vidtube.site embed was seen for this show.
- The bundled AES key/IV still decrypt `enc` (plaintext `{"file":".../master.m3u8"}`).
- Stream playback itself (signed CDN URLs) was not fetched here; verify it in the app.
