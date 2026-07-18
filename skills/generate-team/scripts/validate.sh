#!/usr/bin/env bash
#
# validate.sh — structural validator for a design.md (the SHARED shape check)
# =============================================================================
#
# PURPOSE
#   ONE shared structural validator that both `scripts/approve` (the PRODUCER —
#   which now refuses to FREEZE a malformed spec) and the `build` command (the
#   CONSUMER — which re-asserts shape after its checksum gate) call IDENTICALLY.
#   It answers a single question: "is this design.md well-FORMED per the schema?"
#   — independent of the checksum gate, which only proves AUTHORITY, not shape.
#
#   Before this existed, `approve` counted agents/skills but did NOT check
#   structure, so a malformed spec (missing sections, an agent missing a required
#   field, a skill whose owner-agent dangles) could be frozen as "approved" and
#   the error would only surface later, at build's LLM phase — the opposite of
#   fail-fast. Running this on the PRODUCER side makes the gate reject bad shape
#   at freeze time; running it on the CONSUMER side asserts shape deterministically
#   (not just via build's LLM checklist).
#
# WHAT "STRUCTURALLY VALID" MEANS  (derived from — and kept in lockstep with —
# references/design-schema.md; this is the machine form of that schema's
# "Validation checklist"):
#   (a) a leading YAML frontmatter block exists  (first line `---` … closing `---`);
#   (b) every REQUIRED `## ` section is present  (the 8 sections from the schema's
#       "Body sections" list — see REQUIRED_SECTIONS below);
#   (c) every agent (`### ` under `## Agents`) carries all its required fields
#       (schema §3: role, responsibility, allowed-tools, model; the agent `name`
#       IS the `### ` header text);
#   (d) referential integrity (spec R2.4): every skill's `owner-agent` names an
#       agent that actually exists in `## Agents`. A dangling owner-agent is an
#       error. (Skill required fields per schema §4: purpose, owner-agent; the
#       skill `name` IS the `### ` header text.)
#
# USAGE
#   validate.sh <path-to-design.md>
#
# CONTRACT (approve and the build/test side depend on this EXACT interface):
#   - Exit 0 and print NOTHING on stdout          -> spec is structurally valid.
#   - Exit non-zero and print human-readable
#     diagnostics on stderr                        -> invalid. EVERY problem found
#       is listed (the validator does NOT stop at the first), one per line.
#   - Exit 2 (usage) / exit 1 (file error or invalid spec), mirroring checksum.sh.
#   stdout is reserved for the (empty) success case, so callers can branch on the
#   exit code without parsing output — exactly like checksum.sh keeps stdout clean.
#
# PARSING
#   Frontmatter- and section-scoped, consistent with how `approve`/`checksum.sh`
#   parse: awk tracks the leading `---`…`---` block, an H2 (`^## `) opens a
#   section, an H3 (`^### `) opens an agent/skill, and every line is CRLF-robust
#   (a trailing CR is stripped up front). Kept in awk so the three scripts read
#   the file the same way.
#
# PORTABILITY
#   macOS / darwin (BSD) compatible: POSIX awk + sed only, no GNU-isms, no
#   `sed -i`. Resolves nothing external — it only reads the passed-in file.
#
set -euo pipefail

err() { printf '%s\n' "validate.sh: $*" >&2; }

# --- argument & file validation --------------------------------------------
if [ "$#" -ne 1 ]; then
  err "usage: validate.sh <path-to-design.md>"
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

