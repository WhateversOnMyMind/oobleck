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
const MAX_BODY = 4_000_000;
// Stored rows per account; far beyond any real watch history.
const MAX_HISTORY_ROWS = 50_000;
const MAX_SHOW_ROWS = 10_000;
// Sessions unused this long are dropped; each account keeps at most this many.
const SESSION_IDLE_MS = 180 * 86_400_000;
const MAX_SESSIONS = 20;

// Rate limits, counted per bucket in fixed windows (see `hit`). Wrong
// passwords are counted per account *and* address, so someone guessing from
// one address cannot lock the owner out of their account elsewhere.
const WINDOW_MS = 15 * 60 * 1000;
const LIMITS = {
  login: 10, // wrong passwords per account per address
  loginIp: 50, // wrong passwords per address, any account
  register: 5, // new accounts per address
};

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
  if (pathname === '/v1/register' && m === 'POST') return register(env.DB, await body(request), clientIp(request));
  if (pathname === '/v1/login' && m === 'POST') return login(env.DB, await body(request), clientIp(request));
  if (pathname === '/v1/logout' && m === 'POST') return logout(env.DB, request);
  if (pathname === '/v1/sync' && m === 'POST') return sync(env.DB, await auth(env.DB, request), await body(request));
  if (pathname === '/v1/account' && m === 'DELETE') return deleteAccount(env.DB, await auth(env.DB, request));
  throw new HttpError(404, 'Not found');
}

async function body(request) {
  // Refuse big bodies before reading them.
  const declared = Number(request.headers.get('content-length') || 0);
  if (declared > MAX_BODY) throw new HttpError(413, 'Too much data');
  const text = await request.text();
  if (text.length > MAX_BODY) throw new HttpError(413, 'Too much data');
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
  await db.batch([
    db
      .prepare('INSERT INTO sessions (token_hash, user_id, created_at, last_used) VALUES (?, ?, ?, ?)')
      .bind(await sha256Hex(token), userId, now, now),
    // Drop idle sessions, and keep only the newest few per account.
    db.prepare('DELETE FROM sessions WHERE user_id = ? AND last_used < ?').bind(userId, now - SESSION_IDLE_MS),
    db
      .prepare(
        'DELETE FROM sessions WHERE user_id = ? AND token_hash NOT IN ' +
          '(SELECT token_hash FROM sessions WHERE user_id = ? ORDER BY last_used DESC, created_at DESC LIMIT ?)',
      )
      .bind(userId, userId, MAX_SESSIONS),
  ]);
  return json({ token, username });
}

function clientIp(request) {
  return request.headers.get('cf-connecting-ip') || 'unknown';
}

// The rate-limit table arrived after the first deploy; create it on first use
// (once per isolate) so an existing database needs no manual migration.
let attemptsReady = null;
function ensureAttempts(db) {
  attemptsReady ??= db
    .prepare('CREATE TABLE IF NOT EXISTS attempts (bucket TEXT PRIMARY KEY, count INTEGER NOT NULL, window_start INTEGER NOT NULL)')
    .run()
    .catch((e) => {
      attemptsReady = null;
      throw e;
    });
  return attemptsReady;
}

// Counts one event in `bucket` and returns the count in the current window.
// One atomic statement, so parallel requests cannot all read a stale count.
async function hit(db, bucket, now) {
  await ensureAttempts(db);
  const row = await db
    .prepare(
      'INSERT INTO attempts (bucket, count, window_start) VALUES (?, 1, ?) ' +
        'ON CONFLICT(bucket) DO UPDATE SET ' +
        'count = CASE WHEN attempts.window_start <= ? THEN 1 ELSE attempts.count + 1 END, ' +
        'window_start = CASE WHEN attempts.window_start <= ? THEN excluded.window_start ELSE attempts.window_start END ' +
        'RETURNING count',
    )
    .bind(bucket, now, now - WINDOW_MS, now - WINDOW_MS)
    .first();
  return row ? row.count : 1;
}

async function countOf(db, bucket, now) {
  await ensureAttempts(db);
  const row = await db.prepare('SELECT count, window_start FROM attempts WHERE bucket = ?').bind(bucket).first();
  return row && row.window_start > now - WINDOW_MS ? row.count : 0;
}

const tooMany = () => new HttpError(429, 'Too many wrong passwords. Try again in 15 minutes.');

async function register(db, b, ip) {
  const username = normalizeUsername(b.username);
  const key = checkKey(b.key);
  if ((await hit(db, `register:${ip}`, Date.now())) > LIMITS.register) {
    throw new HttpError(429, 'Too many new accounts from here. Try again later.');
  }
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

async function login(db, b, ip) {
  const username = normalizeUsername(b.username);
  const key = checkKey(b.key);
  const now = Date.now();
  const bucket = `login:${username}:${ip}`;
  const ipBucket = `login-ip:${ip}`;
  if ((await countOf(db, bucket, now)) >= LIMITS.login || (await countOf(db, ipBucket, now)) >= LIMITS.loginIp) {
    throw tooMany();
  }
  const user = await db.prepare('SELECT * FROM users WHERE username = ?').bind(username).first();
  if (!user || !sameHex(await sha256Hex(user.key_salt + key), user.key_hash)) {
    // Counted atomically: of N parallel guesses only the first few get an answer.
    const n = await hit(db, bucket, now);
    const nIp = await hit(db, ipBucket, now);
    if (n > LIMITS.login || nIp > LIMITS.loginIp) throw tooMany();
    throw new HttpError(401, 'Wrong user ID or password');
  }
  await db.prepare('DELETE FROM attempts WHERE bucket = ?').bind(bucket).run();
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
  if (now - s.last_used > SESSION_IDLE_MS) {
    await db.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(hash).run();
    throw new HttpError(401, 'Signed out');
  }
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

  const incomingHistory = list(b.history);
  const incomingShows = list(b.shows);
  if (incomingHistory.length || incomingShows.length) {
    const [h, sh] = await db.batch([
      db.prepare('SELECT COUNT(*) AS n FROM history WHERE user_id = ?').bind(userId),
      db.prepare('SELECT COUNT(*) AS n FROM shows WHERE user_id = ?').bind(userId),
    ]);
    const full = h.results[0].n + incomingHistory.length > MAX_HISTORY_ROWS || sh.results[0].n + incomingShows.length > MAX_SHOW_ROWS;
    if (full) throw new HttpError(413, 'This account has too much history stored');
  }

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

  for (const h of incomingHistory) {
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

  for (const s of incomingShows) {
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
