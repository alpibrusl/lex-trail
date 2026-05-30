# lex-trail tests — sequential hash chain (verify_chain)
#
# Covers two properties:
#   1. verify_chain returns Ok(N) on an honest log with N events
#   2. verify_chain returns Err on a log where a row was deleted
#      (seq gap), proving deletion is detectable even when each
#      remaining row's own content-hash is still valid.

import "../src/log" as log

import "std.sql" as sql

import "std.str" as str

import "std.int" as int

import "std.list" as list

fn test_verify_chain_honest() -> [sql, fs_write, time] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open failed: ", e)),
    Ok(l) => match log.append(l, "llm.step", None, "{\"step\":1}") {
      Err(e) => Err(str.concat("append 1 failed: ", e)),
      Ok(_) => match log.append(l, "llm.step", None, "{\"step\":2}") {
        Err(e) => Err(str.concat("append 2 failed: ", e)),
        Ok(_) => match log.append(l, "llm.step", None, "{\"step\":3}") {
          Err(e) => Err(str.concat("append 3 failed: ", e)),
          Ok(_) => match log.verify_chain(l) {
            Err(e) => Err(str.concat("verify_chain failed on honest log: ", e)),
            Ok(n) => if n == 3 {
              Ok(())
            } else {
              Err(str.concat("expected 3 verified events, got ", int.to_str(n)))
            },
          },
        },
      },
    },
  }
}

# Delete the middle event (seq=1) and confirm verify_chain detects the
# seq gap — this is the deletion-detection property that per-event
# content hashes alone cannot provide.
fn test_verify_chain_detects_deletion() -> [sql, fs_write, time] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open failed: ", e)),
    Ok(l) => match log.append(l, "llm.step", None, "{\"step\":1}") {
      Err(e) => Err(str.concat("append 1 failed: ", e)),
      Ok(_) => match log.append(l, "llm.step", None, "{\"step\":2}") {
        Err(e) => Err(str.concat("append 2 failed: ", e)),
        Ok(_) => match log.append(l, "llm.step", None, "{\"step\":3}") {
          Err(e) => Err(str.concat("append 3 failed: ", e)),
          Ok(_) => match sql.exec(l.db, "DELETE FROM events WHERE seq = 1", []) {
            Err(e) => Err(str.concat("delete failed: ", e.message)),
            Ok(_) => match log.verify_chain(l) {
              Ok(n) => Err(str.concat("verify_chain should detect deletion, got Ok(", str.concat(int.to_str(n), ")"))),
              Err(_) => Ok(()),
            },
          },
        },
      },
    },
  }
}

fn run_all() -> [sql, fs_write, time] Unit {
  let results := [test_verify_chain_honest(), test_verify_chain_detects_deletion()]
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
