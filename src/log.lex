# lex-trail — Append-only event log
#
# A Log wraps a lex-orm connection with the trail schema applied on open.
# The trail persists on SQLite or PostgreSQL — a deployment co-locating the
# trail with the records it describes (the finance stack's ask, #8) gets
# atomic writes and one backup:
#
#   open_memory()  ->  ":memory:"          (ephemeral, in-process)
#   open(path)     ->  file path           (persistent SQLite)
#   open_url(url)  ->  postgres://… | path (dialect from the URL scheme)
#
# The DDL is portable as-is; only placeholder numbering differs, and every
# parameterized statement goes through `q.for_dialect` for that.
#
# Schema
# ------
# events        — one row per Event; primary key is the SHA-256 id
# attestations  — owned by attest.lex; created here for schema cohesion
#
# Effects
# -------
#   open_memory / open  —  [sql, fs_write]
#   append              —  [sql, time]   (time.now_ms for ts_ms)
#   append_at           —  [sql]         (caller-supplied ts_ms; deterministic)
#   range / head        —  [sql]
#   close               —  [sql]

import "./event" as ev

import "std.sql" as sql

import "lex-orm/connection" as conn

import "lex-orm/query" as q

import "lex-orm/error" as dbe

import "std.time" as time

import "std.str" as str

import "std.int" as int

import "std.list" as list

type Log = { db :: conn.ConnDb }

# Open an ephemeral in-memory log. The database is destroyed when the
# handle goes out of scope.
fn open_memory() -> [sql, fs_write] Result[Log, Str] {
  match conn.connect_sqlite(":memory:") {
    Err(e) => Err(dbe.message(e)),
    Ok(db) => match init_schema(db) {
      Err(msg) => Err(msg),
      Ok(_) => Ok({ db: db }),
    },
  }
}

# Open (or create) a persistent SQLite log at the given file path.
fn open(path :: Str) -> [sql, fs_write] Result[Log, Str] {
  match conn.connect_sqlite(path) {
    Err(e) => Err(dbe.message(e)),
    Ok(db) => match init_schema(db) {
      Err(msg) => Err(msg),
      Ok(_) => Ok({ db: db }),
    },
  }
}

# Open by URL: a `postgres://…` DSN persists the trail in PostgreSQL, anything
# else is treated as a SQLite path. Same schema, same guarantees.
fn open_url(url :: Str) -> [sql, fs_write] Result[Log, Str] {
  match conn.open(url) {
    Err(e) => Err(dbe.message(e)),
    Ok(db) => match init_schema(db) {
      Err(msg) => Err(msg),
      Ok(_) => Ok({ db: db }),
    },
  }
}

# Wrap a RAW std.sql handle whose dialect the caller knows (lex-soft and other
# hosts that opened the database themselves and pass `Db` around). Prefer
# from_conn when you already hold a ConnDb — this exists so a raw-handle host
# doesn't have to refactor its whole surface to gain the trail schema.
#
# The dialect argument is not decoration: pass DbSqlite for a `?` database and
# DbPostgres for a `$n` one, or the parameterized statements will not bind.
fn attach(db :: Db, dialect :: conn.Dialect) -> [sql] Result[Log, Str] {
  from_conn({ dialect: dialect, handle: db })
}

# Wrap an EXISTING lex-orm connection: the point of #8 — the trail shares the
# caller's transaction-capable handle instead of opening its own database.
fn from_conn(db :: conn.ConnDb) -> [sql] Result[Log, Str] {
  match init_schema(db) {
    Err(msg) => Err(msg),
    Ok(_) => Ok({ db: db }),
  }
}

# Every parameterized statement crosses the dialect boundary here: SQLite
# takes `?`, PostgreSQL wants `$1..$n`, and q.for_dialect renumbers. Callers
# below write plain `?` SQL and stay dialect-blind.
fn xexec(db :: conn.ConnDb, stmt :: Str, params :: List[SqlParam]) -> [sql] Result[Int, SqlError] {
  let sq := q.for_dialect({ sql: stmt, params: params }, db.dialect)
  sql.exec(db.handle, sq.sql, sq.params)
}

fn xquery(db :: conn.ConnDb, stmt :: Str, params :: List[SqlParam]) -> [sql] Result[List[sql.Row], SqlError] {
  let sq := q.for_dialect({ sql: stmt, params: params }, db.dialect)
  sql.query(db.handle, sq.sql, sq.params)
}

