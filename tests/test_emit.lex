# lex-trail tests — emit module
#
# Verifies the typed emitters append valid, replayable events. Each
# test opens its own :memory: database so tests are hermetic.

import "../src/emit" as emit

import "../src/log" as log

import "../src/event" as ev

import "../src/replay" as replay

import "std.list" as list

import "std.str" as str

import "std.int" as int

fn test_task_received_is_valid() -> [sql, fs_write, time] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open: ", e)),
    Ok(l) => match emit.a2a_task_received(l, "t1", "agent-a", "summarize", "{}", None) {
      Err(e) => Err(str.concat("emit: ", e)),
      Ok(evt) => if ev.is_valid(evt) {
        Ok(())
      } else {
        Err("appended event failed is_valid")
      },
    },
  }
}

fn test_task_sent_is_valid() -> [sql, fs_write, time] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open: ", e)),
    Ok(l) => match emit.a2a_task_sent(l, "t1", "agent-b", "translate", "{}", None) {
      Err(e) => Err(str.concat("emit: ", e)),
      Ok(evt) => if ev.is_valid(evt) {
        Ok(())
      } else {
        Err("appended event failed is_valid")
      },
    },
  }
}

fn test_message_emitters() -> [sql, fs_write, time] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open: ", e)),
    Ok(l) => match emit.a2a_message_received(l, "t1", "m1", "[]", None) {
      Err(e) => Err(str.concat("recv: ", e)),
      Ok(_) => match emit.a2a_message_sent(l, "t1", "m2", "[]", None) {
        Err(e) => Err(str.concat("sent: ", e)),
        Ok(_) => Ok(()),
      },
    },
  }
}

fn test_spec_and_human_emitters() -> [sql, fs_write, time] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open: ", e)),
    Ok(l) => match emit.spec_denied(l, "t1", "no_pii", "{}", "ssn detected", None) {
      Err(e) => Err(str.concat("spec: ", e)),
      Ok(_) => match emit.human_escalated(l, "t1", "ok to deploy?", "prod", None) {
        Err(e) => Err(str.concat("escalate: ", e)),
        Ok(_) => match emit.human_replied(l, "t1", "yes", None) {
          Err(e) => Err(str.concat("reply: ", e)),
          Ok(_) => Ok(()),
        },
      },
    },
  }
}

# End-to-end: a full A2A task lifecycle, replayed from the log alone.
fn test_full_lifecycle_replay() -> [sql, fs_write, time] Result[Unit, Str] {
  let task_id := "lifecycle-1"
  match log.open_memory() {
    Err(e) => Err(str.concat("open: ", e)),
    Ok(l) => {
      let __lex_discard_1 := emit.a2a_task_received(l, task_id, "agent-a", "summarize", "{}", None)
      let __lex_discard_2 := emit.llm_step(l, task_id, "lex-mini", 10, 5, "[]", None)
      let __lex_discard_3 := emit.cap_invoked(l, task_id, "summarize", "{}", "agent-a", None)
      let __lex_discard_4 := emit.cap_completed(l, task_id, "summarize", "done", None)
      let __lex_discard_5 := emit.a2a_state_change(l, task_id, "working", "completed", None)
      match replay.task(l, task_id) {
        Err(e) => Err(str.concat("replay: ", e)),
        Ok(evts) => if list.len(evts) == 5 {
          Ok(())
        } else {
          Err(str.concat("expected 5 events, got ", int.to_str(list.len(evts))))
        },
      }
    },
  }
}

# Caller input with embedded quotes must not corrupt the payload: the
# event still validates and replays under its task_id.
fn test_escaping_does_not_break_replay() -> [sql, fs_write, time] Result[Unit, Str] {
  let task_id := "quote-task"
  match log.open_memory() {
    Err(e) => Err(str.concat("open: ", e)),
    Ok(l) => match emit.cap_completed(l, task_id, "echo", "he said \"hi\"", None) {
      Err(e) => Err(str.concat("emit: ", e)),
      Ok(evt) => if ev.is_valid(evt) {
        match replay.task(l, task_id) {
          Err(e) => Err(str.concat("replay: ", e)),
          Ok(evts) => if list.len(evts) == 1 {
            Ok(())
          } else {
            Err(str.concat("expected 1 event, got ", int.to_str(list.len(evts))))
          },
        }
      } else {
        Err("event with escaped quotes failed is_valid")
      },
    },
  }
}

fn run_all() -> [sql, fs_write, time] Unit {
  let results := [test_task_received_is_valid(), test_task_sent_is_valid(), test_message_emitters(), test_spec_and_human_emitters(), test_full_lifecycle_replay(), test_escaping_does_not_break_replay()]
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

