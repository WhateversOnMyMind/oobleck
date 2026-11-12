// Runs the worker against the real schema on Node's built-in SQLite, through a
// small stand-in for the D1 API (prepare/bind/first/all/run/batch).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import worker from '../src/index.js';

class Stmt {
  constructor(db, sql, args = []) {
    this.db = db;
    this.sql = sql;
    this.args = args;
  }
  bind(...args) {
    return new Stmt(this.db, this.sql, args);
  }
  async first() {
    return this.db.prepare(this.sql).get(...this.args) ?? null;
  }
  async all() {
    return { results: this.db.prepare(this.sql).all(...this.args) };
  }
  async run() {
    const r = this.db.prepare(this.sql).run(...this.args);
    return { meta: { changes: Number(r.changes) } };
  }
}

function fakeD1() {
  const db = new DatabaseSync(':memory:');
  db.exec(readFileSync(new URL('../schema.sql', import.meta.url), 'utf8'));
  return {
    raw: db,
    prepare: (sql) => new Stmt(db, sql),
    async batch(stmts) {
      db.exec('BEGIN');
      try {
        const out = [];
        for (const s of stmts) out.push(/^\s*SELECT/i.test(s.sql) ? await s.all() : await s.run());
        db.exec('COMMIT');
        return out;
      } catch (e) {
        db.exec('ROLLBACK');
        throw e;
      }
    },
  };
}

const KEY = 'a'.repeat(64);
const OTHER_KEY = 'b'.repeat(64);

