# Idempotent re-run merge (build on an existing harness)

The algorithm behind **Phase 0-M** of `team-build/SKILL.md`. When `build` runs and
a prior `.claude/` harness already exists for `<team>`, build must **merge**, not
overwrite (spec D6 / R5.3 / R5.5). This file is the detailed mechanism; SKILL.md
holds the summary and the decision table.

The gate (Phase G) and schema validation (Phase 0) have already passed before any
of this runs. The spec is authorized and well-formed. Merge only decides, per
artifact, **create / regenerate / preserve** — and, on structural drift, **correct
toward the spec**.

---

## Why merge instead of overwrite

The checksum gate covers the **spec only** (R5.4) — it deliberately does *not*
hash the generated `.claude/*` output. That is the whole reason this merge step
exists: artifacts are *meant* to be human-editable. A human may hand-tune an
agent's prompt or a skill's body after build. A blind re-render would silently
destroy that work, and the gate would never catch it (it only watches the spec).

So drift between the approved spec and the on-disk output is **expected and
allowed**. Merge is the mechanism that reconciles that drift on a re-run —
correcting *structure* to the spec while *preserving* human body edits. The gate
guarantees "build ran from the approved design"; merge guarantees "we did not
clobber the human's edits to do it".

---

## Step 1 — detect first-build vs. re-run

After Phase 0 has parsed the approved spec into the build plan, audit the CWD the
same way generate-team Phase 0 does (read `.claude/agents/`, `.claude/skills/`,
`CLAUDE.md`):

- **No prior harness** (agent/skill dirs absent or empty, no `CLAUDE.md` harness
  pointer) → this is a **clean first build**. Skip the rest of this file; generate
  fresh via Phases 3–5 as SKILL.md already describes.
- **Prior harness present** → this is a **re-run**. Continue with the merge below.

There is no separate "team vs. extend vs. maintenance" choice here — build's input
is a single approved spec, so the spec *is* the desired end-state. Merge's job is
to move the existing harness to that end-state with the least destruction.

---

## Step 2 — the change-detection key

"Regenerate only what changed" needs a deterministic key that says, per agent and
per skill, whether the spec section that produced it has changed since the last
build. The key is a **section-level comparison**, on two axes:

### 2a. File Layout — the set of artifacts that should exist

Parse `## File Layout` from the spec into the canonical set of paths build owns:
one `.claude/agents/<name>.md` per `## Agents` entry, one
`.claude/skills/<name>/SKILL.md` per `## Skills` entry, and `CLAUDE.md`. Diff that
set against what is actually on disk:

| Spec File Layout | On disk | Classification |
|------------------|---------|----------------|
| present | absent | **CREATE** — spec adds it, generate fresh |
| present | present | candidate for **UPDATE or PRESERVE** (decided in 2b) |
| absent | present | **EXTRA** — output diverged; handle per precedence (Step 4) |

### 2b. Per-section change detection (the regenerate-vs-preserve key)

For each artifact that is **present in both** spec and disk, decide whether its
*source section* changed. The comparison key is the corresponding spec section
rendered to its canonical generated form, compared against the artifact's
**structural** content on disk:

- **Agent** `<name>` → its block in `## Agents` (the 5 fields: name, role,
  responsibility, allowed-tools, model). Compare those fields against the agent
  file's declared structure (its tool grant, declared role/responsibility, model).
- **Skill** `<name>` → its block in `## Skills` (name, purpose, owner-agent) plus
  whether its declared path in `## File Layout` still matches.
- **Orchestrator / CLAUDE.md** → `## Execution Mode` + `## Invariants/Gates` +
  `## Escalation Rules`.

Result per artifact:

