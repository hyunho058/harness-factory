---
name: generate-team
description: "Designs and configures an agent team architecture. Analyzes the project codebase to define specialized agents and generate the skills each agent will use. Use when: (1) 'set up agent harness', 'build agent harness', 'design harness', 'generate team', 'build team', 'build agent pod', 'create agent team'; (2) establishing agent-based automation for a new domain or project; (3) restructuring or extending an existing harness. This skill creates and modifies .claude/agents/, .claude/skills/, and CLAUDE.md."
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
  - Agent
  - Task
  - AskUserQuestion
  - TeamCreate
  - TeamDelete
  - SendMessage
  - TaskCreate
  - TaskUpdate
---

# generate-team — Agent Team & Skill Architect

A meta-skill that assembles an agent team tailored to a domain or project, defines each agent's role, and generates the skills each agent will use.

**Core principles:**
1. Generate agent definitions (`.claude/agents/`) and skills (`.claude/skills/`).
2. **Use agent teams as the default execution mode.**
3. **Register harness pointers in CLAUDE.md** — record only minimal pointers (trigger rules + change history) so that the orchestrator skill is activated in new sessions.
4. **The harness is an evolving system, not a fixed artifact** — incorporate feedback after each run and continuously update agents, skills, and CLAUDE.md.

## Workflow

### Phase -1: Routing — Gated Path vs. One-Shot Escape Hatch

**Run this routing check FIRST, before Phase 0.** The default entry point for team generation is now the **gated two-step path** (`design` → approve → `build`), which moves human review cost from O(output) to O(design). The Phase 0–6 one-shot flow below is preserved only as an explicit backward-compatibility escape hatch.

Inspect the user arguments (`$ARGUMENTS`):

**Case A — `--skip-design` is present (one-shot escape hatch):**
Run the existing Phase 0–6 one-shot flow below **unchanged**. This generates `.claude/agents/`, `.claude/skills/`, and `CLAUDE.md` directly in a single run, with no design spec and no approval gate. This is the legacy behavior, preserved for users who explicitly opt in. Proceed to Phase 0.

**Case B — `--skip-design` is ABSENT (default = gated path):**
Do **NOT** silently run the one-shot flow. Instead, route the user to the gated path. The gated path is the default because it lets a human review and approve a small design spec *before* any files are materialized — catching design mistakes when they are cheap to fix.

1. Explain the gated path and the three steps:
   - `/harness-factory:design <team>` — interview (Phase 0–2 reasoning) → writes a reviewable design spec at `specs/<team>/design.md` (`status: draft`), then stops. No `.claude/*` files are written.
   - Review and edit `specs/<team>/design.md`, then run `scripts/approve <team>` — sets `status: approved` and freezes a checksum of the spec.
   - `/harness-factory:build <team>` — reads only the approved spec and generates `.claude/agents/`, `.claude/skills/`, and `CLAUDE.md`. Rejects if the spec is missing, not approved, or was tampered with after approval.
2. Tell the user that if they want the old one-shot behavior (generate everything in one run, no gate), they can re-invoke with `--skip-design`.
3. Use `AskUserQuestion` to let the user choose between:
   - **"Go gated (recommended)"** — stop here and point them to run `/harness-factory:design <team>`. Do **not** generate any `.claude/*` files in this invocation.
   - **"One-shot now"** — proceed to Phase 0 and run the one-shot flow below (equivalent to having passed `--skip-design`).

   The recommended default is the gated path. Only fall through to Phase 0 if the user explicitly chooses one-shot.

### Phase 0: Current State Audit

When the skill is triggered, first check the existing harness state in the current working directory (CWD). Phase 0 always scans the CWD — the user must be in the target project directory before running the command.

