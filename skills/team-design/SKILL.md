---
name: team-design
description: "Design phase of gated team generation. Runs the interview (Phase 0 audit -> Phase 1 domain analysis -> Phase 2 architecture design), then writes a reviewable design spec to specs/<team>/design.md with status: draft and STOPS — it generates NO .claude/agents, .claude/skills, or CLAUDE.md. Use when the user asks to 'design team', 'design harness', 'design agent team', 'plan a team', 'spec out a team before building', '설계만', '팀 설계', or wants to review/approve the architecture before it materializes. This is the producer half of design -> approve -> build."
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
  - AskUserQuestion
---

# team-design — Interview & Design-Spec Producer

The **design** half of the gated 2-step flow (`design` → `approve` → `build`).
You run the interview and emit a reviewable design spec. You do **not** build the
harness. The whole point of this gate: move review cost from O(output) to
O(design) — a human reads `specs/<team>/design.md`, edits it, approves it, and only
then does `build` materialize `.claude/*`.

**Hard rule (R1.2): you create or modify NOTHING under `.claude/` and you do NOT
touch `CLAUDE.md`.** Your only filesystem output is `specs/<team>/design.md`.

## Inputs

`$ARGUMENTS` = `<team> [project description]`.
- `<team>` (first token) — required; names the spec dir `specs/<team>/` and the
  `team` frontmatter field. If absent, ask the user for it before proceeding.
- the rest — optional free-text description of the domain/project.

## Shared references

This skill reuses the one-shot logic from the sibling `generate-team` skill. Do
**not** duplicate those reference files — read them by relative path on demand:
- `../generate-team/references/agent-design-patterns.md` — execution modes,
  architecture patterns, agent separation criteria (Phase 2).
- `../generate-team/references/team-examples.md` — complete worked harness examples.
- `../generate-team/references/design-schema.md` — **the design.md contract you
  must conform to. Read it before writing.**
- `../generate-team/assets/design-template.md` — the fillable instance you copy.

(Resolve relative to this file: `${CLAUDE_PLUGIN_ROOT}/skills/team-design/`.)

---

## Step 1 — Draft re-entry check (R1.3)

**Before any interview**, check whether `specs/<team>/design.md` already exists:

```bash
ls specs/<team>/design.md 2>/dev/null && grep -m1 '^status:' specs/<team>/design.md
```

Branch on the result:

- **No file** → fresh design. Continue to Step 2.
- **Exists, `status: draft`** → **resume**. Read the existing draft, treat its filled
  sections as prior progress, and continue editing it in place — re-run only the
  phases needed to fill gaps or incorporate new user input. Do not start over and do
  not wipe sections the user already refined.
- **Exists, `status: approved`** → **do NOT silently overwrite.** Warn the user that
  an approved spec exists and that re-designing will reset it to `draft` and discard
  its frozen checksum (forcing re-approval). Use `AskUserQuestion` to require explicit
  confirmation. Only proceed if the user confirms; otherwise stop and point them at
  `build` (the spec is already approved and buildable).

---

## Step 2 — Interview (Phase 0 → 1 → 2)

Run the decision-only phases lifted from `generate-team` SKILL.md. These phases are
**pure decisions** — team name, agent list, skills, execution mode, invariants — and
produce **no files** except the design spec. (In the original one-shot skill, file
materialization only begins at Phase 3, which `build` now owns. You stop at Phase 2.)

### Phase 0 — Current-State Audit (CWD `.claude/`)

Always scan the current working directory; the user must be in the target project.

1. Read `./.claude/agents/`, `./.claude/skills/`, and `./CLAUDE.md` (read-only —
   never write them here).
2. Branch on state:
   - **New build** — agent/skill dirs absent or empty → design all phases fresh.
   - **Extend existing** — a harness already exists and new agents/skills are wanted
     → design only the delta; carry forward existing agents/skills in `File Layout`
     and `Agents`/`Skills` so `build` knows the full intended end-state.
   - **Ops/maintenance** — pure audit/sync of an existing harness is out of scope;
     point to harness-ops `/check-harness`.
