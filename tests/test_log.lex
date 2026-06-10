# lex-trail tests — log module
#
# Each test opens its own :memory: database so tests are hermetic.

import "../src/log" as log

import "../src/event" as ev

import "std.list" as list

import "std.str" as str

import "std.int" as int

fn test_open_memory() -> [sql, fs_write] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open_memory failed: ", e)),
    Ok(_) => Ok(()),
  }
}

fn test_head_empty() -> [sql, fs_write] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open failed: ", e)),
    Ok(l) => match log.head(l) {
      None => Ok(()),
      Some(_) => Err("expected None on empty log"),
    },
  }
}

fn test_append_and_head() -> [sql, fs_write, time] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open failed: ", e)),
    Ok(l) => match log.append(l, "llm.step", None, "{\"tokens\":5}") {
      Err(e) => Err(str.concat("append failed: ", e)),
      Ok(evt) => match log.head(l) {
        None => Err("head returned None after append"),
        Some(h) => if h.id == evt.id {
          Ok(())
        } else {
          Err("head id does not match appended event id")
        },
      },
    },
  }
}

fn test_append_sets_kind() -> [sql, fs_write, time] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open failed: ", e)),
    Ok(l) => match log.append(l, "cap.invoked", None, "{}") {
      Err(e) => Err(str.concat("append failed: ", e)),
      Ok(evt) => if evt.kind == "cap.invoked" {
        Ok(())
      } else {
        Err(str.concat("wrong kind: ", evt.kind))
      },
    },
  }
}

fn test_append_with_parent() -> [sql, fs_write, time] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open failed: ", e)),
    Ok(l) => match log.append(l, "a2a.task.received", None, "{}") {
      Err(e) => Err(str.concat("first append failed: ", e)),
      Ok(evt1) => match log.append(l, "a2a.message.sent", Some(evt1.id), "{}") {
        Err(e) => Err(str.concat("second append failed: ", e)),
        Ok(evt2) => match evt2.parent {
          Some(p) => if p == evt1.id {
            Ok(())
          } else {
            Err("parent id mismatch")
          },
          None => Err("expected Some parent"),
        },
      },
    },
  }
}

fn test_range_returns_appended() -> [sql, fs_write, time] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open failed: ", e)),
    Ok(l) => match log.append(l, "cap.completed", None, "{}") {
      Err(e) => Err(str.concat("append failed: ", e)),
      Ok(evt) => match log.range(l, evt.ts_ms - 1000, evt.ts_ms + 1000) {
        Err(e) => Err(str.concat("range failed: ", e)),
        Ok(evts) => if list.len(evts) >= 1 {
          Ok(())
        } else {
          Err("range returned no events")
        },
      },
    },
  }
}

fn test_range_empty_window() -> [sql, fs_write] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open failed: ", e)),
    Ok(l) => match log.range(l, 0, 0) {
      Err(e) => Err(str.concat("range failed: ", e)),
      Ok(evts) => if list.len(evts) == 0 {
        Ok(())
      } else {
        Err("expected empty range")
      },
    },
  }
}

fn run_all() -> [sql, fs_write, time] Unit {
  let results := [test_open_memory(), test_head_empty(), test_append_and_head(), test_append_sets_kind(), test_append_with_parent(), test_range_returns_appended(), test_range_empty_window()]
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


fn test_append_at_deterministic() -> [sql, fs_write] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open a failed: ", e)),
    Ok(a) => match log.open_memory() {
      Err(e) => Err(str.concat("open b failed: ", e)),
      Ok(b) => match log.append_at(a, "sim.fill", None, "{\"px\":100}", 1700000000000) {
        Err(e) => Err(str.concat("append_at a failed: ", e)),
        Ok(ea) => match log.append_at(b, "sim.fill", None, "{\"px\":100}", 1700000000000) {
          Err(e) => Err(str.concat("append_at b failed: ", e)),
          Ok(eb) => if ea.id == eb.id {
            Ok(())
          } else {
            Err("same inputs produced different event ids across logs")
          },
        },
      },
    },
  }
}

fn test_append_at_ts_changes_id() -> [sql, fs_write] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open failed: ", e)),
    Ok(l) => match log.append_at(l, "sim.fill", None, "{\"px\":100}", 1) {
      Err(e) => Err(str.concat("append_at 1 failed: ", e)),
      Ok(e1) => match log.append_at(l, "sim.fill", None, "{\"px\":100}", 2) {
        Err(e) => Err(str.concat("append_at 2 failed: ", e)),
        Ok(e2) => if e1.id == e2.id {
          Err("different ts_ms should produce different content hashes")
        } else {
          Ok(())
        },
      },
    },
  }
}
