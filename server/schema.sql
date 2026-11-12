-- Oobleck watch-history sync (Cloudflare D1 / SQLite).
-- Apply with: npx wrangler d1 execute oobleck-sync --remote --file=schema.sql

CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE,      -- lower case
  key_hash TEXT NOT NULL,             -- hex SHA-256(salt || client key)
  key_salt TEXT NOT NULL,             -- hex, 16 random bytes
  failed INTEGER NOT NULL DEFAULT 0,  -- failed logins in a row
  locked_until INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
  token_hash TEXT PRIMARY KEY,        -- hex SHA-256(token); the token itself is never stored
  user_id INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  last_used INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS sessions_user ON sessions(user_id);

-- One row per watched episode. updated_at is the client's clock (newest wins);
-- changed_at is the server's clock (what a device has not pulled yet).
CREATE TABLE IF NOT EXISTS history (
  user_id INTEGER NOT NULL,
  slug TEXT NOT NULL,
  episode TEXT NOT NULL,
  position_ms INTEGER NOT NULL,
  duration_ms INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  changed_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, slug, episode)
);
CREATE INDEX IF NOT EXISTS history_changed ON history(user_id, changed_at);

-- Enough about each show to draw a Continue watching card on another device.
CREATE TABLE IF NOT EXISTS shows (
  user_id INTEGER NOT NULL,
  slug TEXT NOT NULL,
  title TEXT NOT NULL,
  poster TEXT,
  url TEXT,
  site_id TEXT,
  mal_id TEXT,
  changed_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, slug)
);
CREATE INDEX IF NOT EXISTS shows_changed ON shows(user_id, changed_at);

-- "Clear history" for one show (slug) or everything (slug = '*'). Entries
-- watched before `at` (client clock) are dropped on every device.
CREATE TABLE IF NOT EXISTS deletions (
  user_id INTEGER NOT NULL,
  slug TEXT NOT NULL,
  at INTEGER NOT NULL,
  changed_at INTEGER NOT NULL,
  PRIMARY KEY (user_id, slug)
);
CREATE INDEX IF NOT EXISTS deletions_changed ON deletions(user_id, changed_at);
