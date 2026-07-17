#!/usr/bin/env bash
#
# section-checksum.sh — canonical checksum of ONE design.md section
# =============================================================================
#
# PURPOSE
#   The per-section analogue of `checksum.sh`. Where `checksum.sh` freezes the
#   WHOLE spec for the approval gate, this freezes a SINGLE source section so
#   `build` can decide, deterministically, whether the artifact that section
#   produced needs regenerating on a re-run (spec D6 / R5.3 / R5.5).
#
#   build STAMPS the digest into each generated artifact as a provenance marker
#     <!-- generated-from: <selector> @ sha256:<digest> -->
#   and, on a re-run, RECOMPUTES it and compares:
#     stored == recomputed  -> the spec section is unchanged      -> PRESERVE
#     stored != recomputed  -> the spec section changed           -> UPDATE
#   This removes the old "does the artifact still match what this section would
#   generate?" test, which — for prose fields (role/responsibility) that build
#   renders with an LLM — was non-deterministic and mis-classified untouched
#   agents as UPDATE. It splits Q1 ("did the SPEC change?", now a deterministic
#   hash) from Q2 ("did the HUMAN edit the artifact?", still preserve-and-warn).
#   See specs/gated-team-generation/spec.md §D6, §R5.3, §R5.5 and
#   skills/team-build/references/merge.md.
#
#   IMPORTANT — this does NOT touch the checksum GATE. The marker lives in the
#   generated .claude/* artifact, never in design.md, so the frozen spec digest
#   (checksum.sh, G3) is unaffected and R5.4 (checksum scope = spec only) holds.
#
# NORMALIZATION IS SHARED, NOT REIMPLEMENTED
#   The extracted section is written verbatim to a temp file and hashed by the
#   SIBLING `checksum.sh` — the exact same script the gate uses. So the section
#   digest runs through byte-for-byte identical LF / trailing-whitespace / CR
#   normalization, and a false mismatch between stamp-time and compare-time is
#   structurally 0, exactly as it is for the whole-spec gate. Never hand-roll
#   hashing here.
#
# USAGE
#   section-checksum.sh <path-to-design.md> <selector>
#     selector:
#       agent:<name>   the `### <name>` block under `## Agents`
#       skill:<name>   the `### <name>` block under `## Skills`
#       orchestrator   `## Execution Mode` + `## Invariants/Gates`
#                      + `## Escalation Rules` (concatenated in that fixed order)
#   -> prints the lowercase sha256 hex digest to stdout, and NOTHING else.
#   On any error (bad usage, file/section not found): message on stderr, non-zero
#   exit, empty stdout — so callers branch on the exit code (mirrors checksum.sh).
#
# PORTABILITY
#   macOS / darwin (BSD) compatible: POSIX awk + mktemp + the shared checksum.sh.
#
set -euo pipefail

err() { printf '%s\n' "section-checksum.sh: $*" >&2; }

# --- resolve sibling checksum.sh by THIS script's own directory --------------
DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKSUM="$DIR/checksum.sh"

# --- argument & file validation ----------------------------------------------
if [ "$#" -ne 2 ]; then
  err "usage: section-checksum.sh <path-to-design.md> <selector>"
  err "  selector: agent:<name> | skill:<name> | orchestrator"
  exit 2
fi

design_path="$1"
selector="$2"

if [ ! -f "$design_path" ]; then
  err "file not found or not a regular file: $design_path"
  exit 1
fi
if [ ! -x "$CHECKSUM" ]; then
  err "sibling checksum.sh not found or not executable: $CHECKSUM"
  exit 1
fi

# --- extract an H3 (`### <name>`) block that lives under a given H2 -----------
# Prints the `### <name>` heading and its body verbatim ($0), up to (not incl.)
# the next H3/H2 or EOF. Matching is CR-robust and strips markdown cosmetics
# (backticks/asterisks) from the name so it compares like validate.sh does.
extract_h3() {
  # $1 = H2 name (e.g. "Agents"), $2 = H3 name (e.g. "reviewer"), $3 = file
  awk -v h2="$1" -v h3="$2" '
    function clean(s) {
      sub(/\r$/, "", s); gsub(/^[[:space:]]+/, "", s); gsub(/[[:space:]]+$/, "", s)
      gsub(/[`*]/, "", s); return s
    }
    BEGIN { in_h2 = 0; in_blk = 0 }
    {
      line = $0; sub(/\r$/, "", line)
      if (line ~ /^##[[:space:]]/) {                 # an H2 boundary (not H3/H4)
        hdr = line; sub(/^##[[:space:]]+/, "", hdr); sub(/[[:space:]]+$/, "", hdr)
        in_h2 = (hdr == h2) ? 1 : 0
        in_blk = 0
        next
      }
      if (in_h2 && line ~ /^###[[:space:]]/) {       # an H3 opens/closes a block
        nm = line; sub(/^###[[:space:]]+/, "", nm)
        in_blk = (clean(nm) == clean(h3)) ? 1 : 0
        if (in_blk) { print $0 }                     # emit the heading verbatim
        next
      }
      if (in_blk) { print $0 }
    }
  ' "$3"
}

# --- extract an H2 (`## <name>`) section body (heading + body, until next H2) -
extract_h2() {
  # $1 = H2 name, $2 = file
  awk -v h2="$1" '
    BEGIN { in_h2 = 0 }
    {
      line = $0; sub(/\r$/, "", line)
      if (line ~ /^##[[:space:]]/) {
        hdr = line; sub(/^##[[:space:]]+/, "", hdr); sub(/[[:space:]]+$/, "", hdr)
        if (hdr == h2) { in_h2 = 1; print $0; next }
        in_h2 = 0; next
      }
      if (in_h2) { print $0 }
    }
  ' "$2"
}

# --- materialize the selected section into a temp file -----------------------
tmp="$(mktemp "${TMPDIR:-/tmp}/section-checksum.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

case "$selector" in
  agent:?*)
    extract_h3 "Agents" "${selector#agent:}" "$design_path" > "$tmp" ;;
  skill:?*)
    extract_h3 "Skills" "${selector#skill:}" "$design_path" > "$tmp" ;;
  orchestrator)
    # fixed canonical order so the digest is independent of section order in file
    {
      extract_h2 "Execution Mode"   "$design_path"
      extract_h2 "Invariants/Gates" "$design_path"
      extract_h2 "Escalation Rules" "$design_path"
    } > "$tmp" ;;
  *)
    err "unknown selector: $selector (want agent:<name> | skill:<name> | orchestrator)"
    exit 2 ;;
esac

# A selector that resolves to nothing (missing agent/skill, or all three
# orchestrator sections absent) is an error — an empty digest would silently
# collide across every missing section.
if [ ! -s "$tmp" ]; then
  err "section not found or empty for selector '$selector' in $design_path"
  exit 1
fi

# --- hash the extracted bytes with the SHARED checksum.sh (identical rules) ---
digest="$("$CHECKSUM" "$tmp")"
if [ -z "$digest" ]; then
  err "checksum.sh produced an empty digest for selector '$selector'"
  exit 1
fi

printf '%s\n' "$digest"
