#!/usr/bin/env bash
#
# gate_test.sh — regression suite for the checksum gate (the heart of this plugin)
# =============================================================================
#
# WHAT THIS PROVES
#   The design→approve→build gate rejects unapproved / tampered builds, and does
#   so REPRODUCIBLY (spec `specs/gated-team-generation/spec.md` line 29's completion
#   criterion). Today that reproduction is manual; this suite makes it a test.
#
#   `build` itself is an LLM skill we cannot invoke from a shell, so we assert the
#   OBSERVABLE, SCRIPT-LEVEL signals that build's gate consumes:
#     G1 exists       — specs/<team>/design.md present
#     G2 approved     — frontmatter `status: approved`
#     G3 not tampered — frozen `checksum:` == checksum.sh recomputed on the file
#   Each test below pins one of those signals with the REAL scripts, by path.
#
# WHAT WE TEST (the producer/hasher pair, which are pure shell):
#   skills/generate-team/scripts/approve      — freezes status:+checksum: (PRODUCER)
#   skills/generate-team/scripts/checksum.sh  — the shared canonical hasher
#   skills/generate-team/scripts/validate.sh  — structural validator (POST-FIX;
#                                               tests SKIP gracefully if absent)
#
# TARGET CONTRACT (asserted, not today's behavior — see the two notes below):
#   * approve on a design.md with NO leading `---` frontmatter MUST exit non-zero
#     and MUST NOT print an "Approved" banner. The current (pre-fix) approve
#     mis-reports success here; that ONE case is reported as XFAIL until Agent A's
#     validate.sh is wired into approve. It flips to a real PASS once fixed.
#   * validate.sh <design.md> -> exit 0 (silent stdout) when structurally valid;
#     non-zero + stderr diagnostics when invalid.
#
# RUN
#   bash tests/gate_test.sh          # from the repo root
#   Exits non-zero iff a HARD assertion fails (XFAIL/SKIP do not fail the run).
#
# NOTE ON `set -e`: intentionally NOT enabled — this harness runs scripts that are
# SUPPOSED to fail (approve on bad input, validate on invalid specs) and inspects
# their exit codes. Errors are handled explicitly.

# --- locate the repo + the real scripts (by absolute path) -------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPTS="$REPO_ROOT/skills/generate-team/scripts"
APPROVE="$SCRIPTS/approve"
CHECKSUM="$SCRIPTS/checksum.sh"
VALIDATE="$SCRIPTS/validate.sh"

for req in "$APPROVE" "$CHECKSUM"; do
  if [ ! -x "$req" ]; then
    printf 'BAIL OUT! required script missing or not executable: %s\n' "$req" >&2
    exit 3
  fi
done

# --- isolated, self-cleaning workspace ---------------------------------------
WORK="$(mktemp -d "${TMPDIR:-/tmp}/gate_test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT INT TERM

# --- counters + tiny assert helpers (no external framework) ------------------
PASS=0; FAIL=0; SKIP=0; XFAIL=0

pass()  { PASS=$((PASS+1));   printf 'ok    - %s\n' "$1"; }
skip()  { SKIP=$((SKIP+1));   printf 'SKIP  - %s\n' "$1"; }
xfail() { XFAIL=$((XFAIL+1)); printf 'XFAIL - %s  [%s]\n' "$1" "${2:-expected-fail: pending an upstream script fix}"; }
fail()  {
  FAIL=$((FAIL+1))
  printf 'FAIL  - %s\n' "$1"
  if [ -n "${2:-}" ]; then printf '        %s\n' "$2"; fi
}

section() { printf '\n# %s\n' "$1"; }

assert_eq()        { if [ "$2" = "$3" ];  then pass "$1"; else fail "$1" "expected [$2] got [$3]"; fi; }
assert_ne()        { if [ "$2" != "$3" ]; then pass "$1"; else fail "$1" "expected values to differ, both were [$2]"; fi; }
assert_nonempty()  { if [ -n "$2" ];      then pass "$1"; else fail "$1" "value was empty"; fi; }
assert_empty()     { if [ -z "$2" ];      then pass "$1"; else fail "$1" "value was [$2]"; fi; }
assert_contains()  { case "$3" in *"$2"*) pass "$1";; *) fail "$1" "[$3] does not contain [$2]";; esac; }
assert_absent()    { case "$3" in *"$2"*) fail "$1" "[$3] unexpectedly contains [$2]";; *) pass "$1";; esac; }

