# lex-trail — Attestation chain
#
# An attestation is a content-addressed record that references an event
# by id, recording external validation, provenance, or signatures.
# Multiple attestations may target the same event.
#
# The `attestations` table is created by log.init_schema so that both
# modules share the same database handle.
#
# Effects
# -------
#   add    — [sql, time]  (captures ts_ms)
#   chain  — [sql]

import "./event" as ev

import "./log" as l

import "std.sql" as sql

import "std.time" as time

import "std.str" as str

import "std.list" as list

type Attestation = { id :: Str, event_id :: Str, kind :: Str, payload_json :: Str, ts_ms :: Int }

# Append an attestation for event_id to the log.
# The attestation id is itself a SHA-256 hash of its content.
fn add(log :: l.Log, event_id :: Str, kind :: Str, payload_json :: Str) -> [sql, time] Result[Attestation, Str] {
  let ts_ms := time.now_ms()
  let id := ev.compute_id(str.concat("attest:", kind), Some(event_id), payload_json, ts_ms)
  let att := { id: id, event_id: event_id, kind: kind, payload_json: payload_json, ts_ms: ts_ms }
  match l.xexec(log.db, "INSERT INTO attestations(id, event_id, kind, payload_json, ts_ms) VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO NOTHING", [PStr(att.id), PStr(att.event_id), PStr(att.kind), PStr(att.payload_json), PInt(att.ts_ms)]) {
    Err(e) => Err(e.message),
    Ok(_) => Ok(att),
  }
}

# Return all attestations for event_id, oldest-first.
fn chain(log :: l.Log, event_id :: Str) -> [sql] Result[List[Attestation], Str] {
  match l.xquery(log.db, "SELECT id, event_id, kind, payload_json, ts_ms FROM attestations WHERE event_id = ? ORDER BY ts_ms ASC", [PStr(event_id)]) {
    Err(e) => Err(e.message),
    Ok(rows) => Ok(list.map(rows, decode_attest_row)),
  }
}

# ---- Row decoder -------------------------------------------------
fn decode_attest_row[R](row :: R) -> Attestation {
  { id: opt_str(sql.get_str(row, "id")), event_id: opt_str(sql.get_str(row, "event_id")), kind: opt_str(sql.get_str(row, "kind")), payload_json: opt_str(sql.get_str(row, "payload_json")), ts_ms: opt_int(sql.get_int(row, "ts_ms")) }
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
    opt_int(Some(7)) => 7,
    opt_int(None) => 0
  }
{
  match o {
    Some(n) => n,
    None => 0,
  }
}

