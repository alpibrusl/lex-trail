# lex-trail example — Cross-framework trace: Python A2A client → Lex server
#
# Simulates the server-side view of a Python A2A client sending a task to a
# Lex agent. The server-side event log captures the full interaction for
# cross-org audit. Payloads are written as inline JSON strings to show the
# schema without requiring the full A2A SDK.
#
# Events captured:
#   a2a.task.received  — task arrives from Python client
#   llm.step           — LLM inference step
#   a2a.message.sent   — response sent back
#   a2a.task.state_change — task completes
# Plus one attestation on the received event recording the origin framework.
#
# Run:
#   lex run --allow-effects sql,fs_write,time,io examples/cross_framework.lex main

import "lex-trail/log" as log

import "lex-trail/attest" as att

import "lex-trail/replay" as replay

import "lex-trail/kinds" as k

import "lex-trail/event" as ev

import "std.str" as str

import "std.int" as int

import "std.list" as list

import "std.io" as io

fn main() -> [sql, fs_write, time, io] Unit {
  let task_id := "cross-fw-task-001"
  match log.open_memory() {
    Err(e) => io.print(str.concat("[error] log open failed: ", e)),
    Ok(l) => run_demo(l, task_id),
  }
}

fn run_demo(l :: log.Log, task_id :: Str) -> [sql, time, io] Unit {
  let recv_pay := str.concat("{\"task_id\":\"", str.concat(task_id, "\",\"from_agent\":\"python-agent\",\"skill\":\"translate\",\"params\":{\"text\":\"Hello\"}}"))
  let recv_evt_opt := match log.append(l, k.a2a_task_received(), None, recv_pay) {
    Ok(evt) => Some(evt),
    Err(e) => {
      let __lex_discard_1 := io.print(str.concat("[warn] recv append failed: ", e))
      None
    },
  }
  let llm_pay := str.concat("{\"task_id\":\"", str.concat(task_id, "\",\"model\":\"lex-mini\",\"tokens_in\":12,\"tokens_out\":8,\"tool_calls\":[]}"))
  let __lex_discard_2 := log.append(l, k.llm_step(), None, llm_pay)
  let msg_pay := str.concat("{\"task_id\":\"", str.concat(task_id, "\",\"message\":\"Hola\",\"parts\":[{\"type\":\"text\",\"text\":\"Hola\"}]}"))
  let __lex_discard_3 := log.append(l, k.a2a_msg_sent(), None, msg_pay)
  let state_pay := str.concat("{\"task_id\":\"", str.concat(task_id, "\",\"from_state\":\"working\",\"to_state\":\"completed\"}"))
  let __lex_discard_4 := log.append(l, k.a2a_task_state_change(), None, state_pay)
  let __lex_discard_5 := match recv_evt_opt {
    None => (),
    Some(evt) => {
      let attest_pay := "{\"framework\":\"python-a2a\",\"version\":\"1.0\"}"
      let __lex_discard_6 := att.add(l, evt.id, "origin.verified", attest_pay)
      ()
    },
  }
  let __lex_discard_7 := io.print("=== Cross-framework trace ===")
  match replay.task(l, task_id) {
    Err(e) => io.print(str.concat("[error] replay failed: ", e)),
    Ok(evts) => {
      let __lex_discard_8 := list.map(evts, fn (evt :: ev.Event) -> [io] Unit {
        io.print(str.concat("  [", str.concat(evt.kind, str.concat("] id=", str.concat(evt.id, str.concat(" ts=", int.to_str(evt.ts_ms)))))))
      })
      io.print(str.concat(int.to_str(list.len(evts)), " events total."))
    },
  }
}

