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

import "lex-trail/log"    as log
import "lex-trail/replay" as replay
import "lex-trail/kinds"  as k

import "std.str"  as str
import "std.int"  as int
import "std.list" as list
import "std.io"   as io

fn main() -> [sql, fs_write, time, io] Unit {
  let task_id := "a2a-demo-task-001"
  match log.open_memory() {
    Err(e) => io.print(str.concat("[error] log open failed: ", e)),
    Ok(l)  => run_demo(l, task_id),
  }
}

fn run_demo(l :: log.Log, task_id :: Str) -> [sql, time, io] Unit {
  # Agent A: emit task.sent
  let sent_pay :=
    str.concat("{\"task_id\":\"",
      str.concat(task_id,
        "\",\"to_agent\":\"agent-b\",\"skill\":\"summarize\",\"params\":{}}"))
  let _ := log.append(l, k.a2a_task_sent(), None, sent_pay)

  # Agent B: task.received (chains from sent)
  let recv_root := match log.append(l, k.a2a_task_sent(), None, sent_pay) {
    Ok(ev) => Some(ev.id),
    Err(_) => None,
  }
  let recv_pay :=
    str.concat("{\"task_id\":\"",
      str.concat(task_id,
        "\",\"from_agent\":\"agent-a\",\"skill\":\"summarize\",\"params\":{}}"))
  let _ := log.append(l, k.a2a_task_received(), recv_root, recv_pay)

  # Agent B: cap.invoked
  let cap_pay :=
    str.concat("{\"task_id\":\"",
      str.concat(task_id,
        "\",\"capability\":\"summarize\",\"args\":{},\"agent\":\"agent-b\"}"))
  let _ := log.append(l, k.cap_invoked(), None, cap_pay)

  # Agent B: cap.completed
  let done_pay :=
    str.concat("{\"task_id\":\"",
      str.concat(task_id,
        "\",\"capability\":\"summarize\",\"result\":\"Summary ready.\"}"))
  let _ := log.append(l, k.cap_completed(), None, done_pay)

  # Agent B: task state change
  let state_pay :=
    str.concat("{\"task_id\":\"",
      str.concat(task_id,
        "\",\"from_state\":\"working\",\"to_state\":\"completed\"}"))
  let _ := log.append(l, k.a2a_task_state_change(), None, state_pay)

  # Replay
  let _ := io.print(str.concat("=== Replay: task ", str.concat(task_id, " ===")))
  match replay.task(l, task_id) {
    Err(e)   => io.print(str.concat("[error] replay failed: ", e)),
    Ok(evts) => {
      let _ := list.map(evts, fn (evt :: ev.Event) -> [io] Unit {
        io.print(str.concat("  [",
          str.concat(evt.kind,
            str.concat("] id=",
              str.concat(evt.id,
                str.concat(" ts=", int.to_str(evt.ts_ms)))))))
      })
      io.print(str.concat(int.to_str(list.len(evts)), " events replayed."))
    },
  }
}
