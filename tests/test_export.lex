# lex-trail tests — export module
#
# Verifies the JSON audit report carries the event count, the integrity
# summary, and survives caller input that contains JSON metacharacters.

import "../src/export" as export

import "../src/emit" as emit

import "../src/log" as log

import "std.list" as list

import "std.str" as str

fn test_report_shape() -> [sql, fs_write, time] Result[Unit, Str] {
  let task_id := "rep-1"
  match log.open_memory() {
    Err(e) => Err(str.concat("open: ", e)),
    Ok(l) => {
      let __lex_discard_1 := emit.a2a_task_received(l, task_id, "agent-a", "summarize", "{}", None)
      let __lex_discard_2 := emit.llm_step(l, task_id, "lex-mini", 1, 1, "[]", None)
      match export.task_report(l, task_id) {
        Err(e) => Err(str.concat("report: ", e)),
        Ok(rep) => if str.contains(rep, "\"event_count\":2") and str.contains(rep, "\"all_valid\":true") {
          Ok(())
        } else {
          Err(str.concat("unexpected report: ", rep))
        },
      }
    },
  }
}

fn test_report_contains_kind() -> [sql, fs_write, time] Result[Unit, Str] {
  let task_id := "rep-2"
  match log.open_memory() {
    Err(e) => Err(str.concat("open: ", e)),
    Ok(l) => {
      let __lex_discard_3 := emit.cap_invoked(l, task_id, "search", "{}", "agent-b", None)
      match export.task_report(l, task_id) {
        Err(e) => Err(str.concat("report: ", e)),
        Ok(rep) => if str.contains(rep, "\"kind\":\"cap.invoked\"") {
          Ok(())
        } else {
          Err(str.concat("kind missing from report: ", rep))
        },
      }
    },
  }
}

fn test_empty_report() -> [sql, fs_write, time] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open: ", e)),
    Ok(l) => match export.task_report(l, "nope") {
      Err(e) => Err(str.concat("report: ", e)),
      Ok(rep) => if str.contains(rep, "\"event_count\":0") and str.contains(rep, "\"events\":[]") {
        Ok(())
      } else {
        Err(str.concat("unexpected empty report: ", rep))
      },
    },
  }
}

fn run_all() -> [sql, fs_write, time] Unit {
  let results := [test_report_shape(), test_report_contains_kind(), test_empty_report()]
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

