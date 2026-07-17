---
name: team-build
description: "Consumer side of the gated team-generation flow. Hard-gates an APPROVED specs/<team>/design.md (exists → status: approved → checksum matches), then materializes the harness (.claude/agents/, .claude/skills/, CLAUDE.md) from the spec ONLY — no interview, no re-questioning. Use when: (1) 'build team', 'build harness', 'build from spec', 'generate from approved design', '빌드', '스펙으로 생성'; (2) materializing a design.md that has already been approved by scripts/approve; (3) re-running build after re-approving an edited spec. Rejects with guidance when the spec is missing, not approved, or was modified after approval."
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
---

# team-build — Gated Harness Builder (consumer)

The **build** half of the gated 2-command flow (`design` → `approve` → `build`).
It does NOT interview. It reads one approved spec and turns it into a harness.

Two responsibilities, strictly ordered:

1. **GATE** — prove the spec is authorized to be built. If any check fails, stop
   and print guidance. **Generate nothing.** (R4.1–R4.4)
2. **GENERATE** — read only the approved spec's sections and materialize the
   declared file layout. No interview. (R5.1, R5.2)

The argument is `<team>`. The spec lives at `specs/<team>/design.md`.

> **Why a gate, not a flag.** The whole value of the flow is "review cost
> O(output) → O(design)". A human reviews and freezes the design; build refuses
> to run on anything the human did not approve, or on a design that was changed
> after approval. The gate is a machine invariant, not a courtesy check — see
> spec D2.

---

## Phase G: Gate (run FIRST — hard-reject = stop, generate nothing)

`PLUGIN=${CLAUDE_PLUGIN_ROOT}` (the harness-factory plugin root). `SPEC` =
`specs/<team>/design.md` relative to the user's CWD. Run the three checks in
order; the **first** failure stops the command. On any reject: print the message,
do NOT touch the filesystem, do NOT continue to Phase 0.

### G1 — spec exists (R4.1)

Check that `specs/<team>/design.md` exists and is a regular file.

If it does **not** exist → **REJECT**, print exactly:

```
✗ build rejected: no design spec found at specs/<team>/design.md

There is nothing to build yet. Create the design first:

    /harness-factory:design <team>

Then review it, approve it (scripts/approve <team>), and run build again.
```

### G2 — status is approved (R4.2)

Read `SPEC`'s YAML frontmatter. Parse the `status:` field.

If `status` != `approved` (i.e. `draft`, missing, or anything else) → **REJECT**,
print exactly:

```
✗ build rejected: specs/<team>/design.md is not approved (status: <actual-status>)

A design must be reviewed and frozen before it can be built. After you have
reviewed the spec, approve it:

    ${CLAUDE_PLUGIN_ROOT}/skills/generate-team/scripts/approve <team>

That sets status: approved and freezes the checksum. Then run build again.
```

(Substitute the real observed status, e.g. `draft`, into `<actual-status>`.)

### G3 — checksum matches (R4.3) — the anti-tamper gate

Recompute the canonical digest of the spec with the **shared** script — never
hand-roll hashing (that would risk a false mismatch; see
[`../generate-team/references/checksum-normalization.md`](../generate-team/references/checksum-normalization.md)):

```sh
recomputed=$("${CLAUDE_PLUGIN_ROOT}/skills/generate-team/scripts/checksum.sh" specs/<team>/design.md)
```

Read the frozen `checksum:` value from the frontmatter. Compare:

- `recomputed` == frozen `checksum` → **PASS**, proceed to G4.
- Anything else (mismatch, or empty frozen checksum on an `approved` spec) →
  **HARD REJECT**, print exactly:

```
✗ build rejected: checksum mismatch — specs/<team>/design.md was modified after approval

    frozen (frontmatter): <frozen-checksum>
    recomputed now:       <recomputed-checksum>

The spec changed since it was approved. The approval no longer covers what is on
disk, so build will NOT generate from it. Review the change, then re-approve:

    ${CLAUDE_PLUGIN_ROOT}/skills/generate-team/scripts/approve <team>

Re-approval re-freezes the checksum over the current content. Then run build again.
```

