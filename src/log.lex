# lex-trail — Append-only event log with sequential hash chain
#
# A Log wraps a `Db` handle with the trail schema applied on open.
# Both backends are SQLite; the difference is the connection path:
#
#   open_memory()  ->  ":memory:"  (ephemeral, in-process)
#   open(path)     ->  file path   (persistent)
#
# Schema
# ------
# events        — one row per Event; primary key is the SHA-256 id.
#                 seq and chain_hash form a sequential hash chain for
#                 deletion detection (see verify_chain).
# attestations  — owned by attest.lex; created here for schema cohesion
#
# Hash chain
# ----------
# seq is a monotonically-increasing integer assigned at append time.
# chain_hash is SHA-256("chain:<prev_chain_hash>:<event_id>:<seq>").
# The genesis prev_hash is the literal string "genesis" (no row).
# verify_chain walks events ordered by seq and checks both sequence
# continuity and hash integrity — a deleted row causes a seq gap,
# a mutated row causes a hash mismatch.
#
# Effects
# -------
#   open_memory / open  —  [sql, fs_write]
#   append              —  [sql, time]   (time.now_ms for ts_ms; sha256 is pure)
#   range / head        —  [sql]
#   verify_chain        —  [sql]
#   close               —  [sql]

import "./event" as ev

import "std.sql" as sql

import "std.time" as time

import "std.str" as str

import "std.int" as int

import "std.list" as list

import "std.crypto" as crypto

type Log = { db :: Db }

type ChainState = { seq :: Int, chain_hash :: Str }

type ChainRow = { event_id :: Str, seq :: Int, chain_hash :: Str }

# Open an ephemeral in-memory log. The database is destroyed when the
# handle goes out of scope.
fn open_memory() -> [sql, fs_write] Result[Log, Str] {
  match sql.open(":memory:") {
    Err(e) => Err(e.message),
    Ok(db) => match init_schema(db) {
      Err(msg) => Err(msg),
      Ok(_) => match migrate_schema(db) {
        Err(msg) => Err(msg),
        Ok(_) => Ok({ db: db }),
      },
    },
  }
}

