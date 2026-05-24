# lex-trail — Typed event emitters (the integration surface)
#
# Downstream packages (lex-agent, lex-llm, lex-spec, lex-code) should
# emit trail events through these helpers rather than hand-building
# JSON payloads. Each emitter:
#
#   1. builds the standard payload for its kind (see lex-lang#484), and
#   2. appends exactly one event, returning the appended Event so the
#      caller can use evt.id as the `parent` of the next event.
#
# Scalar string fields are encoded with `json.stringify`, so caller
# input containing quotes or backslashes can no longer corrupt the
# payload (this closes the "no escaping of caller-supplied strings"
# v0.1 limitation). Composite fields (`params`, `parts`, `args`,
# `bindings`, `tool_calls`) are passed through verbatim as JSON
# fragments — the caller is responsible for their validity.
#
# Every standard payload carries a top-level `task_id` so the event is
# discoverable by `replay.task`.
#
# Effects: [sql, time] (delegated to log.append).

import "./log" as l

import "./event" as ev

import "./kinds" as k

import "std.str" as str

import "std.int" as int

import "std.json" as json

# ---- Pure payload builders (tested at `lex check` time) -----------
# Build the {task_id, <agent_field>, skill, params} payload shared by
# a2a.task.received (agent_field = "from_agent") and a2a.task.sent
# (agent_field = "to_agent").
fn payload_task(task_id :: Str, agent_field :: Str, agent :: Str, skill :: Str, params_json :: Str) -> Str
  examples {
    payload_task("t1", "from_agent", "agent-a", "summarize", "{}") => "{\"task_id\":\"t1\",\"from_agent\":\"agent-a\",\"skill\":\"summarize\",\"params\":{}}"
  }
{
  str.join(["{\"task_id\":", json.stringify(task_id), ",", json.stringify(agent_field), ":", json.stringify(agent), ",\"skill\":", json.stringify(skill), ",\"params\":", params_json, "}"], "")
}

# Build the {task_id, message, parts} payload shared by
# a2a.message.received and a2a.message.sent.
fn payload_message(task_id :: Str, message :: Str, parts_json :: Str) -> Str
  examples {
    payload_message("t1", "m1", "[]") => "{\"task_id\":\"t1\",\"message\":\"m1\",\"parts\":[]}"
  }
{
  str.join(["{\"task_id\":", json.stringify(task_id), ",\"message\":", json.stringify(message), ",\"parts\":", parts_json, "}"], "")
}

# Build the {task_id, from_state, to_state} payload for
# a2a.task.state_change.
fn payload_state(task_id :: Str, from_state :: Str, to_state :: Str) -> Str
  examples {
    payload_state("t1", "working", "completed") => "{\"task_id\":\"t1\",\"from_state\":\"working\",\"to_state\":\"completed\"}"
  }
{
  str.join(["{\"task_id\":", json.stringify(task_id), ",\"from_state\":", json.stringify(from_state), ",\"to_state\":", json.stringify(to_state), "}"], "")
}

# Build the {task_id, capability, args, agent} payload for cap.invoked.
fn payload_cap_invoked(task_id :: Str, capability :: Str, args_json :: Str, agent :: Str) -> Str
  examples {
    payload_cap_invoked("t1", "search", "{}", "agent-b") => "{\"task_id\":\"t1\",\"capability\":\"search\",\"args\":{},\"agent\":\"agent-b\"}"
  }
{
  str.join(["{\"task_id\":", json.stringify(task_id), ",\"capability\":", json.stringify(capability), ",\"args\":", args_json, ",\"agent\":", json.stringify(agent), "}"], "")
}

# Build the {task_id, capability, result} payload for cap.completed.
fn payload_cap_completed(task_id :: Str, capability :: Str, result :: Str) -> Str
  examples {
    payload_cap_completed("t1", "search", "done") => "{\"task_id\":\"t1\",\"capability\":\"search\",\"result\":\"done\"}"
  }
{
  str.join(["{\"task_id\":", json.stringify(task_id), ",\"capability\":", json.stringify(capability), ",\"result\":", json.stringify(result), "}"], "")
}