1. Read `project/.claude/agents/`, `project/.claude/skills/`, and `project/CLAUDE.md`
2. Branch on current state:
   - **New build**: agent/skill directories are absent or empty → run all phases from Phase 1
   - **Extend existing**: a harness already exists and new agents/skills are requested → run only the required phases per the selection matrix below
   - **Ops/maintenance**: audit, modify, or sync requests for an existing harness → use harness-ops `/check-harness` or `/doc-drift` (out of scope for this skill)

   **Phase selection matrix for extending an existing harness:**
   | Change type | Phase 1 | Phase 2 | Phase 3 | Phase 4 | Phase 5 | Phase 6 |
   |-------------|---------|---------|---------|---------|---------|---------|
   | Add agent | Skip (use Phase 0 results) | Placement decision only | Required | If dedicated skill needed | Modify orchestrator | Required |
   | Add/modify skill | Skip | Skip | Skip | Required | If connections change | Required |
   | Architecture change | Skip | Required | Affected agents only | Affected skills only | Required | Required |
3. Cross-reference existing agents/skills against CLAUDE.md entries and detect drift
4. Report the audit summary to the user and confirm the execution plan

### Phase 1: Domain Analysis
1. Identify the domain/project from the user's request
2. Identify core task types (generate, validate, edit, analyze, etc.)
3. Analyze conflicts/overlaps with existing agents/skills based on Phase 0 audit
4. Explore the project codebase — understand tech stack, data models, and key modules
5. **Detect user skill level** — infer technical level from conversation cues (terminology used, question depth) and calibrate communication tone. Do not use terms like "assertion" or "JSON schema" without explanation for users with limited coding experience.

### Phase 2: Team Architecture Design

#### 2-1. Execution Mode Selection

**Agent team is the primary default.** When two or more agents collaborate, always evaluate agent team mode first. Team members self-coordinate via direct messaging (SendMessage) and a shared task list (TaskCreate), and shared discovery, conflict discussion, and gap coverage improve output quality.

| Mode | When to use | Characteristics |
|------|-------------|-----------------|
| **Agent team** (default) | 2+ agents collaborating, real-time coordination and feedback required, intermediate outputs cross-referenced | Self-coordinated via `TeamCreate` + `SendMessage` + `TaskCreate` |
| **Sub-agent** (alternative) | Single-agent task, only the final result needs to be returned to main, team communication overhead outweighs benefit | Direct `Agent` tool call, parallel via `run_in_background` |
| **Hybrid** | Phases differ in nature — e.g. parallel collection (sub) → consensus integration (team) | Mix team/sub per phase |

**Decision order:**
1. First evaluate whether an agent team design is feasible — default to team for 2+ agents
2. Choose sub-agent only when team communication is structurally unnecessary (result delivery only) and overhead outweighs benefit
3. Consider hybrid when phases differ significantly — specify each phase's execution mode in the orchestrator

> For detailed comparison tables and per-pattern decision trees, see `references/agent-design-patterns.md` under "Execution Modes".

#### 2-2. Architecture Pattern Selection

1. Decompose the task into specialized domains
2. Determine the agent team structure (see `references/agent-design-patterns.md` for architecture patterns):
   - **Pipeline**: sequentially dependent tasks
   - **Fan-out/fan-in**: parallel independent tasks
   - **Expert pool**: situational selection and invocation
   - **Generate-validate**: generate then quality-check
   - **Supervisor**: central agent manages state and dynamically distributes work
   - **Hierarchical delegation**: upper agents recursively delegate to lower agents

#### 2-3. Agent Separation Criteria

Evaluate across four axes: specialization, parallelism, context, and reusability. See `references/agent-design-patterns.md` under "Agent Separation Criteria" for the detailed matrix.

### Phase 3: Agent Definition Generation

**Every agent must be defined in a `project/.claude/agents/{name}.md` file.** Embedding roles directly in an Agent tool prompt without a definition file is prohibited. Reasons:
- Agent definition files must exist as files to be reusable in future sessions
- Team communication protocols must be explicit to guarantee inter-agent collaboration quality
- The core value of a harness is the separation of agents (who) and skills (how)

