# lex-trail tests — event module (pure, no effects)

import "../src/event" as ev

import "std.list" as list
import "std.str"  as str

fn test_compute_id_deterministic() -> Result[Unit, Str] {
  let id1 := ev.compute_id("k", None, "{}", 0)
  let id2 := ev.compute_id("k", None, "{}", 0)
  if id1 == id2 { Ok(()) }
  else { Err("non-deterministic id") }
}

fn test_compute_id_changes_on_kind() -> Result[Unit, Str] {
  let id1 := ev.compute_id("a", None, "{}", 0)
  let id2 := ev.compute_id("b", None, "{}", 0)
  if id1 != id2 { Ok(()) }
  else { Err("different kinds produced same id") }
}

fn test_compute_id_changes_on_parent() -> Result[Unit, Str] {
  let id1 := ev.compute_id("k", None,        "{}", 0)
  let id2 := ev.compute_id("k", Some("px"),  "{}", 0)
  if id1 != id2 { Ok(()) }
  else { Err("different parents produced same id") }
}

fn test_compute_id_changes_on_payload() -> Result[Unit, Str] {
  let id1 := ev.compute_id("k", None, "{}" , 0)
  let id2 := ev.compute_id("k", None, "{\"x\":1}", 0)
  if id1 != id2 { Ok(()) }
  else { Err("different payloads produced same id") }
}

fn test_compute_id_changes_on_ts_ms() -> Result[Unit, Str] {
  let id1 := ev.compute_id("k", None, "{}", 0)
  let id2 := ev.compute_id("k", None, "{}", 1)
  if id1 != id2 { Ok(()) }
  else { Err("different ts_ms produced same id") }
}

fn test_make_kind() -> Result[Unit, Str] {
  let evt := ev.make("llm.step", None, "{}", 0)
  if evt.kind == "llm.step" { Ok(()) }
  else { Err(str.concat("wrong kind: ", evt.kind)) }
}

fn test_make_payload() -> Result[Unit, Str] {
  let evt := ev.make("k", None, "{\"x\":1}", 0)
  if evt.payload_json == "{\"x\":1}" { Ok(()) }
  else { Err(str.concat("wrong payload: ", evt.payload_json)) }
}

fn test_make_ts_ms() -> Result[Unit, Str] {
  let evt := ev.make("k", None, "{}", 9999)
  if evt.ts_ms == 9999 { Ok(()) }
  else { Err("wrong ts_ms") }
}

fn test_make_parent_none() -> Result[Unit, Str] {
  let evt := ev.make("k", None, "{}", 0)
  match evt.parent {
    None    => Ok(()),
    Some(_) => Err("expected None parent"),
  }
}

fn test_make_parent_some() -> Result[Unit, Str] {
  let evt := ev.make("k", Some("parent-id"), "{}", 0)
  match evt.parent {
    Some(p) => if p == "parent-id" { Ok(()) } else { Err("wrong parent id") },
    None    => Err("expected Some parent"),
  }
}

fn test_is_valid_fresh() -> Result[Unit, Str] {
  let evt := ev.make("spec.allowed", None, "{}", 1)
  if ev.is_valid(evt) { Ok(()) }
  else { Err("freshly made event failed is_valid") }
}

fn test_is_valid_rejects_tampered_kind() -> Result[Unit, Str] {
  let evt := ev.make("spec.allowed", None, "{}", 1)
  let bad := { id: evt.id, kind: "spec.denied", parent: evt.parent,
                payload_json: evt.payload_json, ts_ms: evt.ts_ms }
  if not ev.is_valid(bad) { Ok(()) }
  else { Err("tampered event passed is_valid") }
}

fn run_all() -> Unit {
  let results := [
    test_compute_id_deterministic(),
    test_compute_id_changes_on_kind(),
    test_compute_id_changes_on_parent(),
    test_compute_id_changes_on_payload(),
    test_compute_id_changes_on_ts_ms(),
    test_make_kind(),
    test_make_payload(),
    test_make_ts_ms(),
    test_make_parent_none(),
    test_make_parent_some(),
    test_is_valid_fresh(),
    test_is_valid_rejects_tampered_kind(),
  ]
  let failures := list.fold(results, 0,
    fn (n :: Int, r :: Result[Unit, Str]) -> Int {
      match r { Ok(_) => n, Err(_) => n + 1 }
    })
  if failures == 0 { () }
  else {
    let __discard := 1 / 0
    ()
  }
}
