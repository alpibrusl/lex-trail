# lex-trail — Design

Companion to [lex-lang#484](https://github.com/alpibrusl/lex-lang/issues/484).
This document records the v0.1 design decisions the implementation
actually makes. Where a question from #484 is deferred, it says so.

## Why this exists

The trust pitch of the Lex agent platform is: *a human does not have to
read every line of agent-generated code, because the platform records
what the code did.* lex-trail is that record — an append-only,
content-addressed event log of the A2A protocol surface and the LLM
agent loop, replayable per task.

## What is captured

The standard event vocabulary (stable schemas, all keyed by a top-level
`task_id` so they are replayable):

| Kind | Source | Payload |
|---|---|---|
| `a2a.task.received` | lex-agent server | `{task_id, from_agent, skill, params}` |
| `a2a.task.sent` | lex-agent client | `{task_id, to_agent, skill, params}` |
| `a2a.message.received` / `.sent` | lex-agent | `{task_id, message, parts}` |
| `a2a.task.state_change` | lex-agent | `{task_id, from_state, to_state}` |
| `cap.invoked` | lex-agent / lex-llm | `{task_id, capability, args, agent}` |
| `cap.completed` | lex-agent / lex-llm | `{task_id, capability, result}` |
| `cap.failed` | lex-agent / lex-llm | `{task_id, capability, error}` |
| `spec.allowed` | lex-spec | `{task_id, spec, bindings}` |
| `spec.denied` | lex-spec | `{task_id, spec, bindings, reason}` |
| `llm.step` | lex-llm | `{task_id, model, tokens_in, tokens_out, tool_calls}` |
| `human.escalated` | lex-llm | `{task_id, question, context}` |
| `human.replied` | lex-llm | `{task_id, response}` |

`src/kinds.lex` owns the kind strings; `src/emit.lex` owns the payload
shapes. Downstream code emits through `emit.*` rather than hand-building
JSON, which is how the schemas above stay stable. User-defined kinds are
welcome via `log.append` directly.

> Note: #484's payload table omits `task_id` from the `cap.*`, `spec.*`,
> `llm.*`, and `human.*` rows. We include it in every standard payload
> on purpose — without it those events are invisible to `replay.task`,
> which is the whole point of the log. This is a superset, not a
> conflict, with #484.

## Immutability / append-only guarantee

- **Content addressing.** `Event.id = sha256(kind ⏎ parent ⏎ payload ⏎ ts_ms)`
  (fields joined by a separator). The id *is* the integrity check:
  `event.is_valid(evt)` recomputes the hash and compares. Any mutation
  of a stored field is detectable, and the same logical event computed
  by two independent agents produces the same id (cross-org
  cross-verification).
- **Append-only at the storage layer.** Writes are
  `INSERT OR IGNORE` on the content-hash primary key. There is no
  `UPDATE` and no `DELETE` path in the surface; re-appending an
  identical event is an idempotent no-op rather than an error.
- **Durability.** The file-backed backend (`log.open(path)`) is plain
  SQLite: each `append` is its own auto-committed transaction, so a
  crash after a returned `Ok` cannot lose that event. `tests/test_persist.lex`
  pins this — events written through one handle are readable and still
  `is_valid` through a freshly opened handle on the same path.
- **What is *not* guaranteed in v0.1.** Cryptographic signing of entries
  and tamper-*evidence* across the whole chain (a Merkle head) are
  deferred. `is_valid` detects per-event mutation; it does not yet
  detect deletion of an interior event. Signing/federation/encryption
  are explicitly out of scope per #484.

## Correlation across agent hops

Two complementary mechanisms:

1. **`task_id`** is the cross-agent correlation key. Every standard
   payload carries it, and `replay.task(log, task_id)` reconstructs the
   full trace across every agent that shared the log — independent of
   which framework emitted each event.
2. **`parent`** is the intra-trace causal pointer (predecessor event
   id). `replay.walk_chain(log, event_id)` walks it root-first. The
   `emit.*` helpers return the appended `Event` precisely so a caller
   can thread `evt.id` into the next event's `parent` (see
   `examples/end_to_end.lex`).

W3C `traceparent` (from lex-log) is carried *inside* payloads rather
than as a schema column, so trace propagation does not change the event
content-hash contract. A future minor version may promote it to a
first-class indexed field.

## Retention and query model

- **Query.** `log.range(from_ms, to_ms)` (time window), `log.head()`
  (latest), `replay.task(task_id)` (per-task trace, ts-ordered),
  `replay.walk_chain(event_id)` (causal chain), and `attest.chain(event_id)`
  (attestations for an event).
- **Export.** `export.task_report(log, task_id)` renders a task as a
  single integrity-checked JSON document (`{task_id, event_count,
  all_valid, events:[...]}`) suitable for handing to a human or an
  external auditor. `export.event_json` / `export.events_json` serialize
  individual events.
- **Retention.** v0.1 keeps everything; the log is the system of record.
  Time-window pruning is a deployment concern (delete rows below a
  `ts_ms` cutoff out-of-band) and is intentionally not in the surface,
  because deletion is in tension with the append-only guarantee above.

## Integration status

`emit.*` is the in-tree integration surface. Wiring the *other* repos to
call it (lex-agent on every protocol method, lex-llm on every loop step,
lex-spec on every evaluation, `lex blame` cross-referencing trail events
with SigId attestations) lives in those repos and is tracked under #484
— this repository ships the API and the schemas they target, plus an
end-to-end example that exercises the whole vocabulary.
