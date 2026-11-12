# Oobleck sync server

An optional Cloudflare Worker with a D1 database that keeps watch history (resume
positions, Continue watching, "clear history") the same on every device. Accounts
are only a user ID and a password. The free Workers and D1 plans are plenty for
personal use (100k requests a day, 5 GB).

## Deploy (once, about 5 minutes)

You need a free Cloudflare account (https://dash.cloudflare.com/sign-up) and Node 18+.

```bash
cd server
npx wrangler@4 login                       # opens the browser: allow access
npx wrangler@4 d1 create oobleck-sync      # prints a database_id
```

Put the printed `database_id` into `wrangler.toml` (it is an identifier, not a secret), then:

```bash
npx wrangler@4 d1 execute oobleck-sync --remote --file=schema.sql
npx wrangler@4 deploy                      # prints https://oobleck-sync.<you>.workers.dev
```

Then either:
- type that address into the app (Settings → Sync → Sign in → Sync server), or
- bake it into the builds: GitHub → Settings → Secrets and variables → Actions →
  **Variables** → `OOBLECK_SYNC_URL` = the address. CI passes it as
  `--dart-define=OOBLECK_SYNC_URL=...`, and the address field is hidden.

To update the server later: `npx wrangler@4 deploy` again.

## How it works

- `POST /v1/register`, `/v1/login` with `{username, key}` return a bearer token.
  `key` is PBKDF2-SHA256(password, "oobleck-sync:" + username, 100k rounds) worked
  out in the app; the server stores SHA-256(random salt + key). The password never
  leaves the device and a leaked database still costs a full PBKDF2 per guess.
  10 wrong passwords in a row lock the account for 15 minutes.
- `POST /v1/sync` with `{since, history, shows, deletions}` uploads changes and
  returns everything that changed on the server since `since`. The newest
  `updatedAt` wins per episode. A "clear history" is kept as a deletion so other
  devices drop the same entries and older uploads cannot bring them back.
- `POST /v1/logout`, `DELETE /v1/account`.

## Test locally

```bash
node --test test/*.test.js                         # worker tests on Node's SQLite
node --no-warnings test/dev_server.js 8787 sync.db # a local server for the app
```

With the local server running, use `http://127.0.0.1:8787` as the sync server in
the app (on the same PC). `flutter test test/sync_test.dart` runs the app's sync
code against it end to end.
