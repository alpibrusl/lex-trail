# lex-trail tests — durable SQLite backend
#
# The in-memory backend is exercised everywhere else; this file pins
# the durability guarantee of the file-backed backend: events written
# through one handle survive `close` and are readable (and still
# integrity-valid) through a freshly opened handle on the same path.
#
# Each run uses a unique timestamped path under /tmp so the test is
# hermetic across runs.

import "../src/log" as log

import "../src/event" as ev

import "../src/replay" as replay

import "std.list" as list

import "std.str" as str

import "std.int" as int

import "std.time" as time

fn test_events_survive_reopen() -> [sql, fs_write, time] Result[Unit, Str] {
  let ts := time.now_ms()
  let path := str.concat("/tmp/lex-trail-persist-", str.concat(int.to_str(ts), ".db"))
  let task_id := str.concat("persist-", int.to_str(ts))
  let payload := str.concat("{\"task_id\":\"", str.concat(task_id, "\"}"))
  match log.open(path) {
    Err(e) => Err(str.concat("open1: ", e)),
    Ok(l1) => match log.append(l1, "a2a.task.received", None, payload) {
      Err(e) => Err(str.concat("append: ", e)),
      Ok(evt) => {
        let __lex_discard_1 := log.close(l1)
        match log.open(path) {
          Err(e) => Err(str.concat("open2: ", e)),
          Ok(l2) => match replay.task(l2, task_id) {
            Err(e) => Err(str.concat("replay: ", e)),
            Ok(evts) => match list.head(evts) {
              None => Err("event did not survive reopen"),
              Some(got) => if got.id == evt.id and ev.is_valid(got) {
                Ok(())
              } else {
                Err("reopened event id mismatch or failed is_valid")
              },
            },
          },
        }
      },
    },
  }
}

fn run_all() -> [sql, fs_write, time] Unit {
  let results := [test_events_survive_reopen()]
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