# Release the database handle.
fn close(log :: Log) -> [sql] Unit {
  conn.close(log.db)
}

# Append a new event to the log. ts_ms is captured from the wall clock.
# Returns the appended Event (useful for chaining parent ids).
# Uses ON CONFLICT(id) DO NOTHING: if the same content hash already exists the
# call is a no-op and returns the original event value.
fn append(log :: Log, kind :: Str, parent :: Option[Str], payload_json :: Str) -> [sql, time] Result[ev.Event, Str] {
  append_at(log, kind, parent, payload_json, time.now_ms())
}

# Append a new event with a caller-supplied timestamp. This is the
# deterministic variant: given the same (kind, parent, payload, ts_ms)
# the event id — a SHA-256 content hash — is identical across runs,
# which is what makes a trail replay-verifiable. Simulations should
# pass sim-time here (e.g. episode_start + step * tick); `append` is
# the wall-clock convenience wrapper.
# Note the effect row: [sql] only — no clock access, by construction.
fn append_at(log :: Log, kind :: Str, parent :: Option[Str], payload_json :: Str, ts_ms :: Int) -> [sql] Result[ev.Event, Str] {
  append_actor_at(log, kind, "", parent, payload_json, ts_ms)
}

# Like `append`, but records the event's acting party in the indexed `actor`
# column so audit views can scope by agent without a payload LIKE scan. The
# actor is a denormalized copy of a field the caller already puts in
# payload_json; it is NOT part of the content-addressed id (which stays a hash of
# kind/parent/payload/ts), so two events differing only in actor already differ
# in payload and so in id — no id collision, and the ON CONFLICT stays a true
# same-event no-op.
fn append_actor(log :: Log, kind :: Str, actor :: Str, parent :: Option[Str], payload_json :: Str) -> [sql, time] Result[ev.Event, Str] {
  append_actor_at(log, kind, actor, parent, payload_json, time.now_ms())
}

# Deterministic variant of append_actor (caller-supplied ts_ms).
fn append_actor_at(log :: Log, kind :: Str, actor :: Str, parent :: Option[Str], payload_json :: Str, ts_ms :: Int) -> [sql] Result[ev.Event, Str] {
  let evt := ev.make(kind, parent, payload_json, ts_ms)
  let exec_result := match evt.parent {
    Some(p) => xexec(log.db, "INSERT INTO events(id, kind, parent, payload_json, ts_ms, actor) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO NOTHING", [PStr(evt.id), PStr(evt.kind), PStr(p), PStr(evt.payload_json), PInt(evt.ts_ms), PStr(actor)]),
    None => xexec(log.db, "INSERT INTO events(id, kind, parent, payload_json, ts_ms, actor) VALUES (?, ?, NULL, ?, ?, ?) ON CONFLICT(id) DO NOTHING", [PStr(evt.id), PStr(evt.kind), PStr(evt.payload_json), PInt(evt.ts_ms), PStr(actor)]),
  }
  match exec_result {
    Err(e) => Err(e.message),
    Ok(_) => Ok(evt),
  }
}

# Return all events with ts_ms in [from_ms, to_ms], ordered oldest-first.
fn range(log :: Log, from_ms :: Int, to_ms :: Int) -> [sql] Result[List[ev.Event], Str] {
  match xquery(log.db, "SELECT id, kind, parent, payload_json, ts_ms FROM events WHERE ts_ms >= ? AND ts_ms <= ? ORDER BY ts_ms ASC", [PInt(from_ms), PInt(to_ms)]) {
    Err(e) => Err(e.message),
    Ok(rows) => Ok(list.map(rows, decode_event_row)),
  }
}

# Return every event recorded under `actor`, oldest-first. Uses the indexed
# actor column, so scoping an audit view to one party's events is an index range
# rather than a payload_json LIKE scan. Events appended via plain `append` (actor
# left '') are returned only by by_actor("").
fn by_actor(log :: Log, actor :: Str) -> [sql] Result[List[ev.Event], Str] {
  match xquery(log.db, "SELECT id, kind, parent, payload_json, ts_ms FROM events WHERE actor = ? ORDER BY ts_ms ASC", [PStr(actor)]) {
    Err(e) => Err(e.message),
    Ok(rows) => Ok(list.map(rows, decode_event_row)),
  }
}

