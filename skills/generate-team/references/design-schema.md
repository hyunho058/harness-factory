# Design-Spec Schema (Full Contract)

The single source of truth for the `design`↔`build` handoff. `design` (producer)
fills this schema into `specs/<team>/design.md`; `build` (consumer) reads it as its
**only** input. Keep the two sides in lockstep — if a field changes here, both
commands change with it.

A design.md is a Markdown file: a YAML frontmatter block followed by 8 required
body sections. Nothing in `build` is interview-derived — every generated artifact
must trace back to a field defined here. The schema is intentionally rich so the
serialization is near-lossless (spec D5).

---

## Frontmatter

YAML block at the top of the file. Three fields, all required:

| Field | Type | Rule |
|-------|------|------|
| `team` | string | Team name. Matches the `<team>` argument and the `specs/<team>/` dir. |
| `status` | enum | `draft` or `approved`. `design` writes `draft`; `scripts/approve` flips to `approved`. |
| `checksum` | string | sha256 hex of the normalized body. **Empty in draft.** Frozen by `approve`. |

```yaml
---
team: example-team
status: draft
checksum:
---
```

The `checksum` and `status` fields are **excluded** from the hashed body (they
mutate at approve time — including them would self-reference). See
`scripts/checksum.sh` for the exact normalization rules build and approve share.

---

## Body sections

All 8 are REQUIRED and must appear in this order:

1. `## Purpose`
2. `## Non-goals`
3. `## Agents`
4. `## Skills`
5. `## Execution Mode`
6. `## Invariants/Gates`
7. `## Escalation Rules`
8. `## File Layout`

### 1. `## Purpose`

What the generated team is for, in 1–3 sentences. The reviewer reads this first.

### 2. `## Non-goals`

What this team explicitly does NOT do. Records *why* rejected scope was rejected,
so build never re-evaluates already-dismissed alternatives.

### 3. `## Agents`

One entry per agent. **Each entry must carry all 5 fields:**

| Field | Meaning |
|-------|---------|
| name | Agent identifier. Becomes `.claude/agents/<name>.md`. |
| role | One-line role label. |
| responsibility | What this agent owns / is accountable for. |
| allowed-tools | Tools the agent may call (list or `*`). Materialized into the agent file. |
| model | Reasoning model (default `opus`). |

### 4. `## Skills`

One entry per skill. **Each entry must carry all 3 fields:**

| Field | Meaning |
|-------|---------|
| name | Skill identifier. Becomes `.claude/skills/<name>/SKILL.md`. |
| purpose | What the skill does and when it triggers. |
| owner-agent | The agent that owns/invokes this skill. |

**Referential integrity (R2.4):** every Skill's `owner-agent` MUST be the `name`
of an agent that exists in `## Agents`. A skill pointing at an undeclared agent is
a schema violation — build rejects it.

### 5. `## Execution Mode`

How the agents run together: `team`, `sub` (subagent fan-out), or `hybrid`. State
the orchestration pattern. (Adding *new* modes is out of scope for this schema.)

### 6. `## Invariants/Gates`

**This is the point of the gate.** Record the invariants the generated team
enforces — the rules build materializes into the harness (orchestrator skill,
verification gates, CLAUDE.md pointers). If an invariant matters, it lives here or
it does not get enforced. Examples: "no agent writes to `.claude/` directly",
"every PR runs the verify gate", "schema changes escalate to a human".

### 7. `## Escalation Rules`

When and to whom an agent escalates instead of proceeding — autonomy boundaries
(schema change, data loss, auth/payment/security, spec conflict). Records the
*why* so build preserves the reasoning.

### 8. `## File Layout`

The exact paths build will generate. Build creates **only** what is declared here:

- `.claude/agents/<name>.md` — one per agent in `## Agents`
- `.claude/skills/<name>/SKILL.md` — one per skill in `## Skills` (plus optional `references/`)
- `CLAUDE.md` — harness pointer (trigger rules + change history only; not an agent/skill list)

List the concrete paths for this specific team so the consumer and reviewer agree
on what will land on disk.

---

## Validation checklist (build runs this before generating)

Build must pass every check before touching the filesystem. Any failure = reject,
do not generate.

- [ ] **Frontmatter complete** — `team`, `status`, `checksum` all present.
- [ ] **All 8 sections present** — Purpose, Non-goals, Agents, Skills, Execution
      Mode, Invariants/Gates, Escalation Rules, File Layout — in order.
- [ ] **Every Agent has 5 fields** — name, role, responsibility, allowed-tools, model.
- [ ] **Every Skill has 3 fields** — name, purpose, owner-agent.
- [ ] **Referential integrity** — every Skill's owner-agent resolves to an agent
      name in `## Agents` (R2.4). No dangling owners.

The gate checks (`status == approved`, checksum match) are separate and run
*before* this structural validation — see the build command. This checklist
validates the *shape* of an approved spec; the gate validates its *authority*.

---

## See also

- `assets/design-template.md` — fillable instance `design` copies and fills.
- `scripts/checksum.sh` — shared normalization for approve (freeze) and build (verify).