function client(env) {
  return async (method, path, body, token) => {
    const headers = { 'content-type': 'application/json' };
    if (token) headers.authorization = `Bearer ${token}`;
    const res = await worker.fetch(
      new Request(`https://sync.test${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) }),
      env,
    );
    return { status: res.status, body: await res.json() };
  };
}

function setup() {
  const env = { DB: fakeD1() };
  return { env, call: client(env) };
}

test('register, duplicate names, login and lockout', async () => {
  const { env, call } = setup();
  const r = await call('POST', '/v1/register', { username: ' Shinji_01 ', key: KEY });
  assert.equal(r.status, 200);
  assert.equal(r.body.username, 'shinji_01');
  assert.match(r.body.token, /^[0-9a-f]{64}$/);

  // Stored: neither the key nor the token in plain form.
  const row = env.DB.raw.prepare('SELECT * FROM users').get();
  assert.notEqual(row.key_hash, KEY);
  assert.equal(env.DB.raw.prepare('SELECT COUNT(*) AS n FROM sessions WHERE token_hash = ?').get(r.body.token).n, 0);

  assert.equal((await call('POST', '/v1/register', { username: 'SHINJI_01', key: OTHER_KEY })).status, 409);
  assert.equal((await call('POST', '/v1/register', { username: 'ab', key: KEY })).status, 400);
  assert.equal((await call('POST', '/v1/register', { username: 'ok name', key: KEY })).status, 400);
  assert.equal((await call('POST', '/v1/register', { username: 'rei', key: 'short' })).status, 400);

  assert.equal((await call('POST', '/v1/login', { username: 'shinji_01', key: OTHER_KEY })).status, 401);
  assert.equal((await call('POST', '/v1/login', { username: 'nobody', key: KEY })).status, 401);
  const ok = await call('POST', '/v1/login', { username: 'Shinji_01', key: KEY });
  assert.equal(ok.status, 200);
  assert.notEqual(ok.body.token, r.body.token);

  for (let i = 0; i < 10; i++) await call('POST', '/v1/login', { username: 'shinji_01', key: OTHER_KEY });
  assert.equal((await call('POST', '/v1/login', { username: 'shinji_01', key: KEY })).status, 429);
});

test('sync between two devices: newest progress wins, shows travel along', async () => {
  const { call } = setup();
  const { body: a } = await call('POST', '/v1/register', { username: 'asuka', key: KEY });
  const { body: b } = await call('POST', '/v1/login', { username: 'asuka', key: KEY });

  const first = await call(
    'POST',
    '/v1/sync',
    {
      since: 0,
      history: [
        { slug: 'eva', episode: '1', positionMs: 1440000, durationMs: 1440000, updatedAt: 1000 },
        { slug: 'eva', episode: '2', positionMs: 60000, durationMs: 1440000, updatedAt: 2000 },
        { slug: 'bad' }, // ignored
      ],
      shows: [{ slug: 'eva', title: 'Neon Genesis Evangelion', poster: 'https://p/eva.jpg', malId: '30' }],
    },
    a.token,
  );
  assert.equal(first.status, 200);
  assert.equal(first.body.history.length, 2);

  // Phone pulls everything, then watches further.
  const pulled = await call('POST', '/v1/sync', { since: 0 }, b.token);
  assert.deepEqual(pulled.body.shows, [
    { slug: 'eva', title: 'Neon Genesis Evangelion', poster: 'https://p/eva.jpg', url: null, siteId: null, malId: '30' },
  ]);
  const since = pulled.body.now;
  await call('POST', '/v1/sync', { since, history: [{ slug: 'eva', episode: '2', positionMs: 900000, durationMs: 1440000, updatedAt: 5000 }] }, b.token);

  // An older write from the PC does not overwrite it.
  await call('POST', '/v1/sync', { since, history: [{ slug: 'eva', episode: '2', positionMs: 1, durationMs: 1440000, updatedAt: 3000 }] }, a.token);
  const all = await call('POST', '/v1/sync', { since: 0 }, a.token);
  assert.equal(all.body.history.find((h) => h.episode === '2').positionMs, 900000);

  // Incremental pull only returns what changed since.
  const later = await call('POST', '/v1/sync', { since: all.body.now + 1 }, a.token);
  assert.deepEqual(later.body.history, []);
});

test('clearing history reaches other devices and stale pushes do not bring it back', async () => {
  const { call } = setup();
  const { body: u } = await call('POST', '/v1/register', { username: 'misato', key: KEY });
  await call(
    'POST',
    '/v1/sync',
    {
      history: [
        { slug: 'eva', episode: '1', positionMs: 5000, durationMs: 9000, updatedAt: 100 },
        { slug: 'frieren', episode: '3', positionMs: 5000, durationMs: 9000, updatedAt: 100 },
      ],
    },
    u.token,
  );
  const r = await call('POST', '/v1/sync', { deletions: [{ slug: 'eva', at: 200 }] }, u.token);
  assert.deepEqual(r.body.deletions, [{ slug: 'eva', at: 200 }]);
  assert.deepEqual(r.body.history.map((h) => h.slug), ['frieren']);

  // Another device that has not heard about it pushes its old copy: ignored.
  await call('POST', '/v1/sync', { history: [{ slug: 'eva', episode: '1', positionMs: 7000, durationMs: 9000, updatedAt: 150 }] }, u.token);
  // Watching again after the clear is kept.
  await call('POST', '/v1/sync', { history: [{ slug: 'eva', episode: '2', positionMs: 7000, durationMs: 9000, updatedAt: 300 }] }, u.token);
  const after = await call('POST', '/v1/sync', { since: 0 }, u.token);
  assert.deepEqual(after.body.history.map((h) => `${h.slug}/${h.episode}`).sort(), ['eva/2', 'frieren/3']);

  // Clear everything.
  const cleared = await call('POST', '/v1/sync', { deletions: [{ slug: '*', at: 400 }] }, u.token);
  assert.deepEqual(cleared.body.history, []);
});

test('accounts are separate; sign out and delete account', async () => {
  const { env, call } = setup();
  const { body: a } = await call('POST', '/v1/register', { username: 'kaji', key: KEY });
  const { body: b } = await call('POST', '/v1/register', { username: 'gendo', key: OTHER_KEY });
  await call('POST', '/v1/sync', { history: [{ slug: 'eva', episode: '1', positionMs: 1, durationMs: 2, updatedAt: 3 }] }, a.token);
  assert.deepEqual((await call('POST', '/v1/sync', { since: 0 }, b.token)).body.history, []);

  assert.equal((await call('POST', '/v1/sync', {})).status, 401);
  assert.equal((await call('POST', '/v1/sync', {}, 'f'.repeat(64))).status, 401);

  await call('POST', '/v1/logout', undefined, b.token);
  assert.equal((await call('POST', '/v1/sync', {}, b.token)).status, 401);

  assert.equal((await call('DELETE', '/v1/account', undefined, a.token)).status, 200);
  assert.equal((await call('POST', '/v1/sync', {}, a.token)).status, 401);
  assert.equal(env.DB.raw.prepare('SELECT COUNT(*) AS n FROM history').get().n, 0);
  assert.equal((await call('POST', '/v1/login', { username: 'kaji', key: KEY })).status, 401);
});

test('bad input', async () => {
  const { call } = setup();
  assert.equal((await call('GET', '/v1/health')).body.ok, true);
  assert.equal((await call('GET', '/nope')).status, 404);
  const { body: u } = await call('POST', '/v1/register', { username: 'pen-pen', key: KEY });
  assert.equal((await call('POST', '/v1/sync', { history: 'x' }, u.token)).status, 400);
  assert.equal((await call('POST', '/v1/sync', { history: new Array(5001).fill({}) }, u.token)).status, 400);
});
