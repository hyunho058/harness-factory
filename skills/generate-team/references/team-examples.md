# Agent Team Examples

---

## Example 1: Research Team (Agent Team Mode)

### Team Architecture: Fan-out / Fan-in
### Execution Mode: Agent Team

```
[leader/orchestrator]
    ├── TeamCreate(research-team)
    ├── TaskCreate(4 research tasks)
    ├── Members self-coordinate (SendMessage)
    ├── Collect results (Read)
    └── Generate consolidated report
```

### Agent Composition

| Member | Agent Type | Role | Output |
|--------|------------|------|--------|
| official-researcher | general-purpose | Official docs/blog | research_official.md |
| media-researcher | general-purpose | Media/investment | research_media.md |
| community-researcher | general-purpose | Community/social | research_community.md |
| background-researcher | general-purpose | Background/competitive/academic | research_background.md |
| (leader = orchestrator) | — | Consolidated report | consolidated_report.md |

> Research agents use the `general-purpose` built-in type but must be defined in `.claude/agents/{name}.md` files. Each file specifies role, research scope, and team communication protocol to ensure reusability and collaboration quality.

### Orchestrator Workflow (Agent Team)

```
Phase 1: Preparation
  - Analyze user input (identify topic, research mode)
  - Create _workspace/

Phase 2: Team Setup
  - TeamCreate(team_name: "research-team", members: [
      { name: "official", prompt: "Research official channels..." },
      { name: "media", prompt: "Research media/investment trends..." },
      { name: "community", prompt: "Research community reactions..." },
      { name: "background", prompt: "Research background/competitive landscape..." }
    ])
  - TaskCreate(tasks: [
      { title: "Official channel research", assignee: "official" },
      { title: "Media trend research", assignee: "media" },
      { title: "Community reaction research", assignee: "community" },
      { title: "Background landscape research", assignee: "background" }
    ])

Phase 3: Research Execution
  - 4 members research independently
  - Share interesting findings via SendMessage between members
    (e.g., media passes investment news to background)
  - When conflicting information found, members debate directly
  - Each member saves file + notifies leader when done

Phase 4: Integration
  - Leader reads 4 output files
  - Generate consolidated report
  - Note conflicting information with source attribution

Phase 5: Cleanup
  - Request member termination
  - Clean up team
  - Preserve _workspace/ (for post-hoc verification and audit trail)
```

### Team Communication Patterns

```
official ──SendMessage──→ background  (share relevant official announcements)
media ────SendMessage──→ background  (share investment/acquisition information)
community ─SendMessage──→ media      (community reactions relevant to media)
all members ──TaskUpdate──→ shared task list  (progress updates)
leader ←───── idle notification ──── completed member   (automatic)
```

---

## Example 2: SF Novel Writing Team (Agent Team Mode)

### Team Architecture: Pipeline + Fan-out
### Execution Mode: Agent Team

```
Phase 1 (parallel — agent team): worldbuilder + character-designer + plot-architect
  → Self-coordinate consistency via SendMessage
Phase 2 (sequential): prose-stylist (writing)
Phase 3 (parallel — agent team): science-consultant + continuity-manager (review)
  → Share findings via SendMessage
Phase 4 (sequential): prose-stylist (apply review revisions)
```

### Agent Composition

| Member | Agent Type | Role | Skill |
|--------|------------|------|-------|
| worldbuilder | custom | World-building | world-setting |
| character-designer | custom | Character design | character-profile |
| plot-architect | custom | Plot structure | outline |
| prose-stylist | custom | Style editing + writing | write-scene, review-chapter |
| science-consultant | custom | Science verification | science-check |
| continuity-manager | custom | Consistency verification | consistency-check |

### Full Agent File Example: `worldbuilder.md`

```markdown
---
name: worldbuilder
description: "Expert in building SF novel worlds. Designs physical laws, social structures, technology levels, and history."
---

# Worldbuilder — SF World Design Expert

You are an expert in SF world design. Build the physical, social, and technological foundation for the story world based on scientific fact while expanding the imagination.

## Core Role
1. Define the world's physical laws and technology level
2. Design social structures, political systems, and economic systems
3. Establish historical context and current conflict structures
4. Describe environments and atmosphere for each location

## Working Principles
- Internal consistency first — no contradictions between settings
- Infer ripple effects on the world by asking "What if this technology existed?" chains
- World-building serves the story — avoid excessive settings that obstruct the plot

## Input/Output Protocol
- Input: user's world concept, genre requirements
- Output: `_workspace/01_worldbuilder_setting.md`
- Format: markdown, sectioned (physics/society/technology/history/locations)

## Team Communication Protocol
- To character-designer: SendMessage social structure, class system, occupation information
- To plot-architect: SendMessage world's major conflict structures, crisis elements
- From science-consultant: receive scientific error feedback → revise settings
- Broadcast to all relevant members when world settings change

## Error Handling
- If concept is ambiguous, propose 3 directions and ask for selection
- When scientific errors are found, present alternatives alongside

## Collaboration
- Provide social structure information to character-designer
- Provide conflict structure information to plot-architect
- Apply science-consultant feedback to revise settings
```

### Detailed Team Workflow

```
Phase 1: TeamCreate(team_name: "novel-team", members: [worldbuilder, character-designer, plot-architect])
         TaskCreate([world-building, character design, plot structure])
         → Members self-coordinate and work in parallel
         → worldbuilder SendMessage to character-designer when social structure is done
         → character-designer SendMessage to plot-architect when protagonist is set

Phase 2: Clean up Phase 1 team → call prose-stylist as subagent (team not needed for solo writing)
         prose-stylist reads 3 outputs from _workspace/ and writes
         → Save result to _workspace/02_prose_draft.md

Phase 3: Create new team — TeamCreate(team_name: "review-team", members: [science-consultant, continuity-manager])
         (only one team active per session, but Phase 1 team was cleaned up so new team is possible)
         → Two reviewers review draft, share findings with each other
         → science-consultant notifies continuity-manager when physics errors found
         → Clean up team after review

Phase 4: Call prose-stylist as subagent, apply review results for final revision
```

