# lex-trail — anchors, tested against the attacks they exist to defeat.
#
# An anchor is only worth publishing if a holder who edits the log afterwards
# cannot make it reproduce. So the tests are the edits: append, delete, and
# rewrite. A test that only checks "an unchanged log still matches" would pass
# on an anchor that ignored its input entirely.

import "std.io" as io

import "std.str" as str

import "std.int" as int

import "std.list" as list

import "../src/log" as tlog

import "../src/anchor" as anchor

fn assert_true(cond :: Bool, label :: Str) -> Result[Unit, Str] {
  if cond {
    Ok(())
  } else {
    Err(label)
  }
}

fn seeded() -> [sql, fs_write] Result[tlog.Log, Str] {
  match tlog.open_memory() {
    Err(e) => Err(e),
    Ok(log) => {
      let __a := tlog.append_at(log, "meter.reading", None, "{\"wh\":105500}", 1000)
      let __b := tlog.append_at(log, "meter.reading", None, "{\"wh\":111000}", 2000)
      let __c := tlog.append_at(log, "settlement.energy", None, "{\"eur_cents\":1064}", 3000)
      Ok(log)
    },
  }
}

# ---- it reproduces when nothing changed -----------------------------
fn test_an_untouched_log_reproduces_its_anchor() -> [sql, fs_write, crypto] Result[Unit, Str] {
  match seeded() {
    Err(e) => Err(e),
    Ok(log) => match anchor.compute(log, 9999) {
      Err(e) => Err(e),
      Ok(a) => assert_true(anchor.is_match(anchor.verify(log, a)) and a.count == 3, str.concat("an unchanged log must reproduce its anchor over 3 events, counted ", int.to_str(a.count))),
    },
  }
}

# ---- the three attacks ----------------------------------------------
# Appending inside the anchored window is the subtle one: the window is closed,
# so a later event backdated into it must break the anchor even though nothing
# already anchored was touched.
fn test_backdating_an_event_into_the_window_breaks_it() -> [sql, fs_write, crypto] Result[Unit, Str] {
  match seeded() {
    Err(e) => Err(e),
    Ok(log) => match anchor.compute(log, 9999) {
      Err(e) => Err(e),
      Ok(a) => {
        let __x := tlog.append_at(log, "settlement.flex", None, "{\"eur_cents\":48}", 2500)
        assert_true(not anchor.is_match(anchor.verify(log, a)), "an event backdated into an anchored window must break the anchor")
      },
    },
  }
}

# Deletion is the attack a chain's head id cannot see: every surviving id still
# verifies against its parent, and nothing proves the absent event was ever there.
fn test_deleting_an_event_breaks_it() -> [sql, fs_write, crypto] Result[Unit, Str] {
  match seeded() {
    Err(e) => Err(e),
    Ok(log) => match anchor.compute(log, 9999) {
      Err(e) => Err(e),
      Ok(a) => {
        let __d := tlog.xexec(log.db, "DELETE FROM events WHERE ts_ms = ?", [PInt(2000)])
        match anchor.verify(log, a) {
          Match => Err("deleting an anchored event must break the anchor — this is the attack a per-chain head id cannot detect"),
          Diverged(d) => assert_true(d.expected_count == 3 and d.actual_count == 2, str.concat("the verdict must report what changed, got ", int.to_str(d.actual_count))),
        }
      },
    },
  }
}

# The rewrite: edit a payload AND recompute the id so the log is internally
# coherent again. is_valid passes on every event afterwards; the anchor does not.
fn test_a_coherent_rewrite_breaks_it() -> [sql, fs_write, crypto] Result[Unit, Str] {
  match seeded() {
    Err(e) => Err(e),
    Ok(log) => match anchor.compute(log, 9999) {
      Err(e) => Err(e),
      Ok(a) => {
        let __u := tlog.xexec(log.db, "UPDATE events SET payload_json = ?, id = ? WHERE ts_ms = ?", [PStr("{\"eur_cents\":9999}"), PStr("rewritten-but-coherent"), PInt(3000)])
        assert_true(not anchor.is_match(anchor.verify(log, a)), "a rewrite that keeps the log internally coherent must still fail to reproduce the anchor")
      },
    },
  }
}

# ---- the window is a window -----------------------------------------
# An anchor says nothing about what came after it. Stating that in a test so
# nobody later reads a passing anchor as "the log is unchanged".
fn test_events_after_the_window_do_not_affect_it() -> [sql, fs_write, crypto] Result[Unit, Str] {
  match seeded() {
    Err(e) => Err(e),
    Ok(log) => match anchor.compute(log, 3000) {
      Err(e) => Err(e),
      Ok(a) => {
        let __x := tlog.append_at(log, "settlement.flex", None, "{\"eur_cents\":48}", 8000)
        assert_true(anchor.is_match(anchor.verify(log, a)), "an anchor commits to its window only — later events must not break it")
      },
    },
  }
}

# The digest must not depend on the order rows come back in, or an anchor
# taken on SQLite would fail on Postgres for no reason.
fn test_the_digest_is_order_independent() -> [crypto] Result[Unit, Str] {
  assert_true(anchor.digest_of(["c", "a", "b"]) == anchor.digest_of(["a", "b", "c"]), "the digest must not depend on the order the ids arrive in")
}

fn test_different_sets_differ() -> [crypto] Result[Unit, Str] {
  assert_true(not (anchor.digest_of(["a", "b"]) == anchor.digest_of(["a", "b", "c"])), "a different set of ids must produce a different digest")
}

fn results() -> [sql, fs_write, crypto] List[(Str, Result[Unit, Str])] {
  [("an_untouched_log_reproduces_its_anchor", test_an_untouched_log_reproduces_its_anchor()), ("backdating_an_event_into_the_window_breaks_it", test_backdating_an_event_into_the_window_breaks_it()), ("deleting_an_event_breaks_it", test_deleting_an_event_breaks_it()), ("a_coherent_rewrite_breaks_it", test_a_coherent_rewrite_breaks_it()), ("events_after_the_window_do_not_affect_it", test_events_after_the_window_do_not_affect_it()), ("the_digest_is_order_independent", test_the_digest_is_order_independent()), ("different_sets_differ", test_different_sets_differ())]
}

fn report(rs :: List[(Str, Result[Unit, Str])]) -> [io] Int {
  list.fold(rs, 0, fn (n :: Int, r :: (Str, Result[Unit, Str])) -> [io] Int {
    match r {
      (_, Ok(_)) => n,
      (name, Err(why)) => {
        let __p := io.print(str.concat("FAIL ", str.concat(name, str.concat(" — ", why))))
        n + 1
      },
    }
  })
}

# The stdlib is total — there is no `panic` — so a division by zero is the
# raise. `zero` arrives as an argument so it survives constant folding.
fn raise_failure(zero :: Int) -> Int {
  1 / zero
}

fn run_all() -> [io, sql, fs_write, crypto] Unit {
  let failures := report(results())
  if failures == 0 {
    ()
  } else {
    let __p := io.print(str.concat(int.to_str(failures), " test(s) failed"))
    let __boom := raise_failure(0)
    ()
  }
}