3. Cross-reference existing agents/skills against `CLAUDE.md` and note any drift.
4. Report the audit summary to the user and confirm the design plan before proceeding.

### Phase 1 — Domain Analysis

1. Identify the domain/project from the user's request and description.
2. Identify core task types (generate, validate, edit, analyze, …).
3. Analyze conflicts/overlaps with existing agents/skills from the Phase 0 audit.
4. Explore the project codebase — tech stack, data models, key modules (Glob/Grep/Read).
5. Detect user skill level from conversation cues and calibrate tone. Don't use jargon
   ("assertion", "JSON schema") without explanation for non-technical users.

### Phase 2 — Architecture Design

Read `../generate-team/references/agent-design-patterns.md` for the detailed tables.

**2-1 Execution mode.** Default to **agent team** when 2+ agents collaborate.
Choose **sub** only when team communication is structurally unnecessary (result
delivery only) and overhead outweighs benefit. Choose **hybrid** when phases differ
in nature. Record the chosen mode + orchestration pattern → goes to `## Execution Mode`.

**2-2 Architecture pattern.** Decompose the task into specialized domains and pick a
structure: Pipeline / Fan-out-fan-in / Expert pool / Generate-validate / Supervisor /
Hierarchical delegation.

**2-3 Agent separation.** Evaluate specialization, parallelism, context, reusability.
For each agent decide: name, role, responsibility, allowed-tools, model (default
`opus`). For each skill decide: name, purpose, owner-agent (an agent you just named).

