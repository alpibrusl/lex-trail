#!/usr/bin/env python3
"""Independent implementation of the lex-trail wire format, in another language.

The point is not that Python is useful here — it is that the format can be
implemented from SPEC.md alone, by someone who cannot run Lex. If this file and
the Lex implementation ever disagree, the format is not a format and the
"anyone can verify" claim is false.

Run in CI against spec/vectors.json, which is generated from the Lex side.

    python3 spec/verify_vectors.py spec/vectors.json
"""
import hashlib
import json
import sys


def event_id(kind: str, parent: str, payload_json: str, ts_ms: int) -> str:
    """SHA-256 of four fields joined by one NUL byte. See SPEC.md §1.

    NUL, not space — and the anchor digest below uses space, not NUL. The two
    differ for no reason beyond how they were written, which is precisely why
    the format needed writing down.
    """
    joined = "\0".join([kind, parent, payload_json, str(ts_ms)])
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()


def anchor_digest(ids: list[str]) -> str:
    """SHA-256 over the ids sorted as byte strings, space-joined. SPEC.md §3."""
    joined = " ".join(sorted(ids))
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()


def main(path: str) -> int:
    doc = json.loads(open(path, encoding="utf-8").read())
    failures = []

    for v in doc["events"]:
        got = event_id(v["kind"], v["parent"], v["payload_json"], v["ts_ms"])
        if got != v["id"]:
            failures.append(f"event {v['kind']!r}: expected {v['id']}, computed {got}")

    for v in doc["anchors"]:
        got = anchor_digest(v["ids"])
        if got != v["digest"]:
            failures.append(f"anchor {v['ids']}: expected {v['digest']}, computed {got}")

    n = len(doc["events"]) + len(doc["anchors"])
    if failures:
        print(f"FAIL {len(failures)} of {n} vectors did not reproduce:")
        for f in failures:
            print(f"  {f}")
        return 1
    print(f"ok  {n} vectors reproduced by an independent implementation")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "spec/vectors.json"))
