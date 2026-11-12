// Oobleck watch-history sync: a Cloudflare Worker backed by D1.
//
// Accounts are a user name and a password, nothing else. The app stretches the
// password itself (PBKDF2-SHA256, 100k rounds, salt "oobleck-sync:<user>") and
// sends the 32-byte result as `key`; the server stores SHA-256(random salt ||
// key). Guessing a password from a leaked database therefore still costs the
// full PBKDF2 per guess, while each request stays inside the free plan's CPU
// budget. Sessions are random bearer tokens; only their SHA-256 is stored.
//
//   POST   /v1/register  {username, key}            -> {token, username}
//   POST   /v1/login     {username, key}            -> {token, username}
//   POST   /v1/logout                                -> {}
//   POST   /v1/sync      {since, history, shows, deletions} -> {now, history, shows, deletions}
//   DELETE /v1/account                               -> {}
//   GET    /v1/health                                -> {ok: true}

const MAX_ITEMS = 5000;
const LOCK_AFTER = 10; // failed logins in a row
const LOCK_MS = 15 * 60 * 1000;

export default {
  async fetch(request, env) {
    try {
      return await route(request, env);
    } catch (e) {
      if (e instanceof HttpError) return json({ error: e.message }, e.status);
      console.error(e);
      return json({ error: 'Server error' }, 500);
    }
  },
};

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  });
}

async function route(request, env) {
  const { pathname } = new URL(request.url);
  const m = request.method;
  if (pathname === '/v1/health' && m === 'GET') return json({ ok: true });
  if (pathname === '/v1/register' && m === 'POST') return register(env.DB, await body(request));
  if (pathname === '/v1/login' && m === 'POST') return login(env.DB, await body(request));
  if (pathname === '/v1/logout' && m === 'POST') return logout(env.DB, request);
  if (pathname === '/v1/sync' && m === 'POST') return sync(env.DB, await auth(env.DB, request), await body(request));
  if (pathname === '/v1/account' && m === 'DELETE') return deleteAccount(env.DB, await auth(env.DB, request));
  throw new HttpError(404, 'Not found');
}

async function body(request) {
  const text = await request.text();
  if (text.length > 4_000_000) throw new HttpError(413, 'Too much data');
  try {
    const v = JSON.parse(text || '{}');
    if (v && typeof v === 'object' && !Array.isArray(v)) return v;
  } catch (_) {
    // fall through
  }
  throw new HttpError(400, 'Bad JSON');
}

// ---- accounts ---------------------------------------------------------------

export function normalizeUsername(u) {
  if (typeof u !== 'string') throw new HttpError(400, 'User ID is required');
  const name = u.trim().toLowerCase();
  if (!/^[a-z0-9_.-]{3,32}$/.test(name)) {
    throw new HttpError(400, 'User ID must be 3-32 letters, numbers, dot, dash or underscore');
  }
  return name;
}

function checkKey(key) {
  if (typeof key !== 'string' || !/^[0-9a-f]{64}$/.test(key)) throw new HttpError(400, 'Bad key');
  return key;
}

const enc = new TextEncoder();

