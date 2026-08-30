# lex-trail wire format

Everything a second implementation needs in order to compute the same event ids
and the same anchor digests as this one, in any language.

**Why this document exists.** The chain's central claim is that a counterparty
can verify an id without trusting whoever produced it. Until this file existed
that was only true if they ran *this* implementation — the format lived in Lex
source and nowhere else, which quietly turns "anyone can check" into "anyone can
check by running our code". A format defined by one implementation is not a
format.

Test vectors are in [`spec/vectors.json`](spec/vectors.json). An implementation
that reproduces them is compatible; one that does not is not, whatever it
otherwise does. [`spec/verify_vectors.py`](spec/verify_vectors.py) is an
independent implementation in another language, run in CI against the same
vectors, so this document cannot drift away from the code.

## 1. Event id

An event's id is the SHA-256, lowercase hex, of four fields joined by a single
**NUL byte (`0x00`)**, in this order:

```
kind ␀ parent ␀ payload_json ␀ ts_ms
```

| field | encoding |
|---|---|
| `kind` | the string as given, UTF-8, no escaping or normalisation |
| `parent` | the parent's id, or **the empty string** when the event is a root |
| `payload_json` | the payload **as a string**, byte-for-byte as stored |
| `ts_ms` | milliseconds since the Unix epoch, rendered in **base-10 with no padding, sign, or separators** |

Hash the UTF-8 bytes of the joined string. Render as 64 lowercase hex
characters.

```
id = hex( sha256( utf8( kind + "\0" + parent + "\0" + payload_json + "\0" + str(ts_ms) ) ) )
```

### What this format does and does not promise

`payload_json` is hashed **as text, not as JSON**. Two payloads that a JSON
parser would call equal — differing only in key order or whitespace — produce
**different ids**. This is deliberate: the chain commits to the bytes a
producer actually wrote, not to a re-serialisation that a verifier chose. It
does mean a producer must not reformat a payload between computing an id and
storing it, and that a caller sending a JSON *value* to an API (rather than a
string) is trusting that API's canonicalisation.

Fields are **not** length-prefixed or escaped; the NUL separator carries that
weight. NUL cannot appear in a JSON document and does not appear in the dotted
identifiers used as kinds, so in practice the fields cannot be re-split
ambiguously — but an implementation accepting arbitrary input should reject a
`kind` or `payload_json` containing `0x00` rather than rely on that.

**Note the two separators are different.** Event ids join with NUL; anchor
digests (§3) join with a single ASCII space. There is no principle behind the
difference — it is how the two were written — and this document records it
because an implementation that assumes one separator throughout will reproduce
half the vectors and fail the rest. That is exactly what happened while this
file was being drafted.

## 2. Verifying an event

An event is internally valid when its stored id equals the id recomputed from
its own fields. This detects a payload edited in place; it does **not** detect a
deletion, nor a rewrite where every id was recomputed consistently. Anchors
address those.

## 3. Anchor digest

An anchor commits to a set of events at or before a timestamp:

```json
{ "up_to_ms": 1788016591481, "count": 3, "digest": "a312c6ad…" }
```

- take the id of every event whose `ts_ms` ≤ `up_to_ms`
- **sort the ids as byte strings, ascending** — not by timestamp, and not in
  storage order
- join with a single ASCII space (`0x20`) — **not** the NUL used for event ids
- SHA-256, lowercase hex

```
digest = hex( sha256( utf8( " ".join(sorted(ids)) ) ) )
count  = number of ids
```

Sorting by id rather than by time is what makes an anchor reproducible across
storage engines: two databases may return equal timestamps in different orders,
and an anchor that depended on that would fail for reasons nobody tampered with.

`count` travels beside the digest because "you have three fewer events than
when I last looked" is a more actionable answer to a mismatch than "the digest
differs".

### Limits

An anchor says nothing about events after `up_to_ms`, and cannot identify
*which* event changed — only that the set is no longer the one that was
committed to. An anchor left in the database it commits to is worth nothing;
its value comes entirely from being held somewhere its subject cannot reach.
