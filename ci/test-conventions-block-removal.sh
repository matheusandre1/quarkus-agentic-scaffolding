#!/usr/bin/env bash
# Fixture test for the managed-block removal procedure published in README.md's
# "Uninstall" section.
#
# A one-liner that deletes a region of the user's own CLAUDE.md does not validate by
# reading. The earlier design used `sed -i` with a count-based precheck; three inputs
# passed that precheck and still destroyed user-authored lines (see the spec, Finding 1).
# Every one of those inputs is a fixture here.
#
# Two properties are asserted:
#   1. The precheck says OK-SAFE-TO-REMOVE only for one complete, in-order marker pair.
#   2. On every input the precheck REFUSES, running the removal anyway leaves the file
#      byte-for-byte identical - so a user who ignores the precheck is still safe.
#
# Plus a drift guard: README.md must still publish these exact commands.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

BEGIN_MARKER='<!-- BEGIN quarkus-agentic-scaffolding conventions (managed block; do not edit inside. Re-run /setup-agentic-scaffolding to update.) -->'
END_MARKER='<!-- END quarkus-agentic-scaffolding conventions -->'

# --- The two published commands, defined once. ---------------------------------
AWK_PROG='/^<!-- BEGIN quarkus-agentic-scaffolding conventions/{b++;bl=NR}
     /^<!-- END quarkus-agentic-scaffolding conventions/{e++;el=NR}
     END{printf "BEGIN=%d END=%d beginLine=%d endLine=%d -> %s\n", b,e,bl,el,
         (b==1 && e==1 && bl<el) ? "OK-SAFE-TO-REMOVE" : "REFUSE - remove the block by hand"}'
PERL_SUB='s/^<!-- BEGIN quarkus-agentic-scaffolding conventions.*?^<!-- END quarkus-agentic-scaffolding conventions -->[ \t]*\r?\n?//msg'