# --- extract a frontmatter field value the same way build/approve do ---------
# Frontmatter-scoped (first `---`…`---` block only), CR-tolerant. A body line that
# merely starts with "status:" is never mistaken for the meta field. Prints the
# value (empty if the field/frontmatter is absent).
fm_field() { # $1=file  $2=field(status|checksum)
  awk -v f="$2" '
    BEGIN { in_fm = 0; ln = 0 }
    {
      line = $0; sub(/\r$/, "", line); ln++
      if (ln == 1 && line == "---") { in_fm = 1; next }
      if (in_fm) {
        if (line == "---") { exit }
        if (line ~ ("^[ \t]*" f "[ \t]*:")) {
          v = line
          sub("^[ \t]*" f "[ \t]*:[ \t]*", "", v)
          sub(/[ \t]*$/, "", v)
          print v; exit
        }
      }
    }
  ' "$1"
}

# --- fixture writers ---------------------------------------------------------
# A fully schema-valid design.md (references/design-schema.md): 3-field frontmatter,
# all 8 required `## ` sections in order, every agent has 5 fields, every skill has
# 3 fields, and each skill's owner-agent resolves to a real agent.
write_valid_design() { # $1=dest path
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'DESIGN'
---
team: sample-team
status: draft
checksum:
---

## Purpose

A sample team used to exercise the checksum gate in tests.

## Non-goals

- Does not talk to production — tests must stay hermetic.

## Agents

### builder
- **role**: build things
- **responsibility**: materializes the harness from the approved spec
- **allowed-tools**: Read, Write
- **model**: opus

### reviewer
- **role**: review things
- **responsibility**: verifies the build against the spec
- **allowed-tools**: Read
- **model**: opus

## Skills

### build-skill
- **purpose**: builds the harness when asked, from an approved design
- **owner-agent**: builder

## Execution Mode

sub: subagent fan-out, orchestrated one unit at a time.

## Invariants/Gates

- no agent writes to .claude/ directly
- every build re-verifies the frozen checksum before touching disk

## Escalation Rules

- schema change → escalate to human: autonomy boundary

## File Layout

- `.claude/agents/builder.md` — builder
- `.claude/agents/reviewer.md` — reviewer
- `.claude/skills/build-skill/SKILL.md` — build-skill
- `CLAUDE.md` — harness pointer (trigger rules + change history)
DESIGN
}

# run approve; capture combined output + exit code (no set -e so this can't abort)
run_approve() { # $1=team (relative specs/<team>/design.md, so caller must cd first)
  APPROVE_OUT="$("$APPROVE" "$1" 2>&1)"; APPROVE_RC=$?
}

# =============================================================================
section "1. Freeze — approve sets status:approved + a checksum: equal to checksum.sh"
# =============================================================================
D_FREEZE="$WORK/freeze/specs/sample-team/design.md"
write_valid_design "$D_FREEZE"
cd "$WORK/freeze"
run_approve sample-team

assert_eq       "1a approve exits 0 on a valid spec" 0 "$APPROVE_RC"
assert_contains "1b approve prints the Approved banner" "Approved: sample-team" "$APPROVE_OUT"
assert_eq       "1c frontmatter status is now 'approved'" approved "$(fm_field "$D_FREEZE" status)"
FROZEN="$(fm_field "$D_FREEZE" checksum)"
assert_nonempty "1d frontmatter checksum: is frozen (non-empty)" "$FROZEN"
# The invariant build relies on: the frozen digest == what checksum.sh recomputes.
RECOMPUTED="$("$CHECKSUM" "$D_FREEZE")"
assert_eq       "1e frozen checksum == checksum.sh recomputed on the file" "$FROZEN" "$RECOMPUTED"

