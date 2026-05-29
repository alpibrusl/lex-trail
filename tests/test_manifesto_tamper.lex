# CI-covered self-validation for the manifesto tamper-evidence demo
# (examples/manifesto_tamper.lex). Asserts under `lex test` that the
# content-addressed integrity check accepts an honest event and rejects
# a tampered one — trust by verification, not by reading the producer.

import "lex-trail/event" as ev

import "std.list" as list

fn honest_event() -> ev.Event {
  ev.make("llm.step", None, "{\"tokens_in\":10,\"tokens_out\":5}", 0)
}

fn tampered_event() -> ev.Event {
  let original := honest_event()
  { id: original.id, kind: original.kind, parent: original.parent, payload_json: "{\"tokens_in\":0,\"tokens_out\":0}", ts_ms: original.ts_ms }
}

fn honest_event_verifies() -> Result[Unit, Str] {
  if ev.is_valid(honest_event()) {
    Ok(())
  } else {
    Err("honest event failed its own integrity check")
  }
}

fn tampering_is_detected() -> Result[Unit, Str] {
  if ev.is_valid(tampered_event()) {
    Err("tampered event passed integrity — detection failed")
  } else {
    Ok(())
  }
}

fn run_all() -> Unit {
  let results := [honest_event_verifies(), tampering_is_detected()]
  let failures := list.fold(results, 0, fn (n :: Int, r :: Result[Unit, Str]) -> Int {
    match r {
      Ok(_) => n,
      Err(_) => n + 1,
    }
  })
  if failures == 0 {
    ()
  } else {
    let __discard := 1 / 0
    ()
  }
}

