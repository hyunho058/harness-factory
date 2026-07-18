# Orchestrator Skill Template

The orchestrator is the top-level skill that coordinates the entire team. Three templates are provided for each execution mode:

- **Template A: Agent Team Mode (Default)** — first choice for 2+ agent collaboration
- **Template B: Sub-agent Mode (Alternative)** — when team communication is unnecessary
- **Template C: Hybrid Mode** — mix modes per phase

---

## Template A: Agent Team Mode (Default · First Choice)

**The first mode to consider** when 2+ agents collaborate. Use `TeamCreate` to form the team and coordinate via shared task list and `SendMessage`.

> **Prerequisite — team primitives.** This template uses `TeamCreate` /
> `TeamDelete` / `SendMessage` / `TaskCreate`, which are **not present in every
> Claude Code version or session**. Confirm `TeamCreate` is exposed in the target
> environment before generating a team orchestrator. **If it is unavailable, use
> Template B (Sub-agent)** — it relies only on the always-available `Agent` tool
> and is the safe fallback. See `agent-design-patterns.md` → "Execution Modes" for
> the full rule (do not flip the project default to sub without measuring first).

```markdown
---
name: {domain}-orchestrator
description: "Orchestrator that coordinates the {domain} agent team. {initial trigger keyword}. Follow-up tasks: also use this skill for {domain} result modification, partial re-run, update, supplementation, re-execution, or improvement of previous results."
---

# {Domain} Orchestrator

Integrated skill that coordinates the {domain} agent team to produce {final output}.

## Execution Mode: Agent Team

## Agent Composition

| Member | Agent type | Role | Skill | Output |
|------|-------------|------|------|------|
| {teammate-1} | {custom or built-in} | {role} | {skill} | {output-file} |
| {teammate-2} | {custom or built-in} | {role} | {skill} | {output-file} |
| ... | | | | |

## Workflow

### Phase 0: Context Check (follow-up task support)

Check for existing outputs to decide the execution mode:

1. Check whether the `_workspace/` directory exists
2. Decide execution mode:
   - **`_workspace/` absent** → initial run. Proceed to Phase 1
   - **`_workspace/` present + user requests partial modification** → partial re-run. Re-invoke only the relevant agent and overwrite only the target outputs
   - **`_workspace/` present + new input provided** → fresh run. Move the existing `_workspace/` to `_workspace_{YYYYMMDD_HHMMSS}/`, then proceed to Phase 1
3. For partial re-run: include previous output paths in the agent prompt so the agent reads the existing results and incorporates the feedback

### Phase 1: Preparation
1. Analyze user input — {what to determine}
2. Create `_workspace/` in the working directory
   - **Initial run**: create new `_workspace/`
   - **Fresh run**: move existing `_workspace/` to `_workspace_{YYYYMMDD_HHMMSS}/`, then immediately re-create `_workspace/`
3. Save input data to `_workspace/00_input/`

### Phase 2: Team Formation

1. Create team:
   ```
   TeamCreate(
     team_name: "{domain}-team",
     members: [
       { name: "{teammate-1}", agent_type: "{type}", model: "opus", prompt: "{role description and task instructions}" },
       { name: "{teammate-2}", agent_type: "{type}", model: "opus", prompt: "{role description and task instructions}" },
       ...
     ]
   )
   ```

2. Register tasks:
   ```
   TaskCreate(tasks: [
     { title: "{task-1}", description: "{details}", assignee: "{teammate-1}" },
     { title: "{task-2}", description: "{details}", assignee: "{teammate-2}" },
     { title: "{task-3}", description: "{details}", depends_on: ["{task-1}"] },
     ...
   ])
   ```

   > 5–6 tasks per member is appropriate. Use `depends_on` to mark tasks with dependencies.

### Phase 3: {Primary Work — e.g., Research/Generation/Analysis}

**Execution:** Members self-coordinate

Members claim tasks from the shared task list and work independently.
The leader monitors progress and intervenes when needed.

**Inter-member communication rules:**
- {teammate-1} sends {what information} to {teammate-2} via SendMessage
- {teammate-2} saves results to a file on task completion and notifies the leader
- If a member needs another member's result, request it via SendMessage

**Output storage:**

| Member | Output path |
|------|----------|
| {teammate-1} | `_workspace/{phase}_{teammate-1}_{artifact}.md` |
| {teammate-2} | `_workspace/{phase}_{teammate-2}_{artifact}.md` |

**Leader monitoring:**
- Automatically notified when a member goes idle
- Send instructions or reassign tasks via SendMessage when a member is blocked
- Check overall progress with TaskGet

### Phase 4: {Follow-up Work — e.g., Verification/Integration}
1. Wait for all members to complete their tasks (check status with TaskGet)
2. Collect each member's output with Read
3. {integration/verification logic}
4. Generate final output: `{output-path}/{filename}`

### Phase 5: Cleanup
1. Request members to stop (SendMessage)
2. Dissolve team (TeamDelete)
3. Preserve `_workspace/` directory (do not delete intermediate outputs — kept for post-verification and audit trail)
4. Report results summary to user

> **When team reconfiguration is needed:** If different specialist combinations are required per phase, clean up the current team with TeamDelete then form the next phase's team with a new TeamCreate. The previous team's outputs are preserved in `_workspace/` so the new team can access them via Read.

## Data Flow

```
[Leader] → TeamCreate → [teammate-1] ←SendMessage→ [teammate-2]
                             │                           │
                             ↓                           ↓
                       artifact-1.md              artifact-2.md
                             │                           │
                             └───────── Read ────────────┘
                                         ↓
                                  [Leader: integrate]
                                         ↓
                                  final output
