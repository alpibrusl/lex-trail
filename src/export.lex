# lex-trail — JSON export / audit report
#
# Turns the raw event log into a human-inspectable JSON document. This
# is the read side of the trust model: a human (or an external auditor)
# can take a task_id and get back the full, integrity-checked trace
# without touching SQLite directly.
#
# Each exported event carries a `valid` flag (event.is_valid recomputes
# the content hash), and each task report carries an `all_valid`
# summary, so tampering surfaces in the export itself.
#
# Effects: pure builders carry none; `task_report` is [sql] (it
# replays from the log).

import "./event" as ev

import "./log" as l

import "./replay" as replay

import "std.str" as str

import "std.int" as int

import "std.list" as list

import "std.json" as json

# Render a Bool as its JSON literal.
fn bool_str(b :: Bool) -> Str
  examples {
    bool_str(true) => "true",
    bool_str(false) => "false"
  }
{
  if b {
    "true"
  } else {
    "false"
  }
}

# Serialize a single event to a JSON object. `payload` is embedded as a
# raw JSON value (it is already JSON); `parent` becomes a string or
# null; `valid` reports the content-hash integrity check.
fn event_json(evt :: ev.Event) -> Str
  examples {
    event_json({ id: "abc", kind: "llm.step", parent: None, payload_json: "{}", ts_ms: 5 }) => "{\"id\":\"abc\",\"kind\":\"llm.step\",\"parent\":null,\"payload\":{},\"ts_ms\":5,\"valid\":false}"
  }
{
  let parent_json := match evt.parent {
    Some(p) => json.stringify(p),
    None => "null",
  }
  str.join(["{\"id\":", json.stringify(evt.id), ",\"kind\":", json.stringify(evt.kind), ",\"parent\":", parent_json, ",\"payload\":", evt.payload_json, ",\"ts_ms\":", int.to_str(evt.ts_ms), ",\"valid\":", bool_str(ev.is_valid(evt)), "}"], "")
}

# Serialize a list of events to a JSON array.
fn events_json(evts :: List[ev.Event]) -> Str
  examples {
    events_json([]) => "[]"
  }
{
  let items := list.map(evts, fn (e :: ev.Event) -> Str {
    event_json(e)
  })
  str.concat("[", str.concat(str.join(items, ","), "]"))
}

# True iff every event's content hash still matches its content.
fn all_valid(evts :: List[ev.Event]) -> Bool
  examples {
    all_valid([]) => true
  }
{
  list.fold(evts, true, fn (acc :: Bool, e :: ev.Event) -> Bool {
    acc and ev.is_valid(e)
  })
}

# Replay a task and render it as a JSON audit report:
#   { task_id, event_count, all_valid, events: [...] }
# Events are ordered oldest-first (replay.task orders by ts_ms ASC).
fn task_report(log :: l.Log, task_id :: Str) -> [sql] Result[Str, Str] {
  match replay.task(log, task_id) {
    Err(e) => Err(e),
    Ok(evts) => Ok(str.join(["{\"task_id\":", json.stringify(task_id), ",\"event_count\":", int.to_str(list.len(evts)), ",\"all_valid\":", bool_str(all_valid(evts)), ",\"events\":", events_json(evts), "}"], "")),
  }
}