Because approve (freeze) and build (verify) call the **same** `checksum.sh` with
**identical** normalization, a *false* mismatch (disagreeing on a spec nobody
changed) is structurally impossible — a non-empty difference here means the bytes
the human approved are genuinely not the bytes on disk. Do NOT "fix up" or
re-approve on the user's behalf; that would defeat the gate.

### G4 — all gates pass (R4.4)

Only when G1, G2, and G3 all pass: announce "Gate passed — building <team> from
the approved spec." and continue to Phase 0.

### Gate summary

| Check | Condition to PASS | On fail |
|-------|-------------------|---------|
| G1 (R4.1) | `specs/<team>/design.md` exists | reject → run `/harness-factory:design <team>` |
| G2 (R4.2) | frontmatter `status == approved` | reject → run `…/scripts/approve <team>` |
| G3 (R4.3) | `checksum.sh` output == frozen `checksum` | HARD reject → re-approve with `…/scripts/approve <team>` |

> **R5.4 — checksum scope is the SPEC only.** The gate verifies the integrity of
> `design.md` and nothing else. The generated `.claude/*` output is **not**
> checksum-verified — there is no hash over the harness artifacts. The gate's
> guarantee is "build ran from the *approved design*", not "the artifacts on disk
> still match the design". (This is deliberate: T6's idempotent merge preserves
> human edits to generated files, so artifacts are intentionally allowed to drift
> from a byte-for-byte rendering of the spec.)

---

## Phase 0: Load + validate the approved spec (no interview)

The gate proved the spec is *authorized*. Now confirm it is *well-formed*, then
parse it. **Do not ask the user anything** — the spec is the only input (R5.1).

1. **Read** `specs/<team>/design.md` in full.
2. **Structural validation** — assert the spec is well-formed on the consumer
   side too. First run the **shared** deterministic validator (the same one
   `scripts/approve` runs before it freezes, so structure is asserted on both
   producer and consumer sides):

   ```sh
   "${CLAUDE_PLUGIN_ROOT}/skills/generate-team/scripts/validate.sh" specs/<team>/design.md
   ```

   Exit 0 = structurally valid → continue. Non-zero → it lists every problem on
   stderr; **reject**, print those diagnostics, and tell the user to fix the spec
   and re-approve. Then confirm the same checks via the schema's checklist from
   [`../generate-team/references/design-schema.md`](../generate-team/references/design-schema.md)
   ("Validation checklist (build runs this before generating)"):
   - Frontmatter has `team`, `status`, `checksum`.
   - All 8 body sections present, in order: Purpose, Non-goals, Agents, Skills,
     Execution Mode, Invariants/Gates, Escalation Rules, File Layout.
   - Every Agent entry has all 5 fields: name, role, responsibility,
     allowed-tools, model.
   - Every Skill entry has all 3 fields: name, purpose, owner-agent.
   - **Referential integrity (R2.4):** every Skill's `owner-agent` resolves to a
     `name` in `## Agents`. A dangling owner = schema violation → **reject**, name
     the offending skill and tell the user to fix the spec and re-approve.
3. **Parse into a build plan** — extract, for the generation phases:
   - the agent list (name + 5 fields each) → drives Phase 3
   - the skill list (name + 3 fields each, owner-agent wired) → drives Phase 4
   - `## Execution Mode` (team / sub / hybrid + pattern) → drives Phase 5 orchestrator shape
   - `## Invariants/Gates` and `## Escalation Rules` → materialized into the
     orchestrator skill + CLAUDE.md trigger rules
   - `## File Layout` → the exact paths to create; build generates **only** what
     is declared here.

If structural validation fails, reject with the specific violation and stop. A
spec that passed the gate but fails the schema means the approved file is
malformed — the human must fix and re-approve.

---

## Generation (spec-only) — reuse generate-team Phases 3–5

The generation logic is **already written** in
[`../generate-team/SKILL.md`](../generate-team/SKILL.md). Do **not** recreate it
and do **not** re-interview — feed the parsed spec into that logic. The mapping:

