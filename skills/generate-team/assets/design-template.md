---
team: <team-name>
status: draft
checksum:
---

<!-- This is a fillable instance of references/design-schema.md.
     `design` copies it to specs/<team>/design.md and fills every placeholder.
     Leave status: draft and checksum empty — scripts/approve sets both.
     Delete these guidance comments as you fill each section. -->

## Purpose

<!-- 1-3 sentences: what this team is for. The reviewer reads this first. -->
<Why this team exists and what outcome it produces.>

## Non-goals

<!-- What this team explicitly does NOT do. Record WHY rejected scope was rejected
     so build never re-evaluates dismissed alternatives. -->
- <Out-of-scope item — and why.>

## Agents

<!-- One subsection per agent. Each MUST carry all 5 fields:
     name, role, responsibility, allowed-tools, model. -->

### <agent-name>
- **role**: <one-line role label>
- **responsibility**: <what this agent owns / is accountable for>
- **allowed-tools**: <tool list, or * >
- **model**: opus

### <another-agent-name>
- **role**: <...>
- **responsibility**: <...>
- **allowed-tools**: <...>
- **model**: opus

## Skills

<!-- One subsection per skill. Each MUST carry all 3 fields:
     name, purpose, owner-agent.
     owner-agent MUST be the name of an agent listed in ## Agents above
     (referential integrity, R2.4) — a dangling owner is rejected by build. -->

### <skill-name>
- **purpose**: <what it does and when it triggers>
- **owner-agent**: <agent-name from ## Agents>

## Execution Mode

<!-- team | sub | hybrid — plus the orchestration pattern. -->
<mode>: <how the agents run together>

## Invariants/Gates

<!-- The whole point of the gate. Record the invariants this team ENFORCES —
     build materializes these into the harness (orchestrator skill, verify gates,
     CLAUDE.md pointers). If an invariant matters, it lives here. -->
- <Invariant the team enforces, e.g. "no agent writes to .claude/ directly">
- <Gate, e.g. "every change runs the verify gate before merge">

## Escalation Rules

<!-- When and to whom an agent escalates instead of proceeding — autonomy
     boundaries. Record the WHY. -->
- <Trigger> → escalate to <whom>: <why>

## File Layout

<!-- The exact paths build will generate. Build creates ONLY what is declared here.
     One agents/ file per agent above, one skills/ dir per skill above. -->
- `.claude/agents/<agent-name>.md` — <agent-name>
- `.claude/skills/<skill-name>/SKILL.md` — <skill-name>
- `CLAUDE.md` — harness pointer (trigger rules + change history)
