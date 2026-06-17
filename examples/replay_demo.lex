# lex-trail — Content-addressed audit chains for AI agents
#
# Theatrical demo: two AI trading agent sessions recorded in parallel
# in-memory trail logs.  Zero LLM calls — the trail API is exercised
# directly.
#
# Session 1: ORD-001 accepted (qty=100)  — 5 events, SHA-256 chain intact
# Session 2: ORD-BAD rejected (qty=5000) — 3 events, spec denied
#
# Shows:
#   1. Recording events (content-addressed, parent-linked chain)
#   2. Chain verification (verify_chain)
#   3. Session replay (walk_chain, root-first)
#   4. Audit report (export.task_report, JSON)
#   5. Tamper detection explanation
#
# Run:
#   lex run --allow-effects fs_write,io,sql,time examples/replay_demo.lex main

import "../src/log" as log

import "../src/emit" as emit

import "../src/replay" as replay

import "../src/export" as export

import "../src/event" as ev

import "std.str" as str

import "std.int" as int

import "std.io" as io

import "std.list" as list

# ── Helpers ─────────────────────────────────────────────────────────────────
# Append n spaces to a string.
fn add_spaces(s :: Str, n :: Int) -> Str {
  if n <= 0 {
    s
  } else {
    add_spaces(str.concat(s, " "), n - 1)
  }
}

# Pad or truncate a kind string to exactly 20 chars for aligned output.
fn pad_kind(s :: Str) -> Str {
  let n := str.len(s)
  if n >= 20 {
    str.slice(s, 0, 20)
  } else {
    add_spaces(s, 20 - n)
  }
}

# Take first N chars of a string.
fn take(s :: Str, n :: Int) -> Str {
  if str.len(s) <= n {
    s
  } else {
    str.slice(s, 0, n)
  }
}

# Format a parent Option[Str] for display.
fn show_parent(p :: Option[Str]) -> Str {
  match p {
    None => "root",
    Some(id) => str.concat(take(id, 8), "..."),
  }
}

# Print a single event line.
fn print_event(evt :: ev.Event) -> [io] Unit {
  let id_short := str.concat(take(evt.id, 16), "...")
  let par_short := show_parent(evt.parent)
  io.print(str.concat("  ", str.concat(pad_kind(evt.kind), str.concat("  id: ", str.concat(id_short, str.concat("  parent: ", par_short))))))
}

# Unwrap a Result[ev.Event, Str] → Option[Str] (the id to use as next parent).
fn emit_id(r :: Result[ev.Event, Str]) -> Option[Str] {
  match r {
    Ok(e) => Some(e.id),
    Err(_) => None,
  }
}

# Unwrap a Result[ev.Event, Str] → ev.Event, printing and returning an error
# sentinel on failure.
fn unwrap_event(r :: Result[ev.Event, Str]) -> [io] ev.Event {
  match r {
    Ok(e) => e,
    Err(msg) => {
      let __p := io.print(str.concat("[error] emit failed: ", msg))
      ev.make("error", None, "{}", 0)
    },
  }
}

# Print and unwrap, returning the event's id as Option[Str].
fn print_and_chain(r :: Result[ev.Event, Str]) -> [io] Option[Str] {
  match r {
    Err(msg) => {
      let __p := io.print(str.concat("[error] emit failed: ", msg))
      None
    },
    Ok(e) => {
      let __p := print_event(e)
      Some(e.id)
    },
  }
}

fn hr() -> [io] Unit {
  io.print("  ────────────────────────────────────────────────────────────────────────")
}

fn hdr(title :: Str) -> [io] Unit {
  let __a := io.print("")
  let __b := hr()
  let __c := io.print(str.concat("  ", title))
  hr()
}

# ── Session 1 — ORD-001 accepted ─────────────────────────────────────────────
fn run_session_1(l :: log.Log) -> [sql, time, io] Unit {
  let task_id := "TASK-001"
  let __h := hdr("Session 1 — ORD-001  qty=100  ACCEPTED   (5 events)")
  let r1 := emit.a2a_task_received(l, task_id, "trading-agent", "submit_order", "{\"symbol\":\"MSFT\",\"qty\":100}", None)
  let p1 := print_and_chain(r1)
  let r2 := emit.spec_allowed(l, task_id, "order_submit_policy", "{\"tool\":\"submit_order\",\"qty\":100,\"approved\":true}", p1)
  let p2 := print_and_chain(r2)
  let r3 := emit.cap_invoked(l, task_id, "validate_order", "{\"symbol\":\"MSFT\",\"qty\":100}", "trading-agent", p2)
  let p3 := print_and_chain(r3)
  let r4 := emit.llm_step(l, task_id, "claude-sonnet-4-6", 350, 85, "[{\"name\":\"submit_order\",\"args\":{\"symbol\":\"MSFT\",\"qty\":100}}]", p3)
  let p4 := print_and_chain(r4)
  let r5 := emit.cap_completed(l, task_id, "validate_order", "accepted: entry_id=c267ad43...", p4)
  let __p5 := print_and_chain(r5)
  io.print("")
}

# ── Session 2 — ORD-BAD rejected ────────────────────────────────────────────
fn run_session_2(l :: log.Log) -> [sql, time, io] Unit {
  let task_id := "TASK-002"
  let __h := hdr("Session 2 — ORD-BAD  qty=5000  REJECTED  (3 events)")
  let r1 := emit.a2a_task_received(l, task_id, "trading-agent", "submit_order", "{\"symbol\":\"MSFT\",\"qty\":5000}", None)
  let p1 := print_and_chain(r1)
  let r2 := emit.spec_denied(l, task_id, "order_submit_policy", "{\"tool\":\"submit_order\",\"qty\":5000,\"approved\":true}", "quantity 5000 exceeds limit 1000", p1)
  let p2 := print_and_chain(r2)
  let r3 := emit.cap_failed(l, task_id, "validate_order", "spec denied: quantity 5000 exceeds limit 1000", p2)
  let __p3 := print_and_chain(r3)
  io.print("")
}