# =============================================================================
section "2. Tamper — a body edit breaks the digest; an excluded-line edit does not"
# =============================================================================
D_TAMP="$WORK/tamper/specs/t/design.md"
write_valid_design "$D_TAMP"
cd "$WORK/tamper"
run_approve t
FROZEN_T="$(fm_field "$D_TAMP" checksum)"

# (a) modify a BODY line -> checksum.sh now differs from the frozen value.
#     This is exactly the mismatch build's G3 detects and rejects on.
sed 's/A sample team used/A TAMPERED sample team used/' "$D_TAMP" > "$WORK/tamper/edit.tmp" \
  && mv "$WORK/tamper/edit.tmp" "$D_TAMP"
RECOMP_BODY="$("$CHECKSUM" "$D_TAMP")"
assert_ne "2a body-line edit makes checksum.sh != frozen checksum (G3 mismatch)" "$FROZEN_T" "$RECOMP_BODY"

# (b) counter-case: editing ONLY the excluded status:/checksum: frontmatter lines
#     must NOT change checksum.sh's output (they are excluded from the hash).
D_EXCL="$WORK/excl/specs/e/design.md"
write_valid_design "$D_EXCL"
cd "$WORK/excl"
run_approve e
DIGEST_BEFORE="$("$CHECKSUM" "$D_EXCL")"
sed -e 's/^status: approved/status: draft/' -e 's/^checksum: .*/checksum: deadbeefdeadbeef/' \
  "$D_EXCL" > "$WORK/excl/edit.tmp" && mv "$WORK/excl/edit.tmp" "$D_EXCL"
DIGEST_AFTER="$("$CHECKSUM" "$D_EXCL")"
assert_eq "2b editing only excluded status:/checksum: lines does NOT change the digest" "$DIGEST_BEFORE" "$DIGEST_AFTER"

# =============================================================================
section "3. No-frontmatter edge — approve MUST reject (TARGET contract, bug ②)"
# =============================================================================
# A body-only design.md with NO leading `---` frontmatter. Per the post-fix
# contract, approve must exit non-zero and print NO "Approved" banner. The current
# pre-fix approve silently "succeeds" here (ANALYSIS.md §②), so this is XFAIL now
# and becomes a real PASS once Agent A wires validate.sh into approve.
D_NOFM="$WORK/nofm/specs/nofm/design.md"
mkdir -p "$(dirname "$D_NOFM")"
cat > "$D_NOFM" <<'NOFM'
## Purpose

A design.md that is missing its YAML frontmatter block entirely.

## Agents

### solo
- **role**: does everything
NOFM
cd "$WORK/nofm"
run_approve nofm
if [ "$APPROVE_RC" -ne 0 ] && ! printf '%s' "$APPROVE_OUT" | grep -q "Approved"; then
  pass "3a approve on a no-frontmatter spec is rejected (exit!=0, no Approved banner)"
else
  xfail "3a approve on a no-frontmatter spec should be rejected (got exit=$APPROVE_RC; banner-present=$(printf '%s' "$APPROVE_OUT" | grep -q 'Approved' && echo yes || echo no))" \
        "expected-fail until Agent A wires validate.sh into approve (pre-fix approve mis-reports success on a spec it never stamped)"
fi

# =============================================================================
section "4. Normalization — CRLF + trailing whitespace must NOT false-mismatch"
# =============================================================================
# Two files with IDENTICAL logical content but different on-disk bytes:
#   A: LF endings, no trailing whitespace
#   B: same lines with CRLF endings, plus trailing spaces on the CONTENT lines
# checksum.sh strips trailing CR + trailing whitespace and normalizes to LF, so
# both MUST hash to the same digest. This is what keeps approve (often macOS) and
# build/CI (Linux) from a false checksum mismatch across platforms.
FA="$WORK/norm/a.md"; FB="$WORK/norm/b.md"
mkdir -p "$WORK/norm"
cat > "$FA" <<'NORM'
---
team: norm
status: draft
checksum:
---

## Purpose

A line of content.

## Skills