**2-4 Invariants, escalation, layout.** Before writing, decide explicitly:
- the **invariants/gates** this team enforces (e.g. "no agent writes `.claude/`
  directly", "every change runs the verify gate") → `## Invariants/Gates`.
- the **escalation rules** — autonomy boundaries (schema change, data loss,
  auth/payment/security, spec conflict) and to whom → `## Escalation Rules`.
- the concrete **file layout** build will generate (one `.claude/agents/<name>.md`
  per agent, one `.claude/skills/<name>/SKILL.md` per skill, plus `CLAUDE.md`).

Confirm the full design with the user (AskUserQuestion) before writing the spec.

---

## Step 3 — Write `specs/<team>/design.md`

Read `../generate-team/references/design-schema.md` (the full contract) and
`../generate-team/assets/design-template.md` (the fillable instance). Copy the
template to `specs/<team>/design.md` and fill **every** placeholder. The spec is
`build`'s **only** input, so the serialization must be near-lossless.

```bash
mkdir -p specs/<team>
```

Conform exactly to the schema:

**Frontmatter** — three fields:
- `team: <team>` (matches the argument and the dir)
- `status: draft` (always — only `scripts/approve` flips this)
- `checksum:` (**empty** — `scripts/approve` freezes it)

**All 8 body sections, in order:**
1. `## Purpose` — 1–3 sentences: what the team is for.
2. `## Non-goals` — what it does NOT do, **and why** each rejected scope/alternative
   was dismissed. **This is load-bearing (D1):** record the rejected alternatives and
   their rationale here so `build` never re-evaluates already-dismissed options.
3. `## Agents` — one subsection per agent, **all 5 fields each**: name (the `###`
   heading), role, responsibility, allowed-tools, model.
4. `## Skills` — one subsection per skill, **all 3 fields each**: name (heading),
   purpose, owner-agent. **Referential integrity (R2.4):** every `owner-agent` must
   be the name of an agent declared in `## Agents`. A dangling owner is invalid.
5. `## Execution Mode` — `team` | `sub` | `hybrid` + the orchestration pattern.
6. `## Invariants/Gates` — the invariants this team enforces (from Phase 2-4). If an
   invariant matters, it lives here or it never gets enforced.
7. `## Escalation Rules` — `<trigger> → escalate to <whom>: <why>`.
8. `## File Layout` — the exact paths build will generate, derived from `## Agents`
   and `## Skills`: one `.claude/agents/<name>.md` per agent, one
   `.claude/skills/<name>/SKILL.md` per skill, and `CLAUDE.md` (harness pointer:
   trigger rules + change history only — not an agent/skill list).

**Self-check before finishing (mirror the schema's validation checklist):**
- [ ] frontmatter has `team`, `status: draft`, empty `checksum`
- [ ] all 8 sections present and in order
- [ ] every Agent has name/role/responsibility/allowed-tools/model
- [ ] every Skill has name/purpose/owner-agent
- [ ] every Skill's owner-agent resolves to a declared agent (no dangling owners)
- [ ] `## File Layout` paths match the Agents/Skills sets
- [ ] rejected alternatives + their *why* recorded (Non-goals / rationale)

Delete the template's guidance comments as you fill each section.

---

## Step 4 — Present the design for review (R1.2)

After writing `specs/<team>/design.md`, **do not generate anything**. Surface the
design so the human can review it *in chat* — they should not have to open an editor
unless they want to.

**Hard rule still holds:** create or modify NOTHING under `.claude/agents/`,
`.claude/skills/`, or `CLAUDE.md` here. The only file that exists so far is the draft
spec; `build` decides the next disk write, after approval.

Print a concise design summary to the user:

```
Design spec written: specs/<team>/design.md (status: draft) — no .claude/* generated.

  Team:       <team>
  Agents (N): <name> — <one-line role>; <name> — <one-line role>; ...
  Skills (N): <name> (owner: <agent>); ...
  Invariants: <the 1-3 most important gates this team enforces>
  Will build: .claude/agents/*, .claude/skills/*/SKILL.md, CLAUDE.md

Full spec: specs/<team>/design.md
```

## Step 5 — Approval gate (in-chat — removes the manual terminal step)

Approval is still an explicit human act and the checksum still freezes — but the
human shouldn't have to type a shell command. Offer the choice with `AskUserQuestion`:

```
question: "Review the design above. How do you want to proceed?"
options:
  - "Approve now"            — freeze the checksum so it's buildable (I run approve for you)
  - "Revise — I'll say what" — tell me the changes; I edit the spec, then re-present
  - "I'll review the file"   — stop; I'll print the manual approve/build steps
```

**On "Approve now"** (the user has reviewed the summary; this is an informed approval):

1. Run the shared approve helper from the project CWD:
   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/generate-team/scripts/approve" <team>
   ```
2. Confirm back to the user: `status: approved`, checksum frozen (show the short
   digest from the helper's summary).
3. Point to build — **do not run build yourself.** Build is the separate consumer
   that owns generation; design's job ends at a frozen, buildable spec:
   ```
   Approved + checksum frozen. Build the harness with:
       /harness-factory:build <team>
   (or just ask me to build it)
   ```

   **Integrity note:** approve only edits the spec's `status`/`checksum` frontmatter —
   design still wrote nothing under `.claude/` (R1.2 holds). The gate is unchanged: if
   the spec is edited after this, `build` rejects on checksum mismatch (re-approve needed).

**On "Revise — I'll say what":** ask what to change, edit `specs/<team>/design.md` in
place (re-validate against the schema), then go back to Step 4 (re-present summary) and
this choice. Loop until the user approves or picks "I'll review the file."

**On "I'll review the file":** stop and print the manual next-steps verbatim
(substitute `<team>`), then end the turn:

```
Next steps:
  1. Review and edit specs/<team>/design.md until the architecture is right.
  2. Approve it (freezes a checksum):
       ${CLAUDE_PLUGIN_ROOT}/skills/generate-team/scripts/approve <team>
  3. Build the harness from the approved spec:
       /harness-factory:build <team>
```

After approval (or the manual-path guidance), end the turn. The design phase is complete.