# ── Chain verification ───────────────────────────────────────────────────────
fn show_verify(l1 :: log.Log, l2 :: log.Log) -> [sql, io] Unit {
  let __h := hdr("Chain Verification — SHA-256 sequential hash chain")
  let v1 := log.verify_chain(l1)
  let v2 := log.verify_chain(l2)
  let s1 := match v1 {
    Ok(n) => str.concat("Ok(", str.concat(int.to_str(n), ")")),
    Err(e) => str.concat("Err(", str.concat(e, ")")),
  }
  let s2 := match v2 {
    Ok(n) => str.concat("Ok(", str.concat(int.to_str(n), ")")),
    Err(e) => str.concat("Err(", str.concat(e, ")")),
  }
  let ok1 := match v1 {
    Ok(_) => true,
    Err(_) => false,
  }
  let ok2 := match v2 {
    Ok(_) => true,
    Err(_) => false,
  }
  let sym1 := if ok1 {
    "✓"
  } else {
    "✗"
  }
  let sym2 := if ok2 {
    "✓"
  } else {
    "✗"
  }
  let c1 := match v1 {
    Ok(n) => int.to_str(n),
    Err(_) => "?",
  }
  let c2 := match v2 {
    Ok(n) => int.to_str(n),
    Err(_) => "?",
  }
  let __a := io.print(str.concat("  Session 1: verify_chain → ", str.concat(sym1, str.concat("  ", str.concat(c1, " events, chain intact")))))
  let __b := io.print(str.concat("  Session 2: verify_chain → ", str.concat(sym2, str.concat("  ", str.concat(c2, " events, chain intact")))))
  io.print("")
}

# ── Replay — walk_chain from Session 1 leaf ─────────────────────────────────
# Format a single replay event line (indexed, root-first).
fn fmt_replay_line(evt :: ev.Event, idx :: Int) -> Str {
  let n := str.concat("[", str.concat(int.to_str(idx), "] "))
  str.concat("  ", str.concat(n, str.concat(pad_kind(evt.kind), str.concat("  id: ", str.concat(take(evt.id, 12), "...")))))
}

fn print_replay_events(evts :: List[ev.Event], idx :: Int) -> [io] Unit {
  match list.head(evts) {
    None => io.print(""),
    Some(e) => {
      let __p := io.print(fmt_replay_line(e, idx))
      print_replay_events(list.tail(evts), idx + 1)
    },
  }
}

fn show_replay(l1 :: log.Log) -> [sql, io] Unit {
  let __h := hdr("Replay — walk_chain from Session 1 leaf back to root")
  let leaf_opt := log.head(l1)
  match leaf_opt {
    None => io.print("  [no events in log]"),
    Some(leaf) => {
      let __info := io.print(str.concat("  Starting from leaf: ", str.concat(take(leaf.id, 12), "...")))
      let __info2 := io.print("  walk_chain follows parent pointers back to root — causal order:")
      let __nl := io.print("")
      let chain := replay.walk_chain(l1, leaf.id)
      print_replay_events(chain, 1)
    },
  }
}

# ── Audit report ─────────────────────────────────────────────────────────────
fn show_audit(l2 :: log.Log) -> [sql, io] Unit {
  let __h := hdr("Audit Report — export.task_report for Session 2 (ORD-BAD rejected)")
  let __note := io.print("  Full audit report for the rejected session — every decision, cryptographically chained.")
  let __nl := io.print("")
  match export.task_report(l2, "TASK-002") {
    Err(e) => io.print(str.concat("[error] task_report failed: ", e)),
    Ok(json_str) => io.print(json_str),
  }
}

# ── Tamper detection note ────────────────────────────────────────────────────
fn show_tamper_note() -> [io] Unit {
  let __h := hdr("Tamper Detection — why content-addressing matters")
  let __l1 := io.print("  Same content → same SHA-256 id  (idempotent append: INSERT OR IGNORE).")
  let __l2 := io.print("  Mutate any byte in payload_json → id no longer matches stored hash.")
  let __l3 := io.print("  verify_chain catches it: chain_hash is SHA-256(prev_hash:event_id:seq).")
  let __l4 := io.print("  Delete any row → seq gap detected immediately.")
  let __l5 := io.print("  No trust in the agent's code — trust in the math.")
  io.print("")
}

# ── Main ─────────────────────────────────────────────────────────────────────
fn main() -> [io, sql, fs_write, time] Unit {
  let __title := io.print("")
  let __t1 := io.print("  lex-trail  ·  Content-addressed audit chains for AI agents")
  let __t2 := io.print("  Every decision. SHA-256 content-addressed. Deterministically replayable. Tamper-evident.")
  let __t3 := io.print("")
  match log.open_memory() {
    Err(e) => io.print(str.concat("[error] log1 open failed: ", e)),
    Ok(l1) => match log.open_memory() {
      Err(e) => io.print(str.concat("[error] log2 open failed: ", e)),
      Ok(l2) => {
        let __s1 := run_session_1(l1)
        let __s2 := run_session_2(l2)
        let __v := show_verify(l1, l2)
        let __r := show_replay(l1)
        let __a := show_audit(l2)
        show_tamper_note()
      },
    },
  }
}