Even when using built-in types (`general-purpose`, `Explore`, `Plan`), create the agent definition file. Specify the built-in type via the `subagent_type` parameter of the Agent tool, and put the role, principles, and protocols in the definition file.

**Model configuration:** All agents use `model: "opus"`. Always specify `model: "opus"` as a parameter when calling the Agent tool. Harness quality is directly tied to the agents' reasoning capability, and opus guarantees the highest quality.

**Team reconstitution:** Only one team can be active per session, but teams can be dissolved and a new one formed between phases. For pipeline patterns that require different expert combinations per phase, save the previous team's outputs to files, clean up the team, then create a new one.

Define each agent in `project/.claude/agents/{name}.md`. Required sections: core role, operating principles, input/output protocol, error handling, and collaboration. In agent team mode, add a `## Team Communication Protocol` section specifying message sources, destinations, and task request scope.

> For definition templates and complete file examples, see `references/agent-design-patterns.md` under "Agent Definition Structure" + `references/team-examples.md`.

**Required when including a QA agent:**
- Use the `general-purpose` type for QA agents (`Explore` is read-only and cannot run validation scripts)
- QA's core purpose is **"cross-boundary comparison"**, not "existence check" — read both the API response and the frontend hook simultaneously and compare shapes
- Run QA **incrementally after each module completes**, not once at the end
- Detailed guide: see `references/qa-agent-guide.md`

### Phase 4: Skill Generation

Generate skills for each agent in `project/.claude/skills/{name}/SKILL.md`. For a detailed writing guide, see `references/skill-writing-guide.md`.

#### 4-1. Skill Structure

```
skill-name/
├── SKILL.md (required)
│   ├── YAML frontmatter (name, description required)
│   └── Markdown body
└── Bundled Resources (optional)
    ├── scripts/    - executable code for repetitive/deterministic tasks
    ├── references/ - reference documents loaded conditionally
    └── assets/     - files used in output (templates, images, etc.)
```

#### 4-2. Writing the Description — Drive Aggressive Triggering

The description is the skill's only trigger mechanism. Claude tends to be conservative about triggering skills, so write the description **aggressively ("pushy")**.

**Bad example:** `"A skill that processes PDF documents"`
**Good example:** `"Handles all PDF operations: reading, text/table extraction, merging, splitting, rotating, watermarking, encryption, OCR, and more. When a .pdf file is mentioned or a PDF output is requested, always use this skill."`

Key: describe both what the skill does AND the specific trigger conditions, and distinguish it from similar cases that should NOT trigger it.

#### 4-3. Body Writing Principles

| Principle | Description |
|-----------|-------------|
| **Explain the why** | Instead of authoritarian directives like "ALWAYS/NEVER", explain the reason. LLMs that understand the reason make correct judgments even in edge cases. |
| **Stay lean** | The context window is a shared resource. Target SKILL.md body under 500 lines — move non-essential content to references/. |
| **Generalize** | Rather than narrow rules that only fit specific examples, explain the principle so the skill handles diverse inputs. Avoid overfitting. |
| **Bundle repeated code** | When agents consistently write the same scripts across test runs, pre-bundle that code in `scripts/`. |
| **Write in imperative** | Use imperative/directive form: "do X", "run Y", "return Z". |

#### 4-4. Progressive Disclosure

Skills use a three-tier loading system to manage context:

