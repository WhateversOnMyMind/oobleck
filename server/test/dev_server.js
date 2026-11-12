// Local stand-in for the deployed Worker: the same code over Node's built-in
// SQLite, for the Dart end-to-end test and for trying the app without a
// Cloudflare account.
//
//   node server/test/dev_server.js [port] [db-file]
//
// Prints "listening <port>" once ready (port 0 picks a free one).
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';
import worker from '../src/index.js';

const port = Number(process.argv[2] ?? 8787);
const db = new DatabaseSync(process.argv[3] ?? ':memory:');
db.exec(readFileSync(new URL('../schema.sql', import.meta.url), 'utf8'));

class Stmt {
  constructor(sql, args = []) {
    this.sql = sql;
    this.args = args;
  }
  bind(...args) {
    return new Stmt(this.sql, args);
  }
  async first() {
    return db.prepare(this.sql).get(...this.args) ?? null;
  }
  async all() {
    return { results: db.prepare(this.sql).all(...this.args) };
  }
  async run() {
    return { meta: { changes: Number(db.prepare(this.sql).run(...this.args).changes) } };
  }
}

const env = {
  DB: {
    prepare: (sql) => new Stmt(sql),
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
  },
};

const server = createServer(async (req, res) => {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  const body = chunks.length ? Buffer.concat(chunks) : undefined;
  const r = await worker.fetch(
    new Request(`http://localhost${req.url}`, { method: req.method, headers: req.headers, body: req.method === 'GET' ? undefined : body }),
    env,
  );
  res.writeHead(r.status, Object.fromEntries(r.headers));
  res.end(Buffer.from(await r.arrayBuffer()));
});
server.listen(port, '127.0.0.1', () => console.log(`listening ${server.address().port}`));
