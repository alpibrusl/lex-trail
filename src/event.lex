# lex-trail — Event type + content-addressed id
#
# Every event's `id` is the SHA-256 hex digest of its canonical content
# string, making the same logical event produce the same id regardless
# of where it is materialized — the basis for content-addressed
# attestation chains and cross-org audit.
#
# Effects: none. All functions are pure.

import "std.str"    as str
import "std.int"    as int
import "std.crypto" as crypto

type Event = {
  id           :: Str,           # SHA-256 hex content hash
  kind         :: Str,
  parent       :: Option[Str],   # predecessor event id; None for chain roots
  payload_json :: Str,
  ts_ms        :: Int,
}

# Compute a deterministic id from an event's content fields.
# Uses ASCII unit-separator (\x1f) as a field delimiter to avoid
# collisions with field values that contain ":".
fn compute_id(
  kind         :: Str,
  parent       :: Option[Str],
  payload_json :: Str,
  ts_ms        :: Int
) -> Str
  examples {
    compute_id("a", None, "{}", 0) == compute_id("a", None, "{}", 0) => true,
    compute_id("a", None, "{}", 0) == compute_id("b", None, "{}", 0) => false,
    compute_id("a", None, "{}", 0) == compute_id("a", Some("p"), "{}", 0) => false,
    compute_id("a", None, "{}", 0) == compute_id("a", None, "{}", 1) => false,
  }
{
  let p := match parent { Some(s) => s, None => "" }
  crypto.sha256_str(
    str.join([kind, p, payload_json, int.to_str(ts_ms)], "\x1f"))
}

# Build an Event with a computed id.
# Callers supply ts_ms from time.now_ms(); this function is pure.
fn make(
  kind         :: Str,
  parent       :: Option[Str],
  payload_json :: Str,
  ts_ms        :: Int
) -> Event
  examples {
    make("llm.step", None, "{}", 0).kind         => "llm.step",
    make("llm.step", None, "{}", 0).parent       => None,
    make("llm.step", None, "{}", 0).payload_json => "{}",
    make("llm.step", None, "{}", 0).ts_ms        => 0,
    make("llm.step", None, "{}", 0).id ==
      make("llm.step", None, "{}", 0).id         => true,
  }
{
  { id:           compute_id(kind, parent, payload_json, ts_ms),
    kind:         kind,
    parent:       parent,
    payload_json: payload_json,
    ts_ms:        ts_ms }
}

# Verify that an event's id matches its content (integrity check).
fn is_valid(evt :: Event) -> Bool
  examples {
    is_valid(make("k", None, "{}", 0)) => true,
  }
{
  evt.id == compute_id(evt.kind, evt.parent, evt.payload_json, evt.ts_ms)
}
