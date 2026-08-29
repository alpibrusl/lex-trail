# lex-trail — anchors: a commitment you can publish where you cannot rewrite it.
#
# An event's id is the hash of its content INCLUDING its parent's id, so a
# chain's head already commits to everything above it: alter an ancestor and
# every id below changes. That is enough when the party holding the log is not
# the party you need to distrust.
#
# It is not enough when someone else holds the log — a hosted service, a
# counterparty's system. Two attacks survive it:
#
#   deletion    nothing in a chain proves the ABSENCE of a sibling. Drop a
#               whole chain, or an event nobody kept the id of, and every
#               remaining id still verifies.
#   rewrite     recompute every id consistently after an edit and the log is
#               internally coherent again. is_valid passes on all of it.
#
# Both are defeated the same way: commit to the whole log at a moment in time,
# and publish that commitment somewhere the log's holder does not control — the
# counterparty's own system, a timestamping authority, anywhere with its own
# record. Afterwards the holder can still change the data, but not without the
# anchor failing to reproduce.
#
# `digest_of` sorts by id rather than timestamp: two engines may order equal
# timestamps differently, and an anchor that depended on storage order would
# fail for reasons nobody tampered with.
#
# What an anchor does NOT give you: it says nothing about events appended after
# `up_to_ms`, and it cannot tell you WHICH event changed — only that the set is
# no longer the one you were shown. Finding the difference is what `export` and
# a retained copy are for.

import "std.str" as str

import "std.int" as int

import "std.list" as list

import "std.crypto" as crypto

import "./log" as l

import "./event" as ev

# A commitment to every event at or before `up_to_ms`. Small on purpose: this
# is meant to be copied into somebody else's system, printed in a report, or
# e-mailed to a counterparty.
type Anchor = { up_to_ms :: Int, count :: Int, digest :: Str }

# Whether a log still reproduces an anchor. The counts travel with the verdict
# because "you have three fewer events than when I last looked" is a more
# actionable answer than "the digest differs".
type Verdict = Match | Diverged({ expected_count :: Int, actual_count :: Int, expected_digest :: Str, actual_digest :: Str })

fn digest_of(ids :: List[Str]) -> [crypto] Str {
  crypto.sha256_str(str.join(list.sort_by(ids, fn (s :: Str) -> Str {
    s
  }), " "))
}

fn ids_of(events :: List[ev.Event]) -> List[Str] {
  list.map(events, fn (e :: ev.Event) -> Str {
    e.id
  })
}

# Commit to everything at or before `up_to_ms`.
fn compute(log :: l.Log, up_to_ms :: Int) -> [sql, crypto] Result[Anchor, Str] {
  match l.range(log, 0, up_to_ms) {
    Err(e) => Err(e),
    Ok(events) => {
      let ids := ids_of(events)
      Ok({ up_to_ms: up_to_ms, count: list.len(ids), digest: digest_of(ids) })
    },
  }
}

# Recompute the same window and compare. A holder who deleted, added or edited
# anything at or before `up_to_ms` cannot make this reproduce.
fn verify(log :: l.Log, a :: Anchor) -> [sql, crypto] Verdict {
  match compute(log, a.up_to_ms) {
    Err(_) => Diverged({ expected_count: a.count, actual_count: 0 - 1, expected_digest: a.digest, actual_digest: "" }),
    Ok(now) => if now.digest == a.digest and now.count == a.count {
      Match
    } else {
      Diverged({ expected_count: a.count, actual_count: now.count, expected_digest: a.digest, actual_digest: now.digest })
    },
  }
}

fn is_match(v :: Verdict) -> Bool {
  match v {
    Match => true,
    Diverged(_) => false,
  }
}

fn to_json(a :: Anchor) -> Str {
  str.join(["{\"up_to_ms\":", int.to_str(a.up_to_ms), ",\"count\":", int.to_str(a.count), ",\"digest\":\"", a.digest, "\"}"], "")
}