# --- run the structural checks (all in one frontmatter/section-scoped awk) ---
# The awk program prints ONE diagnostic line per problem to its stdout (captured
# below) and prints nothing when the spec is valid. It never calls exit itself,
# so `set -e` does not abort on a "spec invalid" result — validity is decided by
# the shell from whether any diagnostics were produced.
#
# NOTE — the literal lists below are the machine form of the design↔build
# contract that ALSO lives in two other places:
#   * scripts/approve            (SECTION_AGENTS / SECTION_SKILLS vars)
#   * references/design-schema.md ("Body sections" + the §3/§4 field tables)
#   * assets/design-template.md   (the fillable instance)
# If a section or field is renamed, all THREE must change together. This check
# asserts the required sections EXIST, so a rename fails LOUDLY here (and at
# approve time) instead of silently zeroing approve's counters.
problems="$(
  awk '
    BEGIN {
      in_fm = 0; fm_seen = 0; fm_closed = 0
      cur_h2 = ""
      na = 0; ns = 0
      cur_a = 0; cur_s = 0

      # required agent fields (schema §3 Agents table) — "name" is the ### header
      naf = split("role responsibility allowed-tools model", AF, " ")
      # required skill fields (schema §4 Skills table) — "name" is the ### header
      nsf = split("purpose owner-agent", SF, " ")
      # required H2 sections (schema "Body sections"), pipe-separated because the
      # names themselves contain spaces / slashes
      nreq = split("Purpose|Non-goals|Agents|Skills|Execution Mode|Invariants/Gates|Escalation Rules|File Layout", REQ, "|")
    }

    # trim whitespace + strip cosmetic markdown (backticks / bold asterisks) so
    # an agent name and a skill owner-agent value compare cleanly.
    function clean(s) {
      sub(/\r$/, "", s)
      gsub(/^[[:space:]]+/, "", s)
      gsub(/[[:space:]]+$/, "", s)
      gsub(/[`*]/, "", s)
      return s
    }

    {
      line = $0
      sub(/\r$/, "", line)          # CRLF-robust: strip a trailing CR up front
      sub(/[ \t]*$/, "", line)      # tolerate a stray space after `---`/headings

      # --- leading YAML frontmatter block ---
      if (NR == 1 && line == "---") { in_fm = 1; fm_seen = 1; next }
      if (in_fm) {
        if (line == "---") { in_fm = 0; fm_closed = 1 }
        next   # frontmatter body is not scanned for sections/agents/skills
      }

      # --- H2 opens a section (^## , exactly two #, matching approve/checksum) ---
      if (line ~ /^##[[:space:]]/) {
        h = line
        sub(/^##[[:space:]]+/, "", h)
        sub(/[[:space:]]+$/, "", h)
        cur_h2 = h
        seen_sec[h] = 1
        cur_a = 0; cur_s = 0   # a new H2 ends any open agent/skill block
        next
      }

      # --- H3 opens an agent or a skill, depending on the current H2 ---
      if (line ~ /^###[[:space:]]/) {
        nm = line
        sub(/^###[[:space:]]+/, "", nm)
        nm = clean(nm)
        if (cur_h2 == "Agents") {
          na++
          aname[na] = nm
          aline[na] = NR
          cur_a = na; cur_s = 0
          if (nm != "") agentset[nm] = 1
          for (i = 1; i <= naf; i++) afield[na, AF[i]] = 0
        } else if (cur_h2 == "Skills") {
          ns++
          sname[ns] = nm
          sline[ns] = NR
          cur_s = ns; cur_a = 0
          sownerpresent[ns] = 0
          sowner[ns] = ""
          for (i = 1; i <= nsf; i++) sfld[ns, SF[i]] = 0
        } else {
          cur_a = 0; cur_s = 0
        }
        next
      }

      # --- field bullets inside the current agent/skill block ---
      # field form (schema/template): "- **field**: value" (bullet + bold both
      # optional to be lenient; anchored at line start so a value mentioning
      # another field name mid-line cannot false-match).
      if (cur_h2 == "Agents" && cur_a > 0) {
        for (i = 1; i <= naf; i++) {
          f = AF[i]
          re = "^[[:space:]]*[-*]?[[:space:]]*[*]*" f "[*]*[[:space:]]*:"
          if (line ~ re) afield[cur_a, f] = 1
        }
      } else if (cur_h2 == "Skills" && cur_s > 0) {
        for (i = 1; i <= nsf; i++) {
          f = SF[i]
          re = "^[[:space:]]*[-*]?[[:space:]]*[*]*" f "[*]*[[:space:]]*:"
          if (line ~ re) {
            sfld[cur_s, f] = 1
            if (f == "owner-agent") {
              sownerpresent[cur_s] = 1
              v = line
              sub(/^[^:]*:/, "", v)   # everything after the first colon
              sowner[cur_s] = clean(v)
            }
          }
        }
      }
    }

    END {
      # (a) leading frontmatter block
      if (!fm_seen) {
        print "frontmatter: missing leading YAML frontmatter block (first line must be \"---\")"
      } else if (!fm_closed) {
        print "frontmatter: leading YAML frontmatter block is not closed (missing closing \"---\")"
      }

      # (b) every required H2 section present
      for (i = 1; i <= nreq; i++) {
        s = REQ[i]
        if (!(s in seen_sec)) {
          print "section: required section \"## " s "\" is missing"
        }
      }

      # (c) every agent carries all required fields (name = ### header)
      for (a = 1; a <= na; a++) {
        disp = (aname[a] != "") ? ("\"" aname[a] "\"") : ("(unnamed, line " aline[a] ")")
        if (aname[a] == "") {
          print "agent " disp ": missing name (the \"### \" header text is empty)"
        }
        for (i = 1; i <= naf; i++) {
          f = AF[i]
          if (!afield[a, f]) print "agent " disp ": missing required field \"" f "\""
        }
      }

      # (d) skill required fields + referential integrity (R2.4)
      for (s = 1; s <= ns; s++) {
        disp = (sname[s] != "") ? ("\"" sname[s] "\"") : ("(unnamed, line " sline[s] ")")
        if (sname[s] == "") {
          print "skill " disp ": missing name (the \"### \" header text is empty)"
        }
        for (i = 1; i <= nsf; i++) {
          f = SF[i]
          if (!sfld[s, f]) print "skill " disp ": missing required field \"" f "\""
        }
        # referential integrity only makes sense once owner-agent is present:
        if (sownerpresent[s]) {
          if (sowner[s] == "") {
            print "skill " disp ": owner-agent is empty (must name an agent in ## Agents)"
          } else if (!(sowner[s] in agentset)) {
            print "skill " disp ": owner-agent \"" sowner[s] "\" does not match any agent in ## Agents (dangling reference, R2.4)"
          }
        }
      }
    }
  ' "$design_path"
)"

# --- verdict: empty problems => valid; otherwise list every problem on stderr -
if [ -n "$problems" ]; then
  err "spec is not structurally valid: $design_path"
  printf '%s\n' "$problems" | sed 's/^/  - /' >&2
  exit 1
fi

exit 0