- **section unchanged** → **PRESERVE**: do not touch the file. (This is the common
  case on a re-run where the human only edited one agent's spec block.)
- **section changed** → **UPDATE**: regenerate *this* artifact's structure from the
  new spec section — and *only* this one. Do not regenerate artifacts whose
  sections did not change.

> The key is intentionally **section-granular**, not file-granular or
> harness-granular. Changing one agent's allowed-tools in the spec re-renders that
> one agent, not the whole team. This is the literal reading of D6's "regenerate
> only the agents/skills whose corresponding spec section changed".

There is no stored prior-spec snapshot to diff against; the on-disk artifact *is*
the record of the last build. So "did the section change?" is answered by asking
"does the on-disk artifact's structure still match what this spec section would
generate?" — if yes, it is unchanged (PRESERVE); if no, regenerate the structure
(UPDATE), applying the body rule in Step 3.

---

## Step 3 — structure vs. body precedence (R5.5)

When an artifact is classified UPDATE (or its structure has drifted from the
spec), split the reconciliation into two layers with **different** rules. This is
the heart of R5.5.

### STRUCTURE → SPEC WINS (correct to match the spec)

Structure = the machine-checkable shape the spec dictates:

- **which** agents and skills exist (the File Layout set),
- each agent's **allowed-tools** grant and **model**,
- each skill's **owner-agent** wiring,
- the orchestrator's **execution mode**.

On any structural divergence, **the spec is the source of truth** — correct the
artifact so its structure matches the approved spec. The human approved this
structure; the gate proved it; drift in structure is an error to fix, not an edit
to keep. Concretely: if the spec grants an agent `Read, Grep` but the on-disk file
declares `Read, Grep, Bash`, rewrite the tool grant to the spec's `Read, Grep`.
If the spec's File Layout no longer lists a skill, that skill is structurally
absent from the desired end-state (see Step 4).

### BODY → PRESERVE-AND-WARN (keep the human's edits, surface them)

Body = the prose a human hand-edited *inside* an agent or skill `.md` that the
spec does not dictate field-by-field: a tuned system-prompt paragraph, an added
operating-principle, an expanded skill workflow, extra examples.

On body divergence, **preserve the human's edits** — do not overwrite them with a
fresh render — **but surface the divergence as a warning** so the human knows the
output no longer matches a clean rendering of the spec. The warning is the point:
silent preservation hides drift; silent overwrite destroys work. Preserve-and-warn
does neither.

When an artifact is UPDATE and has *both* a changed structural section *and* a
human-edited body: apply the structural correction (spec wins) **in place**,
keeping the surrounding human body intact, and emit the body-divergence warning.
Do not regenerate the whole file from scratch — that would discard the body. Edit
the structural fields (frontmatter tool grant, declared model, owner-agent) and
leave human prose alone.

> Mnemonic: **spec owns the skeleton, human owns the flesh.** Skeleton mismatches
> are corrected to the spec; flesh edits are kept and reported.

---

## Step 4 — handling EXTRA artifacts (on disk, not in spec)

An artifact present on disk but **absent from the spec's File Layout** is output
that diverged from the approved spec. Per R5.5 this is a *structure* question
(which artifacts exist) — but the bias is **non-destructive**:

- **Do NOT delete it.** Build never wholesale-overwrites or prunes the human's
  harness (D6). The human may have added it deliberately, or it may be a leftover
  from a prior spec version.
- **Warn.** Surface it: "`<path>` exists on disk but is not in the approved spec's
  File Layout. It was left untouched. If it should be removed, delete it manually
  or add/remove it from the spec and re-approve."

The exception is a *moved/renamed* artifact: if the spec renamed an agent/skill
(old name in File Layout last build, new name now), build CREATEs the new one and
warns about the stale old one rather than deleting it. The human decides.

---

## Step 5 — CLAUDE.md change history on a re-run

`CLAUDE.md` is a harness pointer, not an artifact list, so it is rarely
"regenerated". On a re-run:

- **PRESERVE** the existing trigger rules and the whole change-history table.
- **APPEND** one change-history row describing this re-run, e.g.
  `<today> | Re-build from re-approved spec | <changed agents/skills> | spec update`.
- If `## Execution Mode` / `## Invariants/Gates` / `## Escalation Rules` changed
  such that the trigger rule or orchestrator pointer must change, correct **that
  pointer** (structure → spec wins) but keep the history.

Never rewrite the change-history table — it is an append-only audit trail and a
human-owned body.

---

## Step 6 — report (what merge must tell the user)

After merging, report the per-artifact disposition so the re-run is auditable:

- **Created:** spec items that were absent on disk.
- **Updated:** artifacts whose spec section changed (structure corrected to spec).
- **Preserved:** artifacts left untouched (section unchanged).
- **Warnings:**
  - body divergences preserved (human edits kept; output ≠ clean spec render),
  - EXTRA artifacts on disk not in the spec (left in place),
  - any renamed/stale artifacts.

Close by restating the R5.4 scope note: the checksum gate covered the **spec**;
the `.claude/*` output is intentionally *not* checksum-verified, which is exactly
why this merge preserved human body edits instead of overwriting them.