| design.md section | generate-team phase | Output |
|-------------------|---------------------|--------|
| `## Agents` | **Phase 3** (Agent Definition Generation) | `.claude/agents/<name>.md` per agent |
| `## Skills` | **Phase 4** (Skill Generation) | `.claude/skills/<name>/SKILL.md` per skill |
| `## Execution Mode` + `## Invariants/Gates` + `## Escalation Rules` | **Phase 5** (Integration + Orchestration) | orchestrator skill + `CLAUDE.md` pointer |
| `## File Layout` | (drives all three) | the exact set of paths to materialize |

The one change vs. generate-team: **the inputs are the spec's fields, not live
interview answers.** Where Phase 3/4/5 say "decide X" or "ask the user", instead
**read X from the corresponding spec section**. Every generated artifact must
trace back to a field in `design.md` (D5 — near-lossless serialization).

### Phase 3 — Agent definitions (from `## Agents`)

For each agent entry, write `.claude/agents/<name>.md` following generate-team
Phase 3. Carry the spec's fields straight through:

- **role** + **responsibility** → the agent's core role / operating-principles sections.
- **allowed-tools** → the agent definition's tool grant.
- **model** → `model: opus` (repo convention — generate-team Phase 3: all agents
  use opus; if the spec says otherwise, honor `opus` per repo convention).

Create the definition **file** for every agent — even built-in types
(`general-purpose`, `Explore`, `Plan`) get a definition file (Phase 3 rule). Add
the `## Team Communication Protocol` section when `## Execution Mode` is `team`.

### Phase 4 — Skills (from `## Skills`)

For each skill entry, write `.claude/skills/<name>/SKILL.md` following
generate-team Phase 4 (aggressive description, lean body < 500 lines, progressive
disclosure to `references/`). Wire ownership: the SKILL.md states its
**owner-agent** (already integrity-checked in Phase 0) so the agent↔skill
connection is explicit.

### Phase 5 — Orchestrator + CLAUDE.md (from Execution Mode / Invariants / Escalation)

Following generate-team Phase 5:

- Build the orchestrator skill in the shape dictated by `## Execution Mode`
  (team → `TeamCreate`/`TaskCreate` self-coordination; sub → `Agent` fan-out;
  hybrid → per-phase modes).
- Materialize `## Invariants/Gates` and `## Escalation Rules` into the
  orchestrator's gate/error-handling logic so the team actually enforces them.
- Write the **CLAUDE.md harness pointer** (generate-team 5-4 template): trigger
  rules + a change-history table only. Do **not** dump the agent/skill list or
  directory tree into CLAUDE.md (it drifts; the orchestrator + `.claude/` own
  that). Seed the change-history table with the initial build row
  (`<today> | Initial build from approved spec | All | —`).

### File Layout is the authority on paths

Generate **only** the paths declared in `## File Layout`. Do not invent extra
files, and do not create anything under `.claude/commands/` (generate-team
Output Checklist: no commands created). When done, verify on-disk paths match the
declared layout.

---

## Phase 6: Validation (spec-conformance, not interview)

Run a condensed version of generate-team Phase 6, oriented to spec conformance:

- **Structure:** every agent in `## Agents` has a file; every skill in `## Skills`
  has a `SKILL.md`; skill frontmatter (name, description) is valid; no files
  outside `## File Layout`; nothing under `.claude/commands/`.
- **Wiring:** each skill's owner-agent exists as an agent file; orchestrator
  references resolve; CLAUDE.md trigger rule points at the orchestrator skill.
- **Mode:** the orchestrator's coordination matches `## Execution Mode`.

Report what was generated (counts of agents/skills, the CLAUDE.md pointer) and
restate the R5.4 scope note: the gate covered the **spec**; the generated
`.claude/*` is not checksum-verified.

---

## Phase 0-M: Idempotent re-run merge (run after Phase 0, before generation)

Phase 0 parsed the approved spec into a build plan. Before generating, audit the
CWD the way generate-team **Phase 0** does (read `.claude/agents/`,
`.claude/skills/`, `CLAUDE.md`) and branch:

- **No prior harness** for `<team>` → **clean first build**. Skip this phase;
  generate fresh via Phases 3–5 above. (This is the case Phases 3–6 describe.)
- **Prior harness present** → **re-run**. Do **not** wholesale-overwrite. Merge
  the spec onto the existing harness per the rules below (R5.3, R5.5).