| Tier | When loaded | Size target |
|------|-------------|-------------|
| **Metadata** (name + description) | Always in context | ~100 words |
| **SKILL.md body** | When skill is triggered | <500 lines |
| **references/** | On demand only | Unlimited (scripts can be executed without loading) |

**Size management rules:**
- When SKILL.md approaches 500 lines, split detail into references/ and leave a pointer in the body ("read this file when…")
- Reference files over 300 lines must include a **table of contents** at the top
- When domain/framework variations exist, split them into domain-specific files under references/ and load only the relevant file

```
cloud-deploy/
├── SKILL.md (workflow + selection guide)
└── references/
    ├── aws.md    ← load only when AWS is selected
    ├── gcp.md
    └── azure.md
```

#### 4-5. Skill-Agent Connection Principles

- 1 agent ↔ 1–N skills (one-to-one or one-to-many)
- Multiple agents can share a skill
- Skills capture "how to do it"; agents capture "who does it"

> For detailed writing patterns, examples, and data schema standards, see `references/skill-writing-guide.md`.

### Phase 5: Integration and Orchestration

The orchestrator is a specialized form of skill that ties individual agents and skills into a single workflow and coordinates the entire team. While the individual skills created in Phase 4 define "what each agent does and how", the orchestrator defines "who collaborates, when, and in what order". For a concrete template, see `references/orchestrator-template.md`.

**Modifying the orchestrator when extending:** When extending rather than building fresh, modify the existing orchestrator rather than creating a new one. When adding agents, reflect the new agent in the team composition, task assignment, and data flow, and add trigger keywords for the new agent to the description.

The orchestrator pattern varies based on the execution mode chosen in Phase 2-1:

#### 5-0. Orchestrator Patterns (by mode)

**Agent team pattern (default):**
The orchestrator assembles the team with `TeamCreate` and assigns tasks with `TaskCreate`. Team members self-coordinate via `SendMessage`. The leader (orchestrator) monitors progress and synthesizes results.

```
[Orchestrator/Leader]
    ├── TeamCreate(team_name, members)
    ├── TaskCreate(tasks with dependencies)
    ├── Team members self-coordinate (SendMessage)
    ├── Collect and synthesize results
    └── Clean up team
```

**Sub-agent pattern (alternative):**
The orchestrator invokes sub-agents directly via the `Agent` tool. Use `run_in_background: true` for parallel execution; results are returned only to the main agent. Use when team communication is unnecessary and you want to reduce overhead.

```
[Orchestrator]
    ├── Agent(agent-1, run_in_background=true)
    ├── Agent(agent-2, run_in_background=true)
    ├── Wait and collect results
    └── Produce integrated output
```

**Hybrid pattern:**
Mix modes across phases. Common combinations:
- **Parallel collection (sub) → consensus integration (team)**: Phase 2 uses sub-agents to collect independent data in parallel → Phase 3 creates a team for discussion and consensus-based integration
- **Team generation (team) → validation (sub)**: Phase 2 team produces a draft → Phase 3 single sub-agent independently validates
- **Team reconstitution between phases**: `TeamDelete` then new `TeamCreate` between each phase, with sub-agent calls inserted in between

When choosing hybrid, specify the execution mode for each phase at the top of that phase's section in the orchestrator (e.g., `**Execution mode:** Agent team`).

#### 5-1. Data Transfer Protocol

Specify the data transfer method between agents in the orchestrator:

| Strategy | Method | Applicable mode | When to use |
|----------|--------|-----------------|-------------|
| **Message-based** | Direct communication between team members via `SendMessage` | Team | Real-time coordination, feedback exchange, lightweight state transfer |
| **Task-based** | Share task state via `TaskCreate`/`TaskUpdate` | Team | Progress tracking, dependency management, task delegation |
| **File-based** | Write and read files at agreed-upon paths | Team + Sub | Large data, structured outputs, when audit trail is needed |
| **Return-value-based** | Return message from `Agent` tool | Sub | Main agent collects sub-agent results directly |

**Recommended combination (team mode):** task-based (coordination) + file-based (artifacts) + message-based (real-time communication)
**Recommended combination (sub mode):** return-value-based (result collection) + file-based (large artifacts)
**Hybrid:** apply the combination matching each phase's execution mode

Rules for file-based transfer:
- Create a `_workspace/` folder under the working directory for intermediate outputs
- File naming convention: `{phase}_{agent}_{artifact}.{ext}` (e.g. `01_analyst_requirements.md`)
- Output only final artifacts to the user-specified path; preserve intermediate files (`_workspace/`) for post-validation and audit

#### 5-2. Error Handling

Include error handling policy in the orchestrator. Core principle: retry once, then continue without that result if it fails again (note the omission in the report); do not discard conflicting data — record the source alongside it.

> For per-error-type strategy tables and implementation details, see `references/orchestrator-template.md` under "Error Handling".

#### 5-3. Team Size Guidelines

| Task scale | Recommended team size | Tasks per member |
|------------|-----------------------|-----------------|
| Small (5–10 tasks) | 2–3 | 3–5 |
| Medium (10–20 tasks) | 3–5 | 4–6 |
| Large (20+ tasks) | 5–7 | 4–5 |

> More team members means more coordination overhead. Three focused members outperform five scattered ones.

#### 5-4. Register Harness Pointer in CLAUDE.md

After completing the harness, register minimal pointers in the project's `CLAUDE.md`. Since CLAUDE.md is loaded every new session, recording only the harness existence and trigger rules is enough — the orchestrator skill handles the rest.

**CLAUDE.md template:**

````markdown
## Harness: {domain name}

**Goal:** {one-line core goal of the harness}

**Trigger:** For {domain}-related task requests, use the `{orchestrator-skill-name}` skill. Simple questions can be answered directly.

**Change history:**
| Date | Change | Target | Reason |
|------|--------|--------|--------|
| {YYYY-MM-DD} | Initial setup | All | — |
````

**Do NOT put in CLAUDE.md:** agent list, skill list, directory structure, detailed execution rules. Reason: agent/skill lists are managed by the orchestrator skill and `.claude/agents/`, `.claude/skills/` — duplicating them here causes drift. Directory structure is directly observable from the filesystem. CLAUDE.md holds only **pointers (trigger rules) + change history**.

#### 5-5. Follow-up Task Support

The orchestrator must handle not only initial runs but also follow-up tasks. Ensure the following three things:

**1. Include follow-up keywords in the orchestrator description:**
Initial creation keywords alone will not trigger follow-up requests. Always include these follow-up expressions in the description:
- "re-run", "run again", "update", "modify", "refine"
- "redo only the {sub-task} of {domain}"
- "based on previous results", "improve results"

**2. Add a context check step in orchestrator Phase 1:**
At workflow start, check for existing outputs and decide the execution mode:
- `_workspace/` exists + user requests partial modification → **partial re-run** (re-invoke only the relevant agent)
- `_workspace/` exists + user provides new input → **new run** (move existing `_workspace/` to `_workspace_prev/`)
- `_workspace/` does not exist → **initial run**

**3. Include re-invocation instructions in agent definitions:**
Specify "behavior when prior outputs exist" in each agent's `.md` file:
- If a previous output file exists, read it and incorporate improvements
- If user feedback is given, modify only the relevant section

> See the "Phase 0: Context Check" section in the orchestrator template: `references/orchestrator-template.md`

### Phase 6: Validation and Testing

Validate the generated harness. For detailed testing methodology, see `references/skill-testing-guide.md`.

#### 6-1. Structure Validation

- Confirm all agent files are in the correct location
- Validate skill frontmatter (name, description)
- Confirm inter-agent reference consistency
- Confirm no commands were created

#### 6-2. Execution Mode Validation

- **Agent team**: confirm communication paths between team members, task dependencies, and appropriate team size
- **Sub-agent**: confirm input/output connections for each agent, `run_in_background` settings, and return-value collection logic
- **Hybrid**: confirm each phase's execution mode is specified in the orchestrator, and that data transfer is unbroken at phase boundaries (verify team outputs connect to sub-agent inputs at team → sub transitions)

#### 6-3. Skill Execution Testing

Run actual execution tests for each generated skill:

1. **Write test prompts** — write 2–3 realistic test prompts for each skill. Use concrete, natural sentences that an actual user would type.

2. **With-skill vs. Without-skill comparison** — when possible, run with-skill and without-skill in parallel to verify the skill's added value. Spawn two agents:
   - **With-skill**: read the skill then perform the task
   - **Without-skill (baseline)**: perform the same prompt without the skill

3. **Evaluate results** — assess output quality both qualitatively (user review) and quantitatively (assertion-based). When outputs are objectively verifiable (file generation, data extraction, etc.), define assertions; for subjective cases (tone, design), rely on user feedback.

4. **Iterative improvement loop** — when issues are found in test results:
   - **Generalize** the feedback and update the skill (do not make narrow fixes for specific examples)
   - Retest after modification
   - Repeat until the user is satisfied or no meaningful improvement remains

5. **Bundle repeated patterns** — when agents consistently produce the same code across test runs (e.g. the same helper script in every test), pre-bundle that code in `scripts/`.

#### 6-4. Trigger Validation

Validate that each skill's description triggers correctly:

1. **Should-trigger queries** (8–10) — diverse phrasings that should trigger the skill (formal/casual, explicit/implicit)
2. **Should-NOT-trigger queries** (8–10) — "near-miss" queries with similar keywords but where a different tool/skill is more appropriate

**Key to writing near-miss queries:** Queries like "write a Fibonacci function" are obviously unrelated and have no test value. Good test cases have ambiguous boundaries — e.g. "extract the chart in this Excel file as PNG" (xlsx skill vs. image conversion).

Also check for trigger conflicts with existing skills at this stage.

#### 6-5. Dry Run Test

- Review that the orchestrator skill's phase order is logical
- Confirm no dead links in data transfer paths
- Confirm every agent's input matches the output of the preceding phase
- Confirm fallback paths for error scenarios are executable

#### 6-6. Write Test Scenarios

- Add a `## Test Scenarios` section to the orchestrator skill
- Document at least one happy-path flow and one error flow

## Output Checklist

Verify after generation is complete:

- [ ] `project/.claude/agents/` — **agent definition files must be created** (required even for built-in types)
- [ ] `project/.claude/skills/` — skill files (SKILL.md + references/)
- [ ] One orchestrator skill (includes data flow + error handling + test scenarios)
- [ ] Execution mode specified (agent team / sub-agent / hybrid; if hybrid, mode listed per phase)
- [ ] All Agent calls include `model: "opus"` parameter
- [ ] `.claude/commands/` — nothing created
- [ ] No conflicts with existing agents/skills
- [ ] Skill descriptions written aggressively ("pushy") — **includes follow-up task keywords**
- [ ] SKILL.md body is under 500 lines; if exceeded, split into references/
- [ ] Execution verified with 2–3 test prompts
- [ ] Trigger validation complete (should-trigger + should-NOT-trigger)
- [ ] **Harness pointer registered in CLAUDE.md** (trigger rules + change history)
- [ ] **Agent/skill additions, deletions, and modifications recorded in CLAUDE.md change history**
- [ ] **Context check step in orchestrator Phase 1** (initial / follow-up / partial re-run determination)

## References

- Harness patterns: `references/agent-design-patterns.md`
- Existing harness examples (complete file contents): `references/team-examples.md`
- Orchestrator template: `references/orchestrator-template.md`
- **Skill writing guide**: `references/skill-writing-guide.md` — writing patterns, examples, data schema standards
- **Skill testing guide**: `references/skill-testing-guide.md` — testing/evaluation/iterative improvement methodology
- **QA agent guide**: `references/qa-agent-guide.md` — reference when including a QA agent in a build harness. Covers integration consistency validation methodology, boundary bug patterns, and QA agent definition templates. Based on 7 real-world bug cases from production projects.