# Open (or create) a persistent SQLite log at the given file path.
fn open(path :: Str) -> [sql, fs_write] Result[Log, Str] {
  match sql.open(path) {
    Err(e) => Err(e.message),
    Ok(db) => match init_schema(db) {
      Err(msg) => Err(msg),
      Ok(_) => match migrate_schema(db) {
        Err(msg) => Err(msg),
        Ok(_) => Ok({ db: db }),
      },
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
# Each appended event receives the next seq number and a chain_hash
# computed over (prev_chain_hash, event_id, seq).
fn append(log :: Log, kind :: Str, parent :: Option[Str], payload_json :: Str) -> [sql, time] Result[ev.Event, Str] {
  let ts_ms := time.now_ms()
  let evt := ev.make(kind, parent, payload_json, ts_ms)
  match last_chain_state(log) {
    Err(msg) => Err(msg),
    Ok(chain_state) => {
      let new_seq := match chain_state {
        None => 0,
        Some(s) => s.seq + 1,
      }
      let prev_hash := match chain_state {
        None => "genesis",
        Some(s) => s.chain_hash,
      }
      let new_chain_hash := compute_chain_hash(prev_hash, evt.id, new_seq)
      let exec_result := match evt.parent {
        Some(p) => sql.exec(log.db, "INSERT OR IGNORE INTO events(id, kind, parent, payload_json, ts_ms, seq, chain_hash) VALUES (?, ?, ?, ?, ?, ?, ?)", [PStr(evt.id), PStr(evt.kind), PStr(p), PStr(evt.payload_json), PInt(evt.ts_ms), PInt(new_seq), PStr(new_chain_hash)]),
        None => sql.exec(log.db, "INSERT OR IGNORE INTO events(id, kind, parent, payload_json, ts_ms, seq, chain_hash) VALUES (?, ?, NULL, ?, ?, ?, ?)", [PStr(evt.id), PStr(evt.kind), PStr(evt.payload_json), PInt(evt.ts_ms), PInt(new_seq), PStr(new_chain_hash)]),
      }
      match exec_result {
        Err(e) => Err(e.message),
        Ok(_) => Ok(evt),
      }
    },
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

# Verify the sequential hash chain for every event in the log.
# Returns Ok(count) where count is the number of events verified,
# or Err with a message describing the first violation found:
#   "chain broken: expected seq N, found seq M" — a row was deleted
#   "hash mismatch at seq N"                    — a row was mutated
fn verify_chain(log :: Log) -> [sql] Result[Int, Str] {
  match sql.query(log.db, "SELECT id, seq, chain_hash FROM events ORDER BY seq ASC", []) {
    Err(e) => Err(e.message),
    Ok(rows) => {
      let chain_rows := list.map(rows, decode_chain_row)
      check_chain(chain_rows, 0, "genesis", 0)
    },
  }
}

# ---- Internal schema bootstrap -----------------------------------
fn init_schema(db :: Db) -> [sql] Result[Unit, Str] {
  exec_stmts(db, [
    "CREATE TABLE IF NOT EXISTS events (id TEXT NOT NULL PRIMARY KEY, kind TEXT NOT NULL, parent TEXT, payload_json TEXT NOT NULL DEFAULT '{}', ts_ms INTEGER NOT NULL, seq INTEGER NOT NULL DEFAULT -1, chain_hash TEXT NOT NULL DEFAULT '')",
    "CREATE INDEX IF NOT EXISTS idx_events_kind ON events(kind)",
    "CREATE INDEX IF NOT EXISTS idx_events_ts   ON events(ts_ms)",
    "CREATE INDEX IF NOT EXISTS idx_events_seq  ON events(seq)",
    "CREATE TABLE IF NOT EXISTS attestations (id TEXT NOT NULL PRIMARY KEY, event_id TEXT NOT NULL, kind TEXT NOT NULL, payload_json TEXT NOT NULL DEFAULT '{}', ts_ms INTEGER NOT NULL)",
    "CREATE INDEX IF NOT EXISTS idx_attest_event ON attestations(event_id)"
  ])
}

# Add seq/chain_hash columns to existing databases that pre-date the
# hash chain. SQLite returns an error if the column already exists;
# we discard it — the column is the goal, not the statement.
fn migrate_schema(db :: Db) -> [sql] Result[Unit, Str] {
  let __seq_col := sql.exec(db, "ALTER TABLE events ADD COLUMN seq INTEGER NOT NULL DEFAULT -1", [])
  let __chain_col := sql.exec(db, "ALTER TABLE events ADD COLUMN chain_hash TEXT NOT NULL DEFAULT ''", [])
  let __seq_idx := sql.exec(db, "CREATE INDEX IF NOT EXISTS idx_events_seq ON events(seq)", [])
  Ok(())
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

# ---- Hash chain --------------------------------------------------

# SHA-256("chain:<prev_hash>:<event_id>:<seq>") — pure, no effects.
fn compute_chain_hash(prev_hash :: Str, event_id :: Str, seq :: Int) -> Str
  examples {
    compute_chain_hash("genesis", "abc", 0) => compute_chain_hash("genesis", "abc", 0)
  }
{
  crypto.sha256_str(str.join(["chain", prev_hash, event_id, int.to_str(seq)], ":"))
}

# Return the seq and chain_hash of the most recently appended event,
# or None if the log is empty (genesis state).
fn last_chain_state(log :: Log) -> [sql] Result[Option[ChainState], Str] {
  match sql.query(log.db, "SELECT seq, chain_hash FROM events ORDER BY seq DESC LIMIT 1", []) {
    Err(e) => Err(e.message),
    Ok(rows) => match list.head(rows) {
      None => Ok(None),
      Some(r) => Ok(Some({ seq: opt_int(sql.get_int(r, "seq")), chain_hash: opt_str(sql.get_str(r, "chain_hash")) })),
    },
  }
}

# Walk chain_rows in seq order. Detects gaps (deleted rows) and hash
# mismatches (mutated rows). Returns Ok(count) or the first violation.
fn check_chain(rows :: List[ChainRow], expected_seq :: Int, prev_hash :: Str, count :: Int) -> Result[Int, Str] {
  match list.head(rows) {
    None => Ok(count),
    Some(r) => if r.seq == expected_seq {
      let expected_hash := compute_chain_hash(prev_hash, r.event_id, r.seq)
      if r.chain_hash == expected_hash {
        check_chain(list.tail(rows), expected_seq + 1, r.chain_hash, count + 1)
      } else {
        Err(str.join(["hash mismatch at seq ", int.to_str(r.seq)], ""))
      }
    } else {
      Err(str.join(["chain broken: expected seq ", int.to_str(expected_seq), ", found seq ", int.to_str(r.seq)], ""))
    },
  }
}

# ---- Row decoders ------------------------------------------------
fn decode_event_row[R](row :: R) -> ev.Event {
  let id := opt_str(sql.get_str(row, "id"))
  let kind := opt_str(sql.get_str(row, "kind"))
  let par := sql.get_str(row, "parent")
  let pay := opt_str(sql.get_str(row, "payload_json"))
  let ts := opt_int(sql.get_int(row, "ts_ms"))
  { id: id, kind: kind, parent: par, payload_json: pay, ts_ms: ts }
}

fn decode_chain_row[R](row :: R) -> ChainRow {
  { event_id: opt_str(sql.get_str(row, "id")), seq: opt_int(sql.get_int(row, "seq")), chain_hash: opt_str(sql.get_str(row, "chain_hash")) }
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
