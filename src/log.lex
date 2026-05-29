# lex-trail — Append-only event log
#
# A Log wraps a `Db` handle with the trail schema applied on open.
# Both backends are SQLite; the difference is the connection path:
#
#   open_memory()  ->  ":memory:"  (ephemeral, in-process)
#   open(path)     ->  file path   (persistent)
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
#   range / head        —  [sql]
#   close               —  [sql]

import "./event" as ev

import "std.sql" as sql

import "std.time" as time

import "std.str" as str

import "std.int" as int

import "std.list" as list

type Log = { db :: Db }

# Open an ephemeral in-memory log. The database is destroyed when the
# handle goes out of scope.
fn open_memory() -> [sql, fs_write] Result[Log, Str] {
  match sql.open(":memory:") {
    Err(e) => Err(e.message),
    Ok(db) => match init_schema(db) {
      Err(msg) => Err(msg),
      Ok(_) => Ok({ db: db }),
    },
  }
}

# Open (or create) a persistent SQLite log at the given file path.
fn open(path :: Str) -> [sql, fs_write] Result[Log, Str] {
  match sql.open(path) {
    Err(e) => Err(e.message),
    Ok(db) => match init_schema(db) {
      Err(msg) => Err(msg),
      Ok(_) => Ok({ db: db }),
    },
  }
}

# Release the database handle.
fn close(log :: Log) -> [sql] Unit {
  sql.close(log.db)
}

# Append a new event to the log. ts_ms is captured from the wall clock.
# Returns the appended Event (useful for chaining parent ids).
# Uses INSERT OR IGNORE: if the same content hash already exists the
# call is a no-op and returns the original event value.
fn append(log :: Log, kind :: Str, parent :: Option[Str], payload_json :: Str) -> [sql, time] Result[ev.Event, Str] {
  let ts_ms := time.now_ms()
  let evt := ev.make(kind, parent, payload_json, ts_ms)
  let exec_result := match evt.parent {
    Some(p) => sql.exec(log.db, "INSERT OR IGNORE INTO events(id, kind, parent, payload_json, ts_ms) VALUES (?, ?, ?, ?, ?)", [PStr(evt.id), PStr(evt.kind), PStr(p), PStr(evt.payload_json), PInt(evt.ts_ms)]),
    None => sql.exec(log.db, "INSERT OR IGNORE INTO events(id, kind, parent, payload_json, ts_ms) VALUES (?, ?, NULL, ?, ?)", [PStr(evt.id), PStr(evt.kind), PStr(evt.payload_json), PInt(evt.ts_ms)]),
  }
  match exec_result {
    Err(e) => Err(e.message),
    Ok(_) => Ok(evt),
  }
}

# Return all events with ts_ms in [from_ms, to_ms], ordered oldest-first.
fn range(log :: Log, from_ms :: Int, to_ms :: Int) -> [sql] Result[List[ev.Event], Str] {
  match sql.query(log.db, "SELECT id, kind, parent, payload_json, ts_ms FROM events WHERE ts_ms >= ? AND ts_ms <= ? ORDER BY ts_ms ASC", [PInt(from_ms), PInt(to_ms)]) {
    Err(e) => Err(e.message),
    Ok(rows) => Ok(list.map(rows, decode_event_row)),
  }
}

# Return the most recently appended event, or None if the log is empty.
fn head(log :: Log) -> [sql] Option[ev.Event] {
  match sql.query(log.db, "SELECT id, kind, parent, payload_json, ts_ms FROM events ORDER BY ts_ms DESC LIMIT 1", []) {
    Err(_) => None,
    Ok(rows) => match list.head(rows) {
      None => None,
      Some(r) => Some(decode_event_row(r)),
    },
  }
}

# ---- Internal schema bootstrap -----------------------------------
fn init_schema(db :: Db) -> [sql] Result[Unit, Str] {
  exec_stmts(db, ["CREATE TABLE IF NOT EXISTS events (id TEXT NOT NULL PRIMARY KEY, kind TEXT NOT NULL, parent TEXT, payload_json TEXT NOT NULL DEFAULT '{}', ts_ms INTEGER NOT NULL)", "CREATE INDEX IF NOT EXISTS idx_events_kind ON events(kind)", "CREATE INDEX IF NOT EXISTS idx_events_ts   ON events(ts_ms)", "CREATE TABLE IF NOT EXISTS attestations (id TEXT NOT NULL PRIMARY KEY, event_id TEXT NOT NULL, kind TEXT NOT NULL, payload_json TEXT NOT NULL DEFAULT '{}', ts_ms INTEGER NOT NULL)", "CREATE INDEX IF NOT EXISTS idx_attest_event ON attestations(event_id)"])
}

fn exec_stmts(db :: Db, stmts :: List[Str]) -> [sql] Result[Unit, Str] {
  match list.head(stmts) {
    None => Ok(()),
    Some(stmt) => match sql.exec(db, stmt, []) {
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

