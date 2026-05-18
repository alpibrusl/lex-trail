# lex-trail — Agent Guidelines

Pure-Lex content-addressed event log. Captures the A2A protocol surface
and `lex-llm` agent loop for end-to-end traceability. No Rust — only
Lex source and stdlib (`std.sql`, `std.crypto`, `std.time`).

---

## Core surface

```
log.open_memory()           -> [sql, fs_write] Result[Log, Str]
log.open(path)              -> [sql, fs_write] Result[Log, Str]
log.append(l, kind, parent, payload_json)
                            -> [sql, time]     Result[Event, Str]
log.range(l, from_ms, to_ms)
                            -> [sql]           Result[List[Event], Str]
log.head(l)                 -> [sql]           Option[Event]

attest.add(l, event_id, kind, payload_json)
                            -> [sql, time]     Result[Attestation, Str]
attest.chain(l, event_id)   -> [sql]           Result[List[Attestation], Str]

replay.task(l, task_id)     -> [sql]           Result[List[Event], Str]
replay.walk_chain(l, event_id)
                            -> [sql]           List[Event]
```

---

## Key types

| type | file | purpose |
|---|---|---|
| `Event` | `src/event.lex` | `{ id, kind, parent, payload_json, ts_ms }` — id is SHA-256 content hash |
| `Log` | `src/log.lex` | wraps a `Db` handle with trail schema applied |
| `Attestation` | `src/attest.lex` | `{ id, event_id, kind, payload_json, ts_ms }` |

---

## Standard event kinds

Import `lex-trail/kinds` and call the zero-arg functions instead of raw strings:

| function | kind string |
|---|---|
| `k.a2a_task_received()` | `a2a.task.received` |
| `k.a2a_task_sent()` | `a2a.task.sent` |
| `k.a2a_msg_received()` | `a2a.message.received` |
| `k.a2a_msg_sent()` | `a2a.message.sent` |
| `k.a2a_task_state_change()` | `a2a.task.state_change` |
| `k.cap_invoked()` | `cap.invoked` |
| `k.cap_completed()` | `cap.completed` |
| `k.cap_failed()` | `cap.failed` |
| `k.spec_allowed()` | `spec.allowed` |
| `k.spec_denied()` | `spec.denied` |
| `k.llm_step()` | `llm.step` |
| `k.human_escalated()` | `human.escalated` |
| `k.human_replied()` | `human.replied` |

---

## Effects

| effect | why |
|---|---|
| `[sql]` | every database read/write |
| `[fs_write]` | `sql.open` creates the SQLite file |
| `[time]` | `append` and `attest.add` capture `time.now_ms()` for `ts_ms` |

Callers opening a log must include `[sql, fs_write]`. Callers appending
events must include `[sql, time]`. Read-only operations (`range`, `head`,
`attest.chain`, `replay.task`) need only `[sql]`.

---

## Content-addressing

Every `Event.id` is `crypto.sha256_str(kind + "\x1f" + parent + "\x1f" + payload_json + "\x1f" + ts_ms)`.
The same logical event always produces the same id — two agents that
independently capture the same interaction can cross-verify by comparing ids.

`event.is_valid(evt)` recomputes the id and compares; use it as a
post-fetch integrity check.

---

## Replay

`replay.task(log, task_id)` does a `LIKE` search on `payload_json` for the
task_id string. Payloads must include a top-level `"task_id"` JSON key.
Results are ordered by `ts_ms ASC`.

`replay.walk_chain(log, event_id)` walks the `parent` pointer chain from
any event back to the root, returning events in root-first order.

---

## Running tests

```bash
lex test           # runs tests/test_*.lex
```

Test functions that use `[sql, fs_write, time]` are hermetic: each opens
its own `":memory:"` SQLite database that is discarded when the handle
goes out of scope.

---

## Coding conventions

- `examples {}` blocks on every pure function — they run at `lex check` time.
- Effect signatures are narrow: don't add `[time]` to read-only functions.
- `INSERT OR IGNORE` on events: the content hash is the primary key, so
  duplicate appends (same id) are silently no-ops, not errors.
- User-defined event kinds are welcome; the standard set in `kinds.lex`
  covers the platform surface.