precheck()     { awk "$AWK_PROG" "$1"; }
remove_block() { perl -i -0777 -pe "$PERL_SUB" "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0
pass() { echo "ok: $1"; }
fail() { echo "FAIL: $1" >&2; failures=$((failures + 1)); }

expect_verdict() { # expect_verdict <file> <OK-SAFE-TO-REMOVE|REFUSE> <label>
  local got
  got="$(precheck "$1")"
  if [[ "$got" == *"$2"* ]]; then
    pass "$3: precheck -> $2"
  else
    fail "$3: precheck expected $2, got: $got"
  fi
}
assert_unchanged() { # assert_unchanged <file> <saved-copy> <label>
  if cmp -s "$1" "$2"; then
    pass "$3: byte-for-byte unchanged"
  else
    fail "$3: THE FILE WAS MODIFIED - this is the bug the fixture exists to catch"
    diff -u "$2" "$1" >&2 || true
  fi
}
assert_has()  { if grep -Fq "$2" "$1"; then pass "$3"; else fail "$3"; fi; }
assert_lacks() { if grep -Fq "$2" "$1"; then fail "$3"; else pass "$3"; fi; }

mk_block() { # mk_block <file> - append a well-formed managed block
  {
    printf '%s\n' "$BEGIN_MARKER"
    printf '\n# Quarkus + LangChain4j + AI Stack - Project Conventions\n\nrule one\nrule two\n\n'
    printf '%s\n' "$END_MARKER"
  } >>"$1"
}

# ============================================================================
# Group A - a complete, in-order pair: precheck passes and the block goes away
# ============================================================================

# A1: user content on both sides of the block.
f="$TMP/a1.md"
printf '# My own notes\n\nKEEP-ONE\n\n' >"$f"
mk_block "$f"
printf '\n## More of mine\n\nKEEP-TWO\n' >>"$f"
expect_verdict "$f" 'OK-SAFE-TO-REMOVE' 'A1 well-formed'
remove_block "$f"
assert_has  "$f" 'KEEP-ONE' 'A1: user content before the block survives'
assert_has  "$f" 'KEEP-TWO' 'A1: user content after the block survives'
assert_lacks "$f" 'BEGIN quarkus-agentic-scaffolding' 'A1: BEGIN marker gone'
assert_lacks "$f" 'END quarkus-agentic-scaffolding'   'A1: END marker gone'
assert_lacks "$f" 'rule one' 'A1: block body gone'

# A2: nothing but the block - reduces to exactly 0 bytes.
f="$TMP/a2.md"
: >"$f"
mk_block "$f"
expect_verdict "$f" 'OK-SAFE-TO-REMOVE' 'A2 only-the-block'
remove_block "$f"
if [[ ! -s "$f" ]]; then
  pass "A2: file is empty, so the documented \`rm\` step applies"
else
  fail "A2: expected 0 bytes, got $(wc -c <"$f") - contents: $(cat "$f")"
fi

# A3: a blank line on each side - leaves whitespace only, which is why the documented
# test is `grep -q '[^[:space:]]'` and not `[ -s ]`.
f="$TMP/a3.md"
printf '\n' >"$f"
mk_block "$f"
printf '\n' >>"$f"
expect_verdict "$f" 'OK-SAFE-TO-REMOVE' 'A3 blank-line padded'
remove_block "$f"
if [[ -s "$f" ]] && ! grep -q '[^[:space:]]' "$f"; then
  pass 'A3: non-empty but whitespace-only, and the published grep test catches it'
else
  fail "A3: expected a whitespace-only non-empty file, got $(wc -c <"$f") bytes"
fi

# A4: CRLF line endings - this is what the \r? in the regex is for.
f="$TMP/a4.md"
{
  printf 'KEEP-CRLF\r\n\r\n'
  printf '%s\r\n' "$BEGIN_MARKER"
  printf 'rule one\r\n'
  printf '%s\r\n' "$END_MARKER"
  printf '\r\nTAIL-CRLF\r\n'
} >"$f"
expect_verdict "$f" 'OK-SAFE-TO-REMOVE' 'A4 CRLF'
remove_block "$f"
assert_has   "$f" 'KEEP-CRLF' 'A4: user content survives'
assert_has   "$f" 'TAIL-CRLF' 'A4: trailing user content survives'
assert_lacks "$f" 'BEGIN quarkus-agentic-scaffolding' 'A4: block removed despite CRLF'

# A5: the END marker is the last line, with no trailing newline - what the \n? is for.
f="$TMP/a5.md"
printf 'KEEP-NONL\n\n%s\nrule one\n%s' "$BEGIN_MARKER" "$END_MARKER" >"$f"
expect_verdict "$f" 'OK-SAFE-TO-REMOVE' 'A5 no trailing newline'
remove_block "$f"
assert_has   "$f" 'KEEP-NONL' 'A5: user content survives'
assert_lacks "$f" 'END quarkus-agentic-scaffolding' 'A5: block removed without a final newline'

# ============================================================================
# Group B - malformed: precheck REFUSES, and the removal is a no-op anyway.
# Every one of these was destroyed by the `sed` procedure this replaced.
# ============================================================================

run_group_b() { # run_group_b <label> <file>
  local label="$1" f="$2" saved="$2.orig"
  cp "$f" "$saved"
  expect_verdict "$f" 'REFUSE' "$label"
  remove_block "$f"
  assert_unchanged "$f" "$saved" "$label"
}

# B1: BEGIN with no END. `sed` deleted from BEGIN to end of file.
f="$TMP/b1.md"
printf 'KEEP\n\n%s\nrule one\n\nMORE-OF-MINE\n' "$BEGIN_MARKER" >"$f"
run_group_b 'B1 BEGIN with no END' "$f"

# B2: a stray END on its own.
f="$TMP/b2.md"
printf 'KEEP\n\n%s\n\nMORE-OF-MINE\n' "$END_MARKER" >"$f"
run_group_b 'B2 stray END' "$f"

# B3: END before BEGIN. Passes even a strict BEGIN==1 && END==1 check - only the
# line-number comparison catches it. `sed` ran the range to end of file.
f="$TMP/b3.md"
printf 'KEEP\n\n%s\n\nMIDDLE-OF-MINE\n\n%s\n\nTAIL-OF-MINE\n' "$END_MARKER" "$BEGIN_MARKER" >"$f"
run_group_b 'B3 out-of-order markers' "$f"

# B4: both markers on one line. `grep -c` counted 1; `sed` never tested the closing
# regex against the line it opened on, so the range ran to end of file.
f="$TMP/b4.md"
printf 'KEEP\n\n%s filler %s\n\nMORE-OF-MINE\n' "$BEGIN_MARKER" "$END_MARKER" >"$f"
run_group_b 'B4 both markers on one line' "$f"

# B5: the user writes *about* the markers, mid-sentence. `grep -c` counted 2 and `sed`
# opened a range on the prose.
f="$TMP/b5.md"
printf "KEEP\n\nThe \`%s\` and \`%s\` pair delimits generated text.\n\nMORE-OF-MINE\n" \
  "$BEGIN_MARKER" "$END_MARKER" >"$f"
run_group_b 'B5 prose mention of both markers' "$f"

# B6: prose mention of BEGIN plus a real END at column 0.
f="$TMP/b6.md"
printf "KEEP\n\nI removed the \`%s\` line by hand.\n\n%s\n\nMORE-OF-MINE\n" \
  "$BEGIN_MARKER" "$END_MARKER" >"$f"
run_group_b 'B6 prose BEGIN plus a real END' "$f"

# ============================================================================
# Group C - two complete blocks. The precheck refuses on count, deliberately, so a
# human eyeballs a duplicated block. The removal is NOT run: perl's /g would happily
# remove both, which is safe content-wise but is not what the published procedure does.
# ============================================================================
f="$TMP/c1.md"
printf 'KEEP\n\n' >"$f"
mk_block "$f"
printf '\nMIDDLE-OF-MINE\n\n' >>"$f"
mk_block "$f"
expect_verdict "$f" 'REFUSE' 'C1 two complete blocks'

# ============================================================================
# Group D - the documented residual. Both markers quoted at column 0 inside a fenced
# code block, with no real block present, is indistinguishable from the real thing.
# This fixture pins the known-imperfect behavior rather than pretending it is absent;
# the damage is bounded to the quoted region instead of running to end of file, and the
# published warning tells the user to read the diff before trusting it.
# ============================================================================
f="$TMP/d1.md"
{
  printf 'KEEP-BEFORE\n\nHere is what the block looks like:\n\n```markdown\n'
  printf '%s\n' "$BEGIN_MARKER"
  printf 'quoted example\n'
  printf '%s\n' "$END_MARKER"
  printf '```\n\nKEEP-AFTER\n'
} >"$f"
expect_verdict "$f" 'OK-SAFE-TO-REMOVE' 'D1 fenced quote (KNOWN false positive)'
remove_block "$f"
assert_has "$f" 'KEEP-BEFORE' 'D1: content outside the fence survives'
assert_has "$f" 'KEEP-AFTER'  'D1: content after the fence survives'
if grep -Fq 'quoted example' "$f"; then
  fail 'D1: unexpected - the quoted region survived; re-check the spec residual note'
else
  pass 'D1: the quoted region was removed (documented residual, damage bounded to it)'
fi

# ============================================================================
# Drift guard - README.md must publish these exact commands.
# ============================================================================
if grep -Fq "perl -i -0777 -pe '$PERL_SUB'" README.md; then
  pass 'README publishes the validated perl command verbatim'
else
  fail 'README no longer publishes the validated perl command - it drifted from this test'
fi
for frag in 'b++;bl=NR' 'e++;el=NR' 'b==1 && e==1 && bl<el' 'OK-SAFE-TO-REMOVE' \
            "grep -q '[^[:space:]]'"; do
  if grep -Fq "$frag" README.md; then
    pass "README still carries the precheck fragment: $frag"
  else
    fail "README lost the precheck fragment: $frag"
  fi
done
if grep -Eq "sed -i.*(BEGIN|END) quarkus-agentic-scaffolding" README.md; then
  fail 'README publishes a sed -i procedure for the managed block - see spec Finding 1'
else
  pass 'README publishes no sed -i procedure for the managed block'
fi
if grep -Eq 'npx skills remove (-g )?--all|skills remove --all' README.md; then
  fail "README publishes \`npx skills remove --all\` - it removes unrelated skills"
else
  pass "README does not publish \`npx skills remove --all\`"
fi

if [[ "$failures" == 0 ]]; then
  echo 'OK: managed-block removal is safe on all 13 fixtures, and README matches'
else
  echo "FAIL: $failures assertion(s) failed" >&2
  exit 1
fi
