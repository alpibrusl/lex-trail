# lex-trail — manifesto demo: trust by attestation, not comprehension
#
# Manifesto §IV / §V:
#   "an append-only log can record exactly what happened, signed,
#    content-addressed, tamper-evident. This chain is not understood —
#    it is verified, at every link."
#   "the human ... [relies] on tooling to enforce [the constraints].
#    The audit surface is smaller."
#
# This demo validates that claim two ways:
#
#   1. PURE CORE (checked at `lex check` time, no runtime needed).
#      Every event's id is the SHA-256 of its content. A tampered
#      event — payload rewritten, id left untouched — fails its
#      integrity check. The `examples {}` blocks below assert exactly
#      that, so `lex check` *is* the proof. Nobody read the agent's
#      code to discover the forgery; verification caught it.
#
#   2. END-TO-END REPLAY (runtime). A full task lifecycle is emitted,
#      then reconstructed from the log alone and integrity-swept. The
#      auditor never sees the agent's source — only the signed trail.
#
# Run the runtime story:
#   lex run --allow-effects sql,fs_write,time,io examples/manifesto_tamper.lex main

import "../src/event" as ev

import "../src/log" as log

import "../src/emit" as emit

import "../src/replay" as replay

import "../src/export" as export

import "std.str" as str

import "std.io" as io

import "std.list" as list

import "std.int" as int

# An honestly-recorded event. Its id is the content hash, so the
# integrity check passes. A caller trusts it WITHOUT reading how it
# was produced — the hash is the evidence.
fn honest_event() -> ev.Event {
  ev.make("llm.step", None, "{\"tokens_in\":10,\"tokens_out\":5}", 0)
}

# The same event with the payload rewritten (claiming zero tokens, to
# hide cost) but the original id kept. The content no longer hashes to
# the stored id.
fn tampered_event() -> ev.Event {
  let original := honest_event()
  { id: original.id, kind: original.kind, parent: original.parent, payload_json: "{\"tokens_in\":0,\"tokens_out\":0}", ts_ms: original.ts_ms }
}

# SELF-VALIDATING CLAIM, part 1: an honest event verifies.
fn honest_passes_integrity() -> Bool
  examples {
    honest_passes_integrity() => true
  }
{
  ev.is_valid(honest_event())
}

# SELF-VALIDATING CLAIM, part 2: a tampered event is detected. The
# example asserts the verdict is `false` — i.e. the forgery does not
# slip through. If tamper-detection ever regressed, `lex check` fails.
fn tampered_is_detected() -> Bool
  examples {
    tampered_is_detected() => false
  }
{
  ev.is_valid(tampered_event())
}

# Integrity-sweep a replayed trail: every link must verify.
fn verify_all(evts :: List[ev.Event]) -> Bool
  examples {
    verify_all([ev.make("k", None, "{}", 0)]) => true
  }
{
  list.fold(evts, true, fn (acc :: Bool, e :: ev.Event) -> Bool {
    if acc {
      ev.is_valid(e)
    } else {
      false
    }
  })
}

fn main() -> [sql, fs_write, time, io] Unit {
  let task_id := "manifesto-tamper-001"
  match log.open_memory() {
    Err(e) => io.print(str.concat("[error] log open failed: ", e)),
    Ok(l) => run_demo(l, task_id),
  }
}

# Emit a small lifecycle, replay it from the log alone, and sweep the
# reconstructed trail for integrity — the audit-without-comprehension
# path the manifesto describes.
fn run_demo(l :: log.Log, task_id :: Str) -> [sql, time, io] Unit {
  let p0 := emit_id(emit.a2a_task_received(l, task_id, "agent-a", "summarize", "{}", None))
  let p1 := emit_id(emit.llm_step(l, task_id, "lex-mini", 10, 5, "[]", p0))
  let __d := emit_id(emit.cap_completed(l, task_id, "summarize", "done", p1))
  match replay.task(l, task_id) {
    Err(e) => io.print(str.concat("[error] replay failed: ", e)),
    Ok(evts) => report(l, task_id, evts),
  }
}

fn emit_id(r :: Result[ev.Event, Str]) -> Option[Str] {
  match r {
    Ok(evt) => Some(evt.id),
    Err(_) => None,
  }
}

fn report(l :: log.Log, task_id :: Str, evts :: List[ev.Event]) -> [sql, io] Unit {
  let __h := io.print("=== manifesto: trust by attestation, not comprehension ===")
  let __c := io.print(str.concat("replayed events: ", int.to_str(list.len(evts))))
  let __v := io.print(str.concat("trail integrity (all links verify): ", show_bool(verify_all(evts))))
  let __t := io.print(str.concat("honest event verifies:   ", show_bool(honest_passes_integrity())))
  let __f := io.print(str.concat("tampered event detected: ", show_bool(tampered_is_detected() == false)))
  match export.task_report(l, task_id) {
    Err(e) => io.print(str.concat("[error] report failed: ", e)),
    Ok(rep) => io.print(rep),
  }
}

fn show_bool(b :: Bool) -> Str
  examples {
    show_bool(true) => "yes",
    show_bool(false) => "no"
  }
{
  if b {
    "yes"
  } else {
    "no"
  }
}