function hex(bytes) {
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function randomHex(n) {
  const b = new Uint8Array(n);
  crypto.getRandomValues(b);
  return hex(b);
}

async function sha256Hex(text) {
  return hex(await crypto.subtle.digest('SHA-256', enc.encode(text)));
}

function sameHex(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function newSession(db, userId, username) {
  const token = randomHex(32);
  const now = Date.now();
  await db
    .prepare('INSERT INTO sessions (token_hash, user_id, created_at, last_used) VALUES (?, ?, ?, ?)')
    .bind(await sha256Hex(token), userId, now, now)
    .run();
  return json({ token, username });
}

async function register(db, b) {
  const username = normalizeUsername(b.username);
  const key = checkKey(b.key);
  const salt = randomHex(16);
  const hash = await sha256Hex(salt + key);
  const res = await db
    .prepare('INSERT INTO users (username, key_hash, key_salt, created_at) VALUES (?, ?, ?, ?) ON CONFLICT(username) DO NOTHING')
    .bind(username, hash, salt, Date.now())
    .run();
  if (!res.meta || res.meta.changes !== 1) throw new HttpError(409, 'That user ID is taken');
  const user = await db.prepare('SELECT id FROM users WHERE username = ?').bind(username).first();
  return newSession(db, user.id, username);
}

async function login(db, b) {
  const username = normalizeUsername(b.username);
  const key = checkKey(b.key);
  const user = await db.prepare('SELECT * FROM users WHERE username = ?').bind(username).first();
  const wrong = new HttpError(401, 'Wrong user ID or password');
  if (!user) throw wrong;
  const now = Date.now();
  if (user.locked_until > now) throw new HttpError(429, 'Too many wrong passwords. Try again in 15 minutes.');
  if (!sameHex(await sha256Hex(user.key_salt + key), user.key_hash)) {
    const failed = user.failed + 1;
    await db
      .prepare('UPDATE users SET failed = ?, locked_until = ? WHERE id = ?')
      .bind(failed >= LOCK_AFTER ? 0 : failed, failed >= LOCK_AFTER ? now + LOCK_MS : 0, user.id)
      .run();
    throw wrong;
  }
  if (user.failed) await db.prepare('UPDATE users SET failed = 0 WHERE id = ?').bind(user.id).run();
  return newSession(db, user.id, username);
}

function bearer(request) {
  const h = request.headers.get('authorization') || '';
  const m = /^Bearer ([0-9a-f]{64})$/.exec(h);
  return m ? m[1] : null;
}

async function auth(db, request) {
  const token = bearer(request);
  if (!token) throw new HttpError(401, 'Signed out');
  const hash = await sha256Hex(token);
  const s = await db.prepare('SELECT user_id, last_used FROM sessions WHERE token_hash = ?').bind(hash).first();
  if (!s) throw new HttpError(401, 'Signed out');
  const now = Date.now();
  // One write a day at most, to stay well inside the free write quota.
  if (now - s.last_used > 86_400_000) {
    await db.prepare('UPDATE sessions SET last_used = ? WHERE token_hash = ?').bind(now, hash).run();
  }
  return s.user_id;
}

async function logout(db, request) {
  const token = bearer(request);
  if (token) await db.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(await sha256Hex(token)).run();
  return json({});
}

async function deleteAccount(db, userId) {
  await db.batch(
    ['history', 'shows', 'deletions', 'sessions'].map((t) => db.prepare(`DELETE FROM ${t} WHERE user_id = ?`).bind(userId)).concat([
      db.prepare('DELETE FROM users WHERE id = ?').bind(userId),
    ]),
  );
  return json({});
}

// ---- sync -------------------------------------------------------------------

function str(v, max) {
  return typeof v === 'string' && v.length > 0 && v.length <= max ? v : null;
}

function int(v) {
  return Number.isSafeInteger(v) && v >= 0 ? v : null;
}

function list(v) {
  if (v === undefined || v === null) return [];
  if (!Array.isArray(v) || v.length > MAX_ITEMS) throw new HttpError(400, 'Bad list');
  return v;
}

async function sync(db, userId, b) {
  const since = int(b.since) ?? 0;
  const now = Date.now();
  const stmts = [];

  for (const d of list(b.deletions)) {
    const slug = str(d && d.slug, 200);
    const at = int(d && d.at);
    if (!slug || at === null) continue;
    stmts.push(
      db
        .prepare(
          'INSERT INTO deletions (user_id, slug, at, changed_at) VALUES (?, ?, ?, ?) ' +
            'ON CONFLICT(user_id, slug) DO UPDATE SET at = MAX(at, excluded.at), changed_at = excluded.changed_at',
        )
        .bind(userId, slug, at, now),
    );
    stmts.push(
      slug === '*'
        ? db.prepare('DELETE FROM history WHERE user_id = ? AND updated_at <= ?').bind(userId, at)
        : db.prepare('DELETE FROM history WHERE user_id = ? AND slug = ? AND updated_at <= ?').bind(userId, slug, at),
    );
  }

  for (const h of list(b.history)) {
    const slug = str(h && h.slug, 200);
    const episode = str(h && h.episode, 32);
    const pos = int(h && h.positionMs);
    const dur = int(h && h.durationMs);
    const upd = int(h && h.updatedAt);
    if (!slug || !episode || pos === null || dur === null || upd === null) continue;
    // Newest client time wins; anything older than a "clear history" is dropped.
    stmts.push(
      db
        .prepare(
          'INSERT INTO history (user_id, slug, episode, position_ms, duration_ms, updated_at, changed_at) ' +
            'SELECT ?, ?, ?, ?, ?, ?, ? WHERE NOT EXISTS (' +
            "SELECT 1 FROM deletions WHERE user_id = ? AND (slug = ? OR slug = '*') AND at >= ?) " +
            'ON CONFLICT(user_id, slug, episode) DO UPDATE SET position_ms = excluded.position_ms, ' +
            'duration_ms = excluded.duration_ms, updated_at = excluded.updated_at, changed_at = excluded.changed_at ' +
            'WHERE excluded.updated_at > history.updated_at',
        )
        .bind(userId, slug, episode, pos, dur, upd, now, userId, slug, upd),
    );
  }

  for (const s of list(b.shows)) {
    const slug = str(s && s.slug, 200);
    const title = str(s && s.title, 500);
    if (!slug || !title) continue;
    const opt = (k, max) => str(s[k], max);
    stmts.push(
      db
        .prepare(
          'INSERT INTO shows (user_id, slug, title, poster, url, site_id, mal_id, changed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?) ' +
            'ON CONFLICT(user_id, slug) DO UPDATE SET title = excluded.title, poster = excluded.poster, url = excluded.url, ' +
            'site_id = excluded.site_id, mal_id = excluded.mal_id, changed_at = excluded.changed_at ' +
            'WHERE shows.title IS NOT excluded.title OR shows.poster IS NOT excluded.poster OR shows.mal_id IS NOT excluded.mal_id',
        )
        .bind(userId, slug, title, opt('poster', 2000), opt('url', 2000), opt('siteId', 100), opt('malId', 20), now),
    );
  }

  // D1 runs a batch as one transaction.
  for (let i = 0; i < stmts.length; i += 500) await db.batch(stmts.slice(i, i + 500));

  // ">=" so rows written in the same millisecond as the last pull are not missed;
  // re-applying a row is harmless on the device.
  const [hist, shows, dels] = await db.batch([
    db
      .prepare('SELECT slug, episode, position_ms, duration_ms, updated_at FROM history WHERE user_id = ? AND changed_at >= ?')
      .bind(userId, since),
    db.prepare('SELECT slug, title, poster, url, site_id, mal_id FROM shows WHERE user_id = ? AND changed_at >= ?').bind(userId, since),
    db.prepare('SELECT slug, at FROM deletions WHERE user_id = ? AND changed_at >= ?').bind(userId, since),
  ]);
  return json({
    now,
    history: hist.results.map((r) => ({
      slug: r.slug,
      episode: r.episode,
      positionMs: r.position_ms,
      durationMs: r.duration_ms,
      updatedAt: r.updated_at,
    })),
    shows: shows.results.map((r) => ({
      slug: r.slug,
      title: r.title,
      poster: r.poster,
      url: r.url,
      siteId: r.site_id,
      malId: r.mal_id,
    })),
    deletions: dels.results.map((r) => ({ slug: r.slug, at: r.at })),
  });
}
