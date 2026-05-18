# lex-trail tests — replay module

import "../src/log"    as log
import "../src/replay" as replay
import "../src/kinds"  as k

import "std.list" as list
import "std.str"  as str
import "std.int"  as int

fn task_payload(task_id :: Str, extra :: Str) -> Str {
  str.concat("{\"task_id\":\"",
    str.concat(task_id,
      str.concat("\",", str.concat(extra, "}"))))
}

fn test_task_replay_finds_matching() -> [sql, fs_write, time] Result[Unit, Str] {
  let task_id := "test-task-001"
  match log.open_memory() {
    Err(e) => Err(str.concat("open failed: ", e)),
    Ok(l) =>
      match log.append(l, k.a2a_task_received(), None,
        task_payload(task_id, "\"skill\":\"summarize\"")) {
        Err(e) => Err(str.concat("append1 failed: ", e)),
        Ok(_) =>
          match log.append(l, k.llm_step(), None,
            task_payload(task_id, "\"tokens_in\":10,\"tokens_out\":5,\"tool_calls\":[]")) {
            Err(e) => Err(str.concat("append2 failed: ", e)),
            Ok(_) =>
              match replay.task(l, task_id) {
                Err(e)   => Err(str.concat("replay failed: ", e)),
                Ok(evts) =>
                  if list.len(evts) == 2 { Ok(()) }
                  else { Err(str.concat("expected 2 events, got ",
                    int.to_str(list.len(evts)))) },
              },
          },
      },
  }
}

fn test_task_replay_excludes_other_tasks() -> [sql, fs_write, time] Result[Unit, Str] {
  let task_id  := "wanted-task"
  let other_id := "other-task"
  match log.open_memory() {
    Err(e) => Err(str.concat("open failed: ", e)),
    Ok(l) =>
      match log.append(l, k.a2a_task_received(), None,
        task_payload(task_id, "\"skill\":\"translate\"")) {
        Err(e) => Err(str.concat("append wanted failed: ", e)),
        Ok(_) =>
          match log.append(l, k.cap_invoked(), None,
            task_payload(other_id, "\"capability\":\"search\"")) {
          Err(e) => Err(str.concat("append other failed: ", e)),
          Ok(_) =>
            match replay.task(l, task_id) {
              Err(e)   => Err(str.concat("replay failed: ", e)),
              Ok(evts) =>
                if list.len(evts) == 1 { Ok(()) }
                else { Err(str.concat("expected 1 event, got ",
                  int.to_str(list.len(evts)))) },
            },
          },
      },
  }
}

fn test_walk_chain_single_event() -> [sql, fs_write, time] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open failed: ", e)),
    Ok(l) =>
      match log.append(l, "k", None, "{}") {
        Err(e)  => Err(str.concat("append failed: ", e)),
        Ok(evt) => {
          let chain := replay.walk_chain(l, evt.id)
          if list.len(chain) == 1 { Ok(()) }
          else { Err("expected chain of length 1") }
        },
      },
  }
}

fn test_walk_chain_parent_link() -> [sql, fs_write, time] Result[Unit, Str] {
  match log.open_memory() {
    Err(e) => Err(str.concat("open failed: ", e)),
    Ok(l) =>
      match log.append(l, "root", None, "{}") {
        Err(e)    => Err(str.concat("root append failed: ", e)),
        Ok(root) =>
          match log.append(l, "child", Some(root.id), "{}") {
            Err(e)    => Err(str.concat("child append failed: ", e)),
            Ok(child) => {
              let chain := replay.walk_chain(l, child.id)
              if list.len(chain) == 2 { Ok(()) }
              else { Err(str.concat("expected chain of 2, got ",
                int.to_str(list.len(chain)))) }
            },
          },
      },
  }
}

fn run_all() -> [sql, fs_write, time] Unit {
  let results := [
    test_task_replay_finds_matching(),
    test_task_replay_excludes_other_tasks(),
    test_walk_chain_single_event(),
    test_walk_chain_parent_link(),
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
