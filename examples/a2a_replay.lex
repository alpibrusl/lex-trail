# lex-trail example — A2A task replay across two Lex agents
#
# Simulates:
#   - Agent A sends a task to Agent B  (a2a.task.sent)
#   - Agent B receives it              (a2a.task.received)
#   - Agent B invokes a capability     (cap.invoked)
#   - The capability completes         (cap.completed)
#   - Task state transitions           (a2a.task.state_change)
#   - Full trace replayed by task_id
#
# All events live in a shared in-memory log.
#
# Run:
#   lex run --allow-effects sql,fs_write,time,io examples/a2a_replay.lex main

import "../src/log" as log

import "../src/replay" as replay

import "../src/kinds" as k

import "../src/event" as ev

import "std.str" as str

import "std.int" as int

import "std.list" as list

import "std.io" as io

fn main() -> [sql, fs_write, time, io] Unit {
  let task_id := "a2a-demo-task-001"
  match log.open_memory() {
    Err(e) => io.print(str.concat("[error] log open failed: ", e)),
    Ok(l) => run_demo(l, task_id),
  }
}

fn run_demo(l :: log.Log, task_id :: Str) -> [sql, time, io] Unit {
  let sent_pay := str.concat("{\"task_id\":\"", str.concat(task_id, "\",\"to_agent\":\"agent-b\",\"skill\":\"summarize\",\"params\":{}}"))
  let __lex_discard_1 := log.append(l, k.a2a_task_sent(), None, sent_pay)
  let recv_root := match log.append(l, k.a2a_task_sent(), None, sent_pay) {
    Ok(ev) => Some(ev.id),
    Err(_) => None,
  }
  let recv_pay := str.concat("{\"task_id\":\"", str.concat(task_id, "\",\"from_agent\":\"agent-a\",\"skill\":\"summarize\",\"params\":{}}"))
  let __lex_discard_2 := log.append(l, k.a2a_task_received(), recv_root, recv_pay)
  let cap_pay := str.concat("{\"task_id\":\"", str.concat(task_id, "\",\"capability\":\"summarize\",\"args\":{},\"agent\":\"agent-b\"}"))
  let __lex_discard_3 := log.append(l, k.cap_invoked(), None, cap_pay)
  let done_pay := str.concat("{\"task_id\":\"", str.concat(task_id, "\",\"capability\":\"summarize\",\"result\":\"Summary ready.\"}"))
  let __lex_discard_4 := log.append(l, k.cap_completed(), None, done_pay)
  let state_pay := str.concat("{\"task_id\":\"", str.concat(task_id, "\",\"from_state\":\"working\",\"to_state\":\"completed\"}"))
  let __lex_discard_5 := log.append(l, k.a2a_task_state_change(), None, state_pay)
  let __lex_discard_6 := io.print(str.concat("=== Replay: task ", str.concat(task_id, " ===")))
  match replay.task(l, task_id) {
    Err(e) => io.print(str.concat("[error] replay failed: ", e)),
    Ok(evts) => {
      let __lex_discard_7 := list.map(evts, fn (evt :: ev.Event) -> [io] Unit {
        io.print(str.concat("  [", str.concat(evt.kind, str.concat("] id=", str.concat(evt.id, str.concat(" ts=", int.to_str(evt.ts_ms)))))))
      })
      io.print(str.concat(int.to_str(list.len(evts)), " events replayed."))
    },
  }
}