```

## Error Handling

| Situation | Strategy |
|------|------|
| 1 member fails/stops | Leader detects → check status via SendMessage → restart or spawn replacement member |
| Majority of members fail | Notify user and confirm whether to continue |
| Timeout | Use partial results collected so far, stop incomplete members |
| Data conflict between members | Include both with source attribution, do not delete |
| Task status delayed | Leader checks with TaskGet then manually updates with TaskUpdate |

## Test Scenarios

### Happy Path
1. User provides {input}
2. Phase 1 produces {analysis result}
3. Phase 2 forms team ({N} members + {M} tasks)
4. Phase 3: members self-coordinate and complete tasks
5. Phase 4: integrate outputs and generate final result
6. Phase 5: clean up team
7. Expected result: `{output-path}/{filename}` created

### Error Path
1. {teammate-2} stops with an error in Phase 3
2. Leader receives idle notification
3. Check status via SendMessage → attempt restart
4. If restart fails, reassign {teammate-2}'s tasks to {teammate-1}
5. Proceed to Phase 4 with remaining results
6. Note "{teammate-2} section partially uncollected" in final report
```

---

## Template B: Sub-agent Mode (Alternative)

Use when team communication overhead is unnecessary. Call directly with the `Agent` tool and collect results from return values.

```markdown
---
name: {domain}-orchestrator
description: "Orchestrator that coordinates {domain} agents. {initial trigger keyword}. Include follow-up task keywords."
---

## Execution Mode: Sub-agents

## Agent Composition

| Agent | subagent_type | Role | Skill | Output |
|---------|--------------|------|------|------|
| {agent-1} | {built-in or custom} | {role} | {skill} | {output-file} |
| {agent-2} | ... | ... | ... | ... |

## Workflow

### Phase 0: Context Check
(Same as Template A — branch on `_workspace/` existence)

### Phase 1: Preparation
1. Analyze input
2. Create `_workspace/` (on initial run, or immediately after moving the existing `_workspace/` to the archive directory on a fresh run)

### Phase 2: Parallel Execution
Call N Agent tools simultaneously in a single message:

| Agent | Input | Output | model | run_in_background |
|---------|------|------|-------|-------------------|
| {agent-1} | {source} | `_workspace/{phase}_{agent}_{artifact}.md` | opus | true |
| {agent-2} | {source} | `_workspace/{phase}_{agent}_{artifact}.md` | opus | true |

### Phase 3: Integration
1. Collect return values from each agent
2. Collect file-based outputs with Read
3. Apply integration logic → final output

### Phase 4: Cleanup
1. Preserve `_workspace/`
2. Report results summary

## Error Handling
- 1 agent fails: retry once. If it fails again, proceed with the gap noted
- Majority fail: notify user and confirm whether to continue
- Timeout: use partial results collected so far
```