Another line of content.
NORM
# Build B from A: CRLF on every line; trailing spaces on the CONTENT lines. The
# `---` delimiters get CRLF only — checksum.sh matches the delimiter after CR
# strip, so `---\r` is fine (the trailing-SPACE delimiter corner is 4b below).
awk '{ if ($0 == "---") printf "---\r\n"; else printf "%s   \r\n", $0 }' "$FA" > "$FB"

if cmp -s "$FA" "$FB"; then
  fail "4-pre A and B should differ byte-for-byte (fixture setup sanity)"
else
  pass "4-pre A (LF/clean) and B (CRLF + trailing-ws) differ on disk (fixture sanity)"
fi
DIG_A="$("$CHECKSUM" "$FA")"
DIG_B="$("$CHECKSUM" "$FB")"
assert_eq "4a checksum.sh(LF/clean) == checksum.sh(CRLF + trailing-ws on content) — false-mismatch = 0" "$DIG_A" "$DIG_B"

# 4b — KNOWN GAP (auto-heals if checksum.sh is hardened): trailing whitespace on
# the `---` frontmatter DELIMITER line itself. checksum.sh strips a trailing CR
# before matching `---` but NOT trailing spaces, so a `--- \r` line fails delimiter
# detection, the status:/checksum: lines stop being excluded, and the digest
# changes. That is precisely the cross-platform false-mismatch test 4 exists to
# prevent (an editor/formatter adding a trailing space to a `---` line), so it is
# asserted against the target and flagged XFAIL rather than dropped.
FC="$WORK/norm/c.md"
awk '{ printf "%s   \r\n", $0 }' "$FA" > "$FC"   # trailing spaces on EVERY line incl. ---
DIG_C="$("$CHECKSUM" "$FC")"
if [ "$DIG_A" = "$DIG_C" ]; then
  pass "4b trailing whitespace on a '---' delimiter line also normalizes (checksum.sh hardened)"
else
  xfail "4b trailing whitespace on a '---' delimiter line should still yield the same digest" \
        "checksum.sh gap: strips a trailing CR but not trailing spaces before the '---' frontmatter-delimiter match, so a '--- ' line breaks frontmatter detection"
fi

# =============================================================================
section "5. validate.sh direct — structural validation (POST-FIX; SKIP if absent)"
# =============================================================================
# Contract asserted (Agent A's target):
#   valid spec                     -> exit 0, silent stdout
#   missing a required `## ` section -> non-zero
#   dangling owner-agent           -> non-zero
#   missing frontmatter            -> non-zero  (bonus)
if [ -x "$VALIDATE" ]; then
  # valid
  V_OK="$WORK/val/ok/design.md"; write_valid_design "$V_OK"
  "$VALIDATE" "$V_OK" >/dev/null 2>&1; RC=$?
  assert_eq "5a validate.sh accepts a fully-valid spec (exit 0)" 0 "$RC"

  # missing a required section: drop `## Escalation Rules`
  V_SEC="$WORK/val/sec/design.md"; write_valid_design "$V_SEC"
  awk 'BEGIN{drop=0}
       /^## Escalation Rules/{drop=1; next}
       /^## /{ if(drop) drop=0 }
       { if(!drop) print }' "$V_SEC" > "$WORK/val/sec.tmp" && mv "$WORK/val/sec.tmp" "$V_SEC"
  "$VALIDATE" "$V_SEC" >/dev/null 2>&1; RC=$?
  assert_ne "5b validate.sh rejects a spec missing a required ## section (non-zero)" 0 "$RC"

  # dangling owner-agent: point the skill at an agent that does not exist
  V_REF="$WORK/val/ref/design.md"; write_valid_design "$V_REF"
  sed 's/^- \*\*owner-agent\*\*: builder/- **owner-agent**: ghost-agent/' "$V_REF" \
    > "$WORK/val/ref.tmp" && mv "$WORK/val/ref.tmp" "$V_REF"
  "$VALIDATE" "$V_REF" >/dev/null 2>&1; RC=$?
  assert_ne "5c validate.sh rejects a dangling skill owner-agent (non-zero)" 0 "$RC"

  # bonus: missing frontmatter entirely
  V_FM="$WORK/val/fm/design.md"; mkdir -p "$(dirname "$V_FM")"
  cp "$D_NOFM" "$V_FM"
  "$VALIDATE" "$V_FM" >/dev/null 2>&1; RC=$?
  assert_ne "5d validate.sh rejects a spec with no frontmatter (non-zero)" 0 "$RC"
