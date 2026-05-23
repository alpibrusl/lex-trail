# lex-trail tests — attest module

import "../src/log" as log

import "../src/attest" as att

import "std.list" as list

import "std.str" as str

fn test_add_and_chain_one() -> [sql, fs_write, time] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open failed: ", e)),
    Ok(l) => match log.append(l, "cap.invoked", None, "{\"cap\":\"summarize\"}") {
      Err(e) => Err(str.concat("append failed: ", e)),
      Ok(evt) => match att.add(l, evt.id, "sig.ed25519", "{\"sig\":\"abc\"}") {
        Err(e) => Err(str.concat("attest.add failed: ", e)),
        Ok(_) => match att.chain(l, evt.id) {
          Err(e) => Err(str.concat("attest.chain failed: ", e)),
          Ok(atts) => if list.len(atts) == 1 {
            Ok(())
          } else {
            Err(str.concat("expected 1 attestation, got ", str.concat("?", "")))
          },
        },
      },
    },
  }
}

fn test_chain_empty_on_unknown_event() -> [sql, fs_write] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open failed: ", e)),
    Ok(l) => match att.chain(l, "nonexistent-id") {
      Err(e) => Err(str.concat("unexpected error: ", e)),
      Ok(atts) => if list.len(atts) == 0 {
        Ok(())
      } else {
        Err("expected empty chain")
      },
    },
  }
}

fn test_attestation_has_event_id() -> [sql, fs_write, time] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open failed: ", e)),
    Ok(l) => match log.append(l, "spec.allowed", None, "{}") {
      Err(e) => Err(str.concat("append failed: ", e)),
      Ok(evt) => match att.add(l, evt.id, "origin.check", "{}") {
        Err(e) => Err(str.concat("attest.add failed: ", e)),
        Ok(a) => if a.event_id == evt.id {
          Ok(())
        } else {
          Err("attestation event_id mismatch")
        },
      },
    },
  }
}

fn test_two_attestations_same_event() -> [sql, fs_write, time] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open failed: ", e)),
    Ok(l) => match log.append(l, "llm.step", None, "{}") {
      Err(e) => Err(str.concat("append failed: ", e)),
      Ok(evt) => match att.add(l, evt.id, "sig.a", "{}") {
        Err(e) => Err(str.concat("first attest failed: ", e)),
        Ok(_) => match att.add(l, evt.id, "sig.b", "{}") {
          Err(e) => Err(str.concat("second attest failed: ", e)),
          Ok(_) => match att.chain(l, evt.id) {
            Err(e) => Err(str.concat("chain failed: ", e)),
            Ok(atts) => if list.len(atts) == 2 {
              Ok(())
            } else {
              Err("expected 2 attestations")
            },
          },
        },
      },
    },
  }
}

fn run_all() -> [sql, fs_write, time] Unit {
  let results := [test_add_and_chain_one(), test_chain_empty_on_unknown_event(), test_attestation_has_event_id(), test_two_attestations_same_event()]
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

