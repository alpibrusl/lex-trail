# lex-trail

[![CI](https://github.com/alpibrusl/lex-trail/actions/workflows/ci.yml/badge.svg)](https://github.com/alpibrusl/lex-trail/actions/workflows/ci.yml)

**Part of the [Lex](https://lexlang.org) project** — Library · [Manifesto](https://lexlang.org/manifesto) · [All packages](https://lexlang.org)

Content-addressed event log for A2A audit. Captures the A2A protocol
surface (`lex-agent`) and LLM agent loop (`lex-llm`) for end-to-end
traceability across cross-framework agent interactions.

See [lex-lang#484](https://github.com/alpibrusl/lex-lang/issues/484) for the full design.

## Demo — audit chains and session replay

Every agent decision. SHA-256 content-addressed. Deterministically replayable. Tamper-evident.

[![asciicast](https://asciinema.org/a/O19TtmPVF2QHBNUZ.svg)](https://asciinema.org/a/O19TtmPVF2QHBNUZ)

```sh
bash examples/replay_demo.sh
```

Two trading sessions recorded in parallel: one accepted (5 events, spec allowed), one rejected (3 events, spec denied). Chain verification, parent-pointer replay, full JSON audit report — and an explanation of why mutating any byte breaks the sequential SHA-256 hash chain.

---

## Quick start

```lex
import "lex-trail/log"    as log
import "lex-trail/kinds"  as k
import "lex-trail/replay" as replay

fn record_and_replay(task_id :: Str) -> [sql, fs_write, time] Unit {
  match log.open_memory() {
    Err(_) => (),
    Ok(l)  => {
      let pay := str.concat("{\"task_id\":\"", str.concat(task_id, "\",\"skill\":\"translate\"}"))
      let _   := log.append(l, k.a2a_task_received(), None, pay)
      let _   := log.append(l, k.llm_step(), None, str.concat("{\"task_id\":\"", str.concat(task_id, "\",\"tokens_in\":10,\"tokens_out\":5,\"tool_calls\":[]}")))
      match replay.task(l, task_id) {
        Ok(evts) => (),  # evts is the full trace in ts_ms order
        Err(_)   => (),
      }
    },
  }
}
```

## Modules

| module | purpose |
|---|---|
| `lex-trail/event` | `Event` type, `make`, `compute_id`, `is_valid` |
| `lex-trail/kinds` | standard event kind string constants |
| `lex-trail/log` | `Log` type, `open_memory`, `open`, `append`, `range`, `head` |
| `lex-trail/emit` | typed emitters for the standard kinds — the integration surface downstream packages call |
| `lex-trail/attest` | attestation chain: `add`, `chain` |
| `lex-trail/replay` | task replay: `task`, `walk_chain` |
| `lex-trail/export` | JSON audit report: `task_report`, `event_json`, `events_json` |

See [DESIGN.md](DESIGN.md) for the event vocabulary, the
immutability/correlation/retention model, and integration status.

## Backends (v0.1)

- **In-memory**: `log.open_memory()` — ephemeral, scoped to the process lifetime. Ideal for tests and short-lived agent runs.
- **SQLite**: `log.open(path)` — persistent file-backed log. Use a shared path for cross-agent audit.

## Examples

```bash
lex run --allow-effects sql,fs_write,time,io examples/end_to_end.lex main
lex run --allow-effects sql,fs_write,time,io examples/a2a_replay.lex main
lex run --allow-effects sql,fs_write,time,io examples/cross_framework.lex main
```

`end_to_end.lex` is the headline demo: it emits a full task lifecycle
through `emit.*` and prints an integrity-checked JSON audit report.

---

Built under the principles of [Trust Without Comprehension](https://lexlang.org/manifesto).

## License

Copyright (c) 2026 lex-trail contributors.

Licensed under the [EUPL-1.2](LICENSE) — the European Union Public Licence, as used across the `lex-*` ecosystem.