---

## Template C: Hybrid Mode

Use different execution modes per phase. Specify `**Execution Mode:** {team | sub-agent}` at the top of each phase.

```markdown
---
name: {domain}-orchestrator
description: "{domain} orchestrator (hybrid). {keyword}. Include follow-up task keywords."
---

## Execution Mode: Hybrid

| Phase | Mode | Reason |
|-------|------|------|
| Phase 2 (parallel collection) | Sub-agent | Independent data collection, team communication unnecessary |
| Phase 3 (consensus integration) | Agent team | Conflicting data requires discussion and consensus |
| Phase 4 (independent verification) | Sub-agent | Single QA agent performs objective verification |

## Workflow

### Phase 2: Parallel Data Collection
**Execution Mode:** Sub-agent

Call N agents in parallel with the Agent tool in a single message (`run_in_background: true`).
Each result saved to `_workspace/02_{agent}_raw.md`.

### Phase 3: Consensus-based Integration
**Execution Mode:** Agent team

1. Form integration team with `TeamCreate` (editor + fact-checker + synthesizer)
2. Distribute tasks with `TaskCreate` — all read from Phase 2's `_workspace/02_*` files
3. Members discuss conflicting data via `SendMessage` and reach consensus in files
4. Generate final integrated document `_workspace/03_integrated.md`
5. Clean up team with `TeamDelete`

### Phase 4: Independent Verification
**Execution Mode:** Sub-agent

A single QA sub-agent receives `_workspace/03_integrated.md` as input and generates a verification report.
```

**Hybrid transition rules:**
- Team → Sub-agent: always clean up the team with `TeamDelete` before calling Agent tool
- Sub-agent → Team: pass sub-agent file outputs to team members as Read paths
- Team → Team: clean up the previous team before a new `TeamCreate` (only 1 team active per session)

---

## Writing Principles

1. **State execution mode first** — specify one of "Agent team" / "Sub-agent" / "Hybrid" at the top of the orchestrator. If hybrid, a per-phase mode table is required
2. **Be specific about TeamCreate/SendMessage/TaskCreate usage in team mode** — team composition, task registration, communication rules
3. **Fully specify Agent tool parameters in sub-agent mode** — name, subagent_type, prompt, run_in_background, model
4. **Use absolute file paths** — no relative paths; use clear paths based on `_workspace/`
5. **Specify inter-phase dependencies** — which phase depends on which phase's results. For hybrid, emphasize mode-transition points
6. **Keep error handling realistic** — do not assume "everything succeeds"
7. **Test scenarios are required** — at least 1 happy path + 1 error path

## Follow-up Task Keywords for description

Orchestrator descriptions are insufficient with initial trigger keywords alone. Always include the following follow-up expressions:

- re-run / run again / update / modify / supplement
- "just the {part} of {domain} again"
- "based on previous results", "improve results"
- Domain-specific casual requests (e.g., for a launch strategy harness: "launch", "promotion", "trending")

Without follow-up keywords, the harness becomes effectively dead code after the first run.

## Real Orchestrator Reference

Basic structure of a fan-out/fan-in pattern orchestrator:
Prepare → Phase 0 (context check) → TeamCreate + TaskCreate → N members run in parallel → Read + integrate → cleanup.
See the research team example in `references/team-examples.md`.