---

## Example 3: Webtoon Production Team (Subagent Mode)

### Team Architecture: Generate-Verify
### Execution Mode: Subagent

> In the generate-verify pattern with only 2 agents where result passing is the core rather than communication, subagent is appropriate.

```
Phase 1: Agent(webtoon-artist) → generate panels
Phase 2: Agent(webtoon-reviewer) → quality review
Phase 3: Agent(webtoon-artist) → regenerate problem panels (max 2 times)
```

### Agent Composition

| Agent | subagent_type | Role | Skill |
|-------|---------------|------|-------|
| webtoon-artist | custom | Generate panel images | generate-webtoon |
| webtoon-reviewer | custom | Quality review | review-webtoon, fix-webtoon-panel |

### Full Agent File Example: `webtoon-reviewer.md`

```markdown
---
name: webtoon-reviewer
description: "Expert in reviewing webtoon panel quality. Evaluates composition, character consistency, text readability, and direction."
---

# Webtoon Reviewer — Webtoon Quality Review Expert

You are an expert in reviewing webtoon panel quality. Evaluate panels based on visual completeness, story delivery, and character consistency.

## Core Role
1. Evaluate composition and visual completeness of each panel
2. Verify character appearance consistency across panels
3. Evaluate speech bubble text readability and placement
4. Review direction flow and pacing of the full episode

## Working Principles
- Give clear verdicts in 3 levels: PASS / FIX / REDO
- FIX for cases resolvable with partial corrections, REDO for cases requiring full regeneration
- Judge based on objective criteria (consistency, readability, composition), not subjective preference

## Input/Output Protocol
- Input: panel images in `_workspace/panels/` directory
- Output: `_workspace/review_report.md`
- Format:
  ```
  ## Panel {N}
  - Verdict: PASS | FIX | REDO
  - Reason: [specific reason]
  - Revision instruction: [specific revision direction if FIX/REDO]
  ```

## Error Handling
- If image load fails, verdict that panel as REDO
- Panels still REDO after 2 regenerations are PASS with a warning

## Collaboration
- Deliver revision instructions to webtoon-artist (based on output file)
- Re-review regenerated panels (max 2-loop)
```

### Error Handling

```
Retry policy:
- REDO verdict panel → request regeneration from artist (include specific revision instructions)
- Force PASS after max 2 loops
- If 50% or more of all panels are REDO, suggest prompt revision to user
```

---

## Example 4: Code Review Team (Agent Team Mode)

### Team Architecture: Fan-out / Fan-in + Discussion
### Execution Mode: Agent Team

> Code review is a prime example where agent teams shine. Reviewers with different perspectives share findings and challenge each other for deeper reviews.

```
[leader] → TeamCreate(review-team)
    ├── security-reviewer: check security vulnerabilities
    ├── performance-reviewer: analyze performance impact
    └── test-reviewer: verify test coverage
    → Reviewers share findings with each other (SendMessage)
    → Leader consolidates results
```

### Team Communication Patterns

```
security ──SendMessage──→ performance  ("This SQL query is injectable, check performance side too")
performance ──SendMessage──→ test      ("Found N+1 query, please verify related tests exist")
test ────SendMessage──→ security      ("No tests for auth module, what's the priority from security perspective?")
```

Key: reviewers communicate **directly without going through the leader** to quickly catch cross-domain issues.

---

## Example 5: Supervisor Pattern — Code Migration Team (Agent Team Mode)

### Team Architecture: Supervisor
### Execution Mode: Agent Team

```
[supervisor/leader] → analyze file list → assign batches
    ├→ [migrator-1] (batch A)
    ├→ [migrator-2] (batch B)
    └→ [migrator-3] (batch C)
    ← receive TaskUpdate → assign additional batches or reassign
```

### Agent Composition

| Member | Role |
|--------|------|
| (leader = migration-supervisor) | File analysis, batch distribution, progress management |
| migrator-1~3 | Migrate assigned file batches |

### Supervisor's Dynamic Distribution Logic (Using Agent Team)

```
1. Collect full list of target files
2. Estimate complexity (file size, import count, dependencies)
3. Register file batches as tasks via TaskCreate (with dependencies)
4. Members claim tasks on their own
5. When member reports completion via TaskUpdate:
   - Success → automatically claim next task
   - Failure → leader sends SendMessage to confirm cause → reassign or assign to different member
6. All tasks complete → leader runs integration tests
```

Difference from fan-out: tasks are **dynamically assigned at runtime**, not fixed in advance. The self-claiming feature of the shared task list naturally matches the supervisor pattern.

---

## Output Pattern Summary

### Agent Definition Files
Location: `project/.claude/agents/{agent-name}.md`
Required sections: Core Role, Working Principles, Input/Output Protocol, Error Handling, Collaboration
Additional section for team mode: **Team Communication Protocol** (message receive/send, task claim scope)

### Skill File Structure
Location: `project/.claude/skills/{skill-name}/SKILL.md` (project level)
Or: `~/.claude/skills/{skill-name}/SKILL.md` (global level)

### Integration Skill (Orchestrator)
Top-level skill that coordinates the entire team. Defines agent composition and workflow per scenario.
Template: see `references/orchestrator-template.md`.
**Always specify execution mode** — agent team (default) or subagent.
