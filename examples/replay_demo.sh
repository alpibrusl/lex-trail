#!/usr/bin/env bash
# Theatrical demo — lex-trail: content-addressed audit chains for AI agents
# Usage:   bash examples/replay_demo.sh
#          asciinema rec examples/replay_demo.cast -c "bash examples/replay_demo.sh" --overwrite
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE/.."
LEX="${LEX:-lex}"

BOLD=$'\033[1m'; DIM=$'\033[2m'; CYAN=$'\033[36m'
GREEN=$'\033[32m'; BLUE=$'\033[34m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'

slow() { echo "$@" | pv -qL 55; }
pause() { sleep "${1:-1.2}"; }
hr()  { printf '%s' "$DIM"; printf '─%.0s' {1..72}; printf '%s\n' "$RESET"; }
hdr() { echo; hr; echo "  ${BOLD}${CYAN}$*${RESET}"; hr; echo; }
cmd() { echo "${BOLD}${BLUE}\$${RESET}  $*"; pause 0.6; }

# Format the demo output.
# - Add newlines around ─ separator lines
# - Add newlines before event lines (lines starting with two spaces + kind prefix)
# - Add newlines before section headings
# - Pretty-print standalone JSON objects
fmt() {
  python3 -c "
import sys, re, json

raw = sys.stdin.read().strip()

# Newline around HR sequences (─{10,})
text = re.sub(r'(─{10,})', lambda m: '\n' + m.group(0) + '\n', raw)

# Newline before section headings (lines starting with two spaces + capital word)
text = re.sub(r'  (Session [12])', r'\n  \1', text)
text = re.sub(r'  (Replaying|Starting|walk_chain)', r'\n  \1', text)
text = re.sub(r'  (Full audit)', r'\n  \1', text)
text = re.sub(r'  (Same content|Mutate|verify_chain|Delete|No trust)', r'\n  \1', text)

# Newline before event kind lines
text = re.sub(r'  (a2a\.|spec\.|cap\.|llm\.)', r'\n  \1', text)

# Newline before replay index lines
text = re.sub(r'  (\[\d+\] )', r'\n  \1', text)

# Newline before verify_chain result lines
text = re.sub(r'  (Session [12]: verify_chain)', r'\n  \1', text)

# Separate adjacent JSON objects
text = re.sub(r'\}(\{)', r'}\n\1', text)

# Strip trailing 'null' (Unit return value)
text = re.sub(r'\s*null\s*$', '', text)

# Pretty-print standalone JSON objects/arrays
out = []
for line in text.split('\n'):
    s = line.strip()
    if (s.startswith('{') and s.endswith('}')) or (s.startswith('[') and s.endswith(']')):
        try:
            out.append(json.dumps(json.loads(s), indent=2))
            continue
        except Exception:
            pass
    out.append(line)
print('\n'.join(out))
"
}

clear
echo
echo "  ${BOLD}lex-trail${RESET}  ·  Content-addressed audit chains for AI agents"
echo "  ${DIM}Every decision. SHA-256 content-addressed. Deterministically replayable. Tamper-evident.${RESET}"
echo
sleep 2

# ── What we're showing ───────────────────────────────────────────────────────
hdr "Two trading sessions — one accepted, one rejected"
slow "  Session 1 — ORD-001  qty=100  : 5 events, policy allowed, order accepted."
slow "  Session 2 — ORD-BAD  qty=5000 : 3 events, spec denied — qty exceeds limit."
slow "  Each event gets a SHA-256 content-addressed id and a parent pointer."
slow "  verify_chain walks every seq+hash link. Any mutation breaks the chain."
echo
pause 1.2

# ── Type check ───────────────────────────────────────────────────────────────
hdr "Type check — all effects declared before a byte runs"
cmd "lex check examples/replay_demo.lex"
pause 0.4
"$LEX" check examples/replay_demo.lex
echo "${GREEN}${BOLD}✓  ok${RESET}"
echo
pause 1.2

# ── Run the demo ─────────────────────────────────────────────────────────────
hdr "End to end — record, verify, replay, audit, tamper detection"
slow "  Zero LLM calls. The trail API is exercised directly."
echo
pause 0.8

cmd "lex run --allow-effects fs_write,io,sql,time \\"
echo "        examples/replay_demo.lex main"
pause 0.5
"$LEX" run --allow-effects fs_write,io,sql,time \
  examples/replay_demo.lex main 2>&1 | fmt
echo
pause 1.5

# ── Summary ──────────────────────────────────────────────────────────────────
hr
echo
echo "  ${BOLD}${GREEN}DONE${RESET}"
echo
echo "  Session 1: ORD-001 — 5-event chain, qty=100 accepted, SHA-256 ids linked by parent."
echo "  Session 2: ORD-BAD — 3-event chain, qty=5000 denied by spec, cap.failed recorded."
echo "  verify_chain: walks seq+hash pairs — Ok(5) and Ok(3), both intact."
echo "  walk_chain:   follows parent pointers from leaf to root — full causal replay."
echo "  task_report:  JSON audit export, all_valid=true, every payload visible."
echo "  Tamper detect: mutate a byte → SHA-256 mismatch; delete a row → seq gap."
echo
hr
echo