> **Why merge, not overwrite.** The checksum gate covers the **spec only** (R5.4)
> — it deliberately does *not* hash the `.claude/*` output. That is precisely
> *because* artifacts are meant to be human-editable: a blind re-render would
> destroy hand-tuned agent prompts or skill bodies, and the gate (which only
> watches the spec) would never catch it. This merge step is the mechanism that
> reconciles output drift — correcting structure to the spec while preserving
> human body edits. The gate proves "build ran from the approved design"; merge
> proves "we did not clobber the human's edits doing it".

### Change-detection key (regenerate only what changed — R5.3)

Decide create / update / preserve **per artifact** from two section-level diffs:

1. **File Layout set** — parse `## File Layout` into the canonical path set (one
   agent file per `## Agents` entry, one `SKILL.md` per `## Skills` entry,
   `CLAUDE.md`) and diff it against disk:
   - in spec, **not** on disk → **CREATE** (spec adds it).
   - on disk, **not** in spec → **EXTRA** — never delete; warn (see merge ref).
   - in both → candidate for update-or-preserve (next).
2. **Per-section change** — for each artifact present in both, compare its source
   spec section to the artifact's on-disk **structure**:
   - **Agent** → its `## Agents` block (name, role, responsibility, allowed-tools,
     model).
   - **Skill** → its `## Skills` block (name, purpose, owner-agent) + declared path.
   - **Orchestrator / CLAUDE.md** → `## Execution Mode` + `## Invariants/Gates` +
     `## Escalation Rules`.

   Section **unchanged** → **PRESERVE** (do not touch the file). Section
   **changed** → **UPDATE** only that one artifact. The key is **section-granular**:
   changing one agent's allowed-tools re-renders that one agent, not the team.
   There is no stored prior-spec snapshot — the on-disk artifact *is* the record of
   the last build, so "did it change?" = "does the artifact's structure still match
   what this spec section would generate?".

### Merge precedence on divergence (R5.5)

When an artifact is UPDATE or has drifted, split reconciliation into two layers
with **different** rules:

- **STRUCTURE → SPEC WINS.** Which agents/skills exist (File Layout), each agent's
  **allowed-tools** + **model**, each skill's **owner-agent** wiring, and the
  orchestrator's **execution mode** are corrected to match the approved spec. The
  human approved this structure and the gate proved it; structural drift is an
  error to fix, not an edit to keep.
- **BODY → PRESERVE-AND-WARN.** Human-edited prose *inside* an agent/skill `.md`
  that the spec does not dictate field-by-field (tuned prompt paragraphs, added
  principles, expanded workflows) is **preserved** — never overwritten — but the
  divergence is **surfaced as a warning** so the human knows the output no longer
  matches a clean render of the spec.

When an artifact has both a changed structural section and a human-edited body,
apply the structural correction **in place** (edit the frontmatter tool grant /
model / owner-agent), keep the surrounding human body intact, and emit the
body-divergence warning. Do **not** regenerate the whole file from scratch — that
discards the body. Mnemonic: **spec owns the skeleton, human owns the flesh.**

> **R5.4 reaffirmed.** The checksum gate covers the **spec only**; the generated
> `.claude/*` is intentionally *not* checksum-verified. This merge step — not the
> gate — is what reconciles output drift. That separation is deliberate: hash-
> locking artifacts would forbid the human edits this phase exists to preserve.

For the full algorithm (first-build detection, EXTRA/renamed handling, CLAUDE.md
append-only change history, and the merge report), read
[`references/merge.md`](references/merge.md).

---

## References (shared — do not duplicate)

- Design↔build contract / what sections to consume:
  [`../generate-team/references/design-schema.md`](../generate-team/references/design-schema.md)
- Checksum normalization (the G3 hash contract):
  [`../generate-team/references/checksum-normalization.md`](../generate-team/references/checksum-normalization.md)
- Generation logic reused by Phases 3–5:
  [`../generate-team/SKILL.md`](../generate-team/SKILL.md)
- Idempotent re-run merge algorithm (Phase 0-M full detail):
  [`references/merge.md`](references/merge.md)
- Shared checksum script (called in G3):
  `../generate-team/scripts/checksum.sh`
- Approve helper (producer side, freezes the checksum):
  `../generate-team/scripts/approve`
