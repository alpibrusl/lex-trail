# lex-trail — A2A task replay
#
# Given a task_id, reconstruct the full event history: messages, state
# changes, capability invocations, spec evaluations, llm steps.
#
# replay.task uses a SQL LIKE search on payload_json for the task_id
# string. Payloads must include a top-level `"task_id"` JSON key for
# this to work — the platform standard payloads in kinds.lex all do.
#
# replay.walk_chain walks the parent pointer chain from any event back
# to the chain root, returning events in root-first order.
#
# Effects: [sql] (read-only).

import "./event" as ev

import "./log" as l

import "std.sql" as sql

import "std.str" as str

import "std.list" as list

# Return all events whose payload_json contains task_id, oldest-first.
fn task(log :: l.Log, task_id :: Str) -> [sql] Result[List[ev.Event], Str] {
  let pattern := str.concat("%\"task_id\":\"", str.concat(task_id, "\"%"))
  match l.xquery(log.db, "SELECT id, kind, parent, payload_json, ts_ms FROM events WHERE payload_json LIKE ? ORDER BY ts_ms ASC", [PStr(pattern)]) {
    Err(e) => Err(e.message),
    Ok(rows) => Ok(list.map(rows, decode_event_row)),
  }
}

# Walk the parent chain starting from event_id, root-first.
fn walk_chain(log :: l.Log, event_id :: Str) -> [sql] List[ev.Event] {
  walk_up(log, event_id, [])
}

fn walk_up(log :: l.Log, event_id :: Str, acc :: List[ev.Event]) -> [sql] List[ev.Event] {
  match l.xquery(log.db, "SELECT id, kind, parent, payload_json, ts_ms FROM events WHERE id = ? LIMIT 1", [PStr(event_id)]) {
    Err(_) => list.reverse(acc),
    Ok(rows) => match list.head(rows) {
      None => list.reverse(acc),
      Some(r) => {
        let evt := decode_event_row(r)
        let acc2 := list.cons(evt, acc)
        match evt.parent {
          None => list.reverse(acc2),
          Some(p) => walk_up(log, p, acc2),
        }
      },
    },
  }
}

# ---- Row decoder -------------------------------------------------
fn decode_event_row[R](row :: R) -> ev.Event {
  { id: opt_str(sql.get_str(row, "id")), kind: opt_str(sql.get_str(row, "kind")), parent: sql.get_str(row, "parent"), payload_json: opt_str(sql.get_str(row, "payload_json")), ts_ms: opt_int(sql.get_int(row, "ts_ms")) }
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
    opt_int(Some(1)) => 1,
    opt_int(None) => 0
  }
{
  match o {
    Some(n) => n,
    None => 0,
  }
}