# Build the {task_id, capability, error} payload for cap.failed.
fn payload_cap_failed(task_id :: Str, capability :: Str, error :: Str) -> Str
  examples {
    payload_cap_failed("t1", "search", "timeout") => "{\"task_id\":\"t1\",\"capability\":\"search\",\"error\":\"timeout\"}"
  }
{
  str.join(["{\"task_id\":", json.stringify(task_id), ",\"capability\":", json.stringify(capability), ",\"error\":", json.stringify(error), "}"], "")
}

# Build the {task_id, spec, bindings} payload for spec.allowed.
fn payload_spec_allowed(task_id :: Str, spec :: Str, bindings_json :: Str) -> Str
  examples {
    payload_spec_allowed("t1", "no_pii", "{}") => "{\"task_id\":\"t1\",\"spec\":\"no_pii\",\"bindings\":{}}"
  }
{
  str.join(["{\"task_id\":", json.stringify(task_id), ",\"spec\":", json.stringify(spec), ",\"bindings\":", bindings_json, "}"], "")
}

# Build the {task_id, spec, bindings, reason} payload for spec.denied.
fn payload_spec_denied(task_id :: Str, spec :: Str, bindings_json :: Str, reason :: Str) -> Str
  examples {
    payload_spec_denied("t1", "no_pii", "{}", "ssn detected") => "{\"task_id\":\"t1\",\"spec\":\"no_pii\",\"bindings\":{},\"reason\":\"ssn detected\"}"
  }
{
  str.join(["{\"task_id\":", json.stringify(task_id), ",\"spec\":", json.stringify(spec), ",\"bindings\":", bindings_json, ",\"reason\":", json.stringify(reason), "}"], "")
}

# Build the {task_id, model, tokens_in, tokens_out, tool_calls} payload
# for llm.step.
fn payload_llm_step(task_id :: Str, model :: Str, tokens_in :: Int, tokens_out :: Int, tool_calls_json :: Str) -> Str
  examples {
    payload_llm_step("t1", "lex-mini", 12, 8, "[]") => "{\"task_id\":\"t1\",\"model\":\"lex-mini\",\"tokens_in\":12,\"tokens_out\":8,\"tool_calls\":[]}"
  }
{
  str.join(["{\"task_id\":", json.stringify(task_id), ",\"model\":", json.stringify(model), ",\"tokens_in\":", int.to_str(tokens_in), ",\"tokens_out\":", int.to_str(tokens_out), ",\"tool_calls\":", tool_calls_json, "}"], "")
}

# Build the {task_id, question, context} payload for human.escalated.
fn payload_human_escalated(task_id :: Str, question :: Str, context :: Str) -> Str
  examples {
    payload_human_escalated("t1", "ok to deploy?", "prod") => "{\"task_id\":\"t1\",\"question\":\"ok to deploy?\",\"context\":\"prod\"}"
  }
{
  str.join(["{\"task_id\":", json.stringify(task_id), ",\"question\":", json.stringify(question), ",\"context\":", json.stringify(context), "}"], "")
}

# Build the {task_id, response} payload for human.replied.
fn payload_human_replied(task_id :: Str, response :: Str) -> Str
  examples {
    payload_human_replied("t1", "yes") => "{\"task_id\":\"t1\",\"response\":\"yes\"}"
  }
{
  str.join(["{\"task_id\":", json.stringify(task_id), ",\"response\":", json.stringify(response), "}"], "")
}

# ---- A2A protocol emitters ----------------------------------------
fn a2a_task_received(log :: l.Log, task_id :: Str, from_agent :: Str, skill :: Str, params_json :: Str, parent :: Option[Str]) -> [sql, time] Result[ev.Event, Str] {
  l.append(log, k.a2a_task_received(), parent, payload_task(task_id, "from_agent", from_agent, skill, params_json))
}