# Return the most recently appended event, or None if the log is empty.
fn head(log :: Log) -> [sql] Option[ev.Event] {
  match xquery(log.db, "SELECT id, kind, parent, payload_json, ts_ms FROM events ORDER BY ts_ms DESC LIMIT 1", []) {
    Err(_) => None,
    Ok(rows) => match list.head(rows) {
      None => None,
      Some(r) => Some(decode_event_row(r)),
    },
  }
}

# ---- Internal schema bootstrap -----------------------------------
# The `actor` column is an indexed, denormalized copy of the event's acting
# party — supplied by the caller via `append_actor` (see below). Consumers that
# scope an audit view to one tenant's agents were left scanning payload_json with
# LIKE; an indexed column turns that filter into an index range. Fresh databases
# get it from CREATE TABLE; databases predating this version get it from the
# tolerated ALTER, then the index. Callers using plain `append` leave it ''.
fn init_schema(db :: conn.ConnDb) -> [sql] Result[Unit, Str] {
  match exec_stmts(db, ["CREATE TABLE IF NOT EXISTS events (id TEXT NOT NULL PRIMARY KEY, kind TEXT NOT NULL, parent TEXT, payload_json TEXT NOT NULL DEFAULT '{}', ts_ms BIGINT NOT NULL, actor TEXT NOT NULL DEFAULT '')", "CREATE INDEX IF NOT EXISTS idx_events_kind ON events(kind)", "CREATE INDEX IF NOT EXISTS idx_events_ts   ON events(ts_ms)", "CREATE TABLE IF NOT EXISTS attestations (id TEXT NOT NULL PRIMARY KEY, event_id TEXT NOT NULL, kind TEXT NOT NULL, payload_json TEXT NOT NULL DEFAULT '{}', ts_ms BIGINT NOT NULL)", "CREATE INDEX IF NOT EXISTS idx_attest_event ON attestations(event_id)"]) {
    Err(e) => Err(e),
    Ok(_) => match add_actor_column(db) {
      Err(e) => Err(e),
      Ok(_) => exec_stmts(db, ["CREATE INDEX IF NOT EXISTS idx_events_actor ON events(actor)"]),
    },
  }
}

# Add `actor` to an events table created before this version. Neither SQLite nor
# every Postgres supports `ADD COLUMN IF NOT EXISTS` portably, so we run the ALTER
# and treat a duplicate-column error (the fresh-database case, where CREATE TABLE
# already added it) as success. Any other failure propagates.
fn add_actor_column(db :: conn.ConnDb) -> [sql] Result[Unit, Str] {
  match sql.exec(db.handle, "ALTER TABLE events ADD COLUMN actor TEXT NOT NULL DEFAULT ''", []) {
    Ok(_) => Ok(()),
    Err(e) => if is_duplicate_column(e.message) { Ok(()) } else { Err(e.message) },
  }
}

# A duplicate-column error means the column is already there — SQLite says
# "duplicate column name", Postgres says "already exists".
fn is_duplicate_column(msg :: Str) -> Bool {
  str.contains(msg, "duplicate column") or str.contains(msg, "already exists")
}

fn exec_stmts(db :: conn.ConnDb, stmts :: List[Str]) -> [sql] Result[Unit, Str] {
  match list.head(stmts) {
    None => Ok(()),
    Some(stmt) => match sql.exec(db.handle, stmt, []) {
      Err(e) => Err(e.message),
      Ok(_) => exec_stmts(db, list.tail(stmts)),
    },
  }
}

# ---- Row decoder -------------------------------------------------
fn decode_event_row[R](row :: R) -> ev.Event {
  let id := opt_str(sql.get_str(row, "id"))
  let kind := opt_str(sql.get_str(row, "kind"))
  let par := sql.get_str(row, "parent")
  let pay := opt_str(sql.get_str(row, "payload_json"))
  let ts := opt_int(sql.get_int(row, "ts_ms"))
  { id: id, kind: kind, parent: par, payload_json: pay, ts_ms: ts }
}

fn opt_str(o :: Option[Str]) -> Str
  examples {
    opt_str(Some("x")) => "x",
    opt_str(None) => ""
  }
{
  match o {
    Some(s) => s,
    None => "",
  }
}

fn opt_int(o :: Option[Int]) -> Int
  examples {
    opt_int(Some(42)) => 42,
    opt_int(None) => 0
  }
{
  match o {
    Some(n) => n,
    None => 0,
  }
}