else
  skip "5a validate.sh accepts a valid spec              (validate.sh not present yet)"
  skip "5b validate.sh rejects a missing ## section      (validate.sh not present yet)"
  skip "5c validate.sh rejects a dangling owner-agent    (validate.sh not present yet)"
  skip "5d validate.sh rejects a missing-frontmatter spec (validate.sh not present yet)"
fi

# =============================================================================
section "6. Gate rejection scenarios — the 3 states build must reject"
# =============================================================================
# build is an LLM skill; we assert the observable SCRIPT-LEVEL signal each state
# maps to. build's LLM gate (G1/G2/G3) consumes exactly these signals:
#   missing  -> no frozen status:/checksum: present   (never approved)
#   draft    -> status: is present but != approved
#   tampered -> frozen checksum: != checksum.sh recomputed

# (missing) frontmatter with team only — no status:/checksum: lines at all.
G_MISS="$WORK/gate/missing/design.md"; mkdir -p "$(dirname "$G_MISS")"
cat > "$G_MISS" <<'MISS'
---
team: missing-team
---

## Purpose

Never run through approve.
MISS
assert_empty  "6a missing: no frozen status: value  -> build G2 has nothing approved" "$(fm_field "$G_MISS" status)"
assert_empty  "6a missing: no frozen checksum: value -> build G3 has no anchor to verify" "$(fm_field "$G_MISS" checksum)"
assert_absent "6a missing: file has no 'status: approved' line" "status: approved" "$(cat "$G_MISS")"

# (draft) status present but not approved.
G_DRAFT="$WORK/gate/draft/design.md"; write_valid_design "$G_DRAFT"   # ships status: draft
assert_eq "6b draft: status is 'draft' (!= approved) -> build G2 rejects" draft "$(fm_field "$G_DRAFT" status)"
assert_ne "6b draft: status != 'approved'"                              approved "$(fm_field "$G_DRAFT" status)"

# (tampered) approved + frozen checksum, but body edited after freeze.
G_TAMP="$WORK/gate/tampered/specs/gt/design.md"; write_valid_design "$G_TAMP"
cd "$WORK/gate/tampered"
run_approve gt
G_FROZEN="$(fm_field "$G_TAMP" checksum)"
sed 's/A sample team used/A SNEAKILY EDITED team used/' "$G_TAMP" > "$WORK/gate/tampered/edit.tmp" \
  && mv "$WORK/gate/tampered/edit.tmp" "$G_TAMP"
assert_eq "6c tampered: status is still 'approved' (so only G3 can catch it)" approved "$(fm_field "$G_TAMP" status)"
assert_ne "6c tampered: frozen checksum != recomputed -> build G3 rejects" "$G_FROZEN" "$("$CHECKSUM" "$G_TAMP")"

# =============================================================================
# summary
# =============================================================================
TOTAL=$((PASS + FAIL + SKIP + XFAIL))
printf '\n'
printf '# ------------------------------------------------------------\n'
printf '# summary: %s checks | %s pass | %s fail | %s skip | %s xfail\n' \
  "$TOTAL" "$PASS" "$FAIL" "$SKIP" "$XFAIL"
if [ "$XFAIL" -gt 0 ]; then
  printf '#   XFAIL = target-contract assertions not yet met by the current scripts\n'
  printf '#           (see the [reason] on each XFAIL line). NOT counted as failures;\n'
  printf '#           each auto-flips to a real PASS once the underlying script is fixed.\n'
fi
if [ "$SKIP" -gt 0 ]; then
  printf '#   SKIP  = validate.sh cases, pending Agent A adding scripts/validate.sh.\n'
fi
printf '# ------------------------------------------------------------\n'

if [ "$FAIL" -gt 0 ]; then
  printf 'RESULT: FAIL\n'
  exit 1
fi
printf 'RESULT: PASS\n'
exit 0
