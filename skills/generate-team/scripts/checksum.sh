#!/usr/bin/env bash
#
# checksum.sh — canonical design.md checksum (the design↔build hash contract)
# =============================================================================
#
# PURPOSE
#   ONE shared script that both `scripts/approve` (the PRODUCER — freezes the
#   checksum at approval time) and the `build` command (the CONSUMER — verifies
#   the checksum before generating output) call IDENTICALLY. Because both sides
#   run the exact same bytes through the exact same normalization, a *false*
#   mismatch (approve↔build disagreeing on an unchanged spec) is structurally 0.
#   That zero is the invariant this script exists to guarantee (see
#   specs/gated-team-generation/spec.md — its Constraints "체크섬 정규화", §D3,
#   §R3.2, §R4.3). Never hand-roll hashing in approve/build — call this script.
#
# USAGE
#   checksum.sh <path-to-design.md>
#   -> prints the lowercase sha256 hex digest to stdout, and NOTHING else
#      (so callers can capture it with `digest=$(checksum.sh ...)`).
#   On any error: a message on stderr and a non-zero exit; stdout stays empty.
#
# CANONICAL NORMALIZATION  (THIS BLOCK IS THE CONTRACT — see also
# references/checksum-normalization.md):
#   1. Read the file.
#   2. From the YAML frontmatter (the first `---`…`---` block), REMOVE the
#      `checksum:` line and the `status:` line entirely. They are excluded
#      because approve mutates `status` and writes `checksum` at freeze time;
#      hashing them would be self-referential and guarantee a false mismatch.
#   3. Keep EVERYTHING else: the rest of the frontmatter AND the full body.
#   4. Normalize line endings to LF (strip any trailing CR) and strip trailing
#      whitespace on every line.
#   5. Compute sha256 over the resulting normalized bytes.
#
# PORTABILITY
#   Prefers `shasum -a 256` (present on macOS/darwin), falls back to
#   `sha256sum` (Linux). Errors clearly if neither exists.
#
set -euo pipefail

err() { printf '%s\n' "checksum.sh: $*" >&2; }

# --- argument & file validation -------------------------------------------
if [ "$#" -ne 1 ]; then
  err "usage: checksum.sh <path-to-design.md>"
  exit 2
fi

design_path="$1"

if [ ! -e "$design_path" ]; then
  err "file not found: $design_path"
  exit 1
fi
if [ ! -f "$design_path" ]; then
  err "not a regular file: $design_path"
  exit 1
fi
if [ ! -r "$design_path" ]; then
  err "file not readable: $design_path"
  exit 1
fi

# --- pick a sha256 implementation ------------------------------------------
sha256_hex() {
  # Reads bytes from stdin, prints the bare lowercase hex digest.
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    err "no sha256 tool found (need 'shasum' or 'sha256sum')"
    exit 1
  fi
}

# --- normalize then hash ----------------------------------------------------
# Step 2: drop the checksum:/status: lines, but ONLY inside the leading YAML
#         frontmatter (the first `---` … `---` block). Lines outside the
#         frontmatter are never touched, so a body line that happens to start
#         with "status:" is preserved.
# Step 4: strip a trailing CR (\r) and any other trailing whitespace per line.
#         Done INSIDE awk, BEFORE the `---` delimiter compare, so a `--- ` line
#         with a stray trailing space still opens/closes the frontmatter block.
#         Otherwise the block would go undetected, its status:/checksum: lines
#         would stop being excluded, and the digest would shift — a cross-platform
#         false mismatch (exactly the "0 false mismatch" invariant this guards).
#
# awk does the frontmatter-scoped deletion AND the per-line trailing whitespace/CR
# strip; the trailing sed re-applies the strip harmlessly as a safety net. The
# pipeline emits LF-terminated lines (awk/sed both write \n), satisfying LF
# normalization.
normalized="$(
  awk '
    BEGIN { in_fm = 0; fm_done = 0 }
    {
      # strip a trailing CR AND trailing whitespace up front so frontmatter
      # delimiter matching is robust against CRLF files and a stray space after
      # a `---` line.
      line = $0
      sub(/\r$/, "", line)
      sub(/[ \t]*$/, "", line)

      if (NR == 1 && line == "---") { in_fm = 1; print line; next }

      if (in_fm) {
        if (line == "---") { in_fm = 0; fm_done = 1; print line; next }
        # drop the self-referential meta fields inside frontmatter only
        if (line ~ /^[ \t]*checksum[ \t]*:/) next
        if (line ~ /^[ \t]*status[ \t]*:/)   next
        print line; next
      }

      print line
    }
  ' "$design_path" \
  | sed -e 's/[[:space:]]*$//'
)"

# Re-add the trailing newline that command-substitution strips, so the hashed
# bytes are stable and identical between producer and consumer regardless of
# whether the source file ended with a newline.
printf '%s\n' "$normalized" | sha256_hex