fn a2a_task_sent(log :: l.Log, task_id :: Str, to_agent :: Str, skill :: Str, params_json :: Str, parent :: Option[Str]) -> [sql, time] Result[ev.Event, Str] {
  l.append(log, k.a2a_task_sent(), parent, payload_task(task_id, "to_agent", to_agent, skill, params_json))
}

fn a2a_message_received(log :: l.Log, task_id :: Str, message :: Str, parts_json :: Str, parent :: Option[Str]) -> [sql, time] Result[ev.Event, Str] {
  l.append(log, k.a2a_msg_received(), parent, payload_message(task_id, message, parts_json))
}

fn a2a_message_sent(log :: l.Log, task_id :: Str, message :: Str, parts_json :: Str, parent :: Option[Str]) -> [sql, time] Result[ev.Event, Str] {
  l.append(log, k.a2a_msg_sent(), parent, payload_message(task_id, message, parts_json))
}

fn a2a_state_change(log :: l.Log, task_id :: Str, from_state :: Str, to_state :: Str, parent :: Option[Str]) -> [sql, time] Result[ev.Event, Str] {
  l.append(log, k.a2a_task_state_change(), parent, payload_state(task_id, from_state, to_state))
}

# ---- Capability emitters ------------------------------------------
fn cap_invoked(log :: l.Log, task_id :: Str, capability :: Str, args_json :: Str, agent :: Str, parent :: Option[Str]) -> [sql, time] Result[ev.Event, Str] {
  l.append(log, k.cap_invoked(), parent, payload_cap_invoked(task_id, capability, args_json, agent))
}

fn cap_completed(log :: l.Log, task_id :: Str, capability :: Str, result :: Str, parent :: Option[Str]) -> [sql, time] Result[ev.Event, Str] {
  l.append(log, k.cap_completed(), parent, payload_cap_completed(task_id, capability, result))
}

fn cap_failed(log :: l.Log, task_id :: Str, capability :: Str, error :: Str, parent :: Option[Str]) -> [sql, time] Result[ev.Event, Str] {
  l.append(log, k.cap_failed(), parent, payload_cap_failed(task_id, capability, error))
}

# ---- Spec emitters ------------------------------------------------
fn spec_allowed(log :: l.Log, task_id :: Str, spec :: Str, bindings_json :: Str, parent :: Option[Str]) -> [sql, time] Result[ev.Event, Str] {
  l.append(log, k.spec_allowed(), parent, payload_spec_allowed(task_id, spec, bindings_json))
}

fn spec_denied(log :: l.Log, task_id :: Str, spec :: Str, bindings_json :: Str, reason :: Str, parent :: Option[Str]) -> [sql, time] Result[ev.Event, Str] {
  l.append(log, k.spec_denied(), parent, payload_spec_denied(task_id, spec, bindings_json, reason))
}

# ---- LLM agent-loop emitters --------------------------------------
fn llm_step(log :: l.Log, task_id :: Str, model :: Str, tokens_in :: Int, tokens_out :: Int, tool_calls_json :: Str, parent :: Option[Str]) -> [sql, time] Result[ev.Event, Str] {
  l.append(log, k.llm_step(), parent, payload_llm_step(task_id, model, tokens_in, tokens_out, tool_calls_json))
}

fn human_escalated(log :: l.Log, task_id :: Str, question :: Str, context :: Str, parent :: Option[Str]) -> [sql, time] Result[ev.Event, Str] {
  l.append(log, k.human_escalated(), parent, payload_human_escalated(task_id, question, context))
}

fn human_replied(log :: l.Log, task_id :: Str, response :: Str, parent :: Option[Str]) -> [sql, time] Result[ev.Event, Str] {
  l.append(log, k.human_replied(), parent, payload_human_replied(task_id, response))
}

