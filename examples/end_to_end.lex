# lex-trail example — end-to-end agent task, captured and audited
#
# This is the headline trust demo: a full A2A task lifecycle is emitted
# through the typed `emit` helpers (the same surface lex-agent / lex-llm
# call), then a human-inspectable, integrity-checked JSON audit report
# is produced from the log alone — nobody had to read the agent's code
# to know what it did.
#
# Lifecycle captured (all chained by parent id):
#   a2a.task.received  → agent-b accepts a "summarize" task from agent-a
#   llm.step           → one model inference step
#   cap.invoked        → the summarize capability is invoked
#   spec.allowed       → a policy check passes
#   cap.completed      → the capability returns a result
#   a2a.message.sent   → the answer is sent back
#   a2a.task.state_change → working → completed
#
# Run:
#   lex run --allow-effects sql,fs_write,time,io examples/end_to_end.lex main

import "lex-trail/log" as log

import "lex-trail/emit" as emit

import "lex-trail/export" as export

import "lex-trail/event" as ev

import "std.str" as str

import "std.io" as io

fn main() -> [sql, fs_write, time, io] Unit {
  let task_id := "e2e-demo-001"
  match log.open_memory() {
    Err(e) => io.print(str.concat("[error] log open failed: ", e)),
    Ok(l) => run_demo(l, task_id),
  }
}

# Emit the lifecycle, threading each event's id into the next as
# `parent` so the trail forms a single verifiable chain.
fn run_demo(l :: log.Log, task_id :: Str) -> [sql, time, io] Unit {
  let p0 := emit_step(emit.a2a_task_received(l, task_id, "agent-a", "summarize", "{}", None))
  let p1 := emit_step(emit.llm_step(l, task_id, "lex-mini", 128, 32, "[]", p0))
  let p2 := emit_step(emit.cap_invoked(l, task_id, "summarize", "{}", "agent-b", p1))
  let p3 := emit_step(emit.spec_allowed(l, task_id, "no_pii", "{}", p2))
  let p4 := emit_step(emit.cap_completed(l, task_id, "summarize", "Summary ready.", p3))
  let p5 := emit_step(emit.a2a_message_sent(l, task_id, "m-out", "[{\"type\":\"text\",\"text\":\"Summary ready.\"}]", p4))
  let __lex_discard_1 := emit_step(emit.a2a_state_change(l, task_id, "working", "completed", p5))
  print_report(l, task_id)
}

# Unwrap an emit result into the id to use as the next parent. On error
# the chain simply restarts from a root (None) for the next event.
fn emit_step(r :: Result[ev.Event, Str]) -> Option[Str] {
  match r {
    Ok(evt) => Some(evt.id),
    Err(_) => None,
  }
}

fn print_report(l :: log.Log, task_id :: Str) -> [sql, io] Unit {
  let __lex_discard_2 := io.print(str.concat("=== Audit report: task ", str.concat(task_id, " ===")))
  match export.task_report(l, task_id) {
    Err(e) => io.print(str.concat("[error] report failed: ", e)),
    Ok(report) => io.print(report),
  }
}

