# harness-factory

A Claude Code plugin that analyzes your project codebase and automatically generates a multi-agent team architecture — producing `.claude/agents/`, `.claude/skills/`, and `CLAUDE.md` tailored to your domain.

## What it does

Run `/generate-team` (or `/harness-factory:generate-team`) in any project directory. The skill:

1. **Audits** the existing harness state (agents, skills, CLAUDE.md)
2. **Analyzes** the project's domain, tech stack, and task types
3. **Designs** an agent team architecture (pipeline, fan-out, expert pool, etc.)
4. **Generates** agent definition files in `.claude/agents/`
5. **Generates** skill files in `.claude/skills/`
6. **Registers** orchestration pointers in `CLAUDE.md`
7. **Tests** each agent/skill and iterates based on QA feedback

## Installation

```bash
# 1. Clone the repository
git clone https://github.com/hyunhokim/harness-factory.git ~/.claude/plugins/harness-factory

# 2. Register the marketplace
claude plugin marketplace add ~/.claude/plugins/harness-factory

# 3. Install the plugin
claude plugin install harness-factory
```

## Usage

The default flow is **gated**: a human reviews and approves a small design spec *before* any files are generated. This moves review cost from O(output) to O(design).

```
# 1. Design — interview, then write a reviewable spec and stop
/harness-factory:design <team>

# 2. Review specs/<team>/design.md, then approve (freezes a checksum)
scripts/approve <team>

# 3. Build — reads only the approved spec and generates the harness
/harness-factory:build <team>
```

`design` runs the interview (audit → domain analysis → architecture design) and writes `specs/<team>/design.md` with `status: draft`, then stops — no `.claude/*` files are written. After you edit and approve the spec, `build` reads only the approved spec and generates `.claude/agents/`, `.claude/skills/`, and `CLAUDE.md`. `build` hard-rejects if the spec is missing, not approved, or was tampered with after approval (checksum mismatch).

### One-shot escape hatch (`--skip-design`)

The legacy single-run flow is preserved as an explicit opt-out:

```
/generate-team --skip-design [project description]
```

With `--skip-design`, the original Phase 0–6 flow runs in one pass and writes `.claude/*` directly, with no design spec and no approval gate.

Running `/generate-team` **without** `--skip-design` does not silently generate anything — it explains the gated path above and routes you to `/harness-factory:design <team>`. Leave the project description empty to let the skill scan the current working directory automatically.

## Practical Example: Generating a UI Component Team

Instead of abstract concepts, here is exactly what you type, what gets generated, and how you use it.

### Scenario: Building a React "UI Component Development & QA" Team

Assume you are in your frontend project directory (`my-react-app`).

#### Step 1: Trigger the factory
You type the following in Claude Code:
> `/generate-team "Create an agent team that develops UI components and strictly checks design system consistency"`

#### Step 2: What the factory does behind the scenes
`harness-factory` audits your current project state and analyzes your request, automatically generating the following files:

*   **Agent definitions (Who does the work):**
    *   `.claude/agents/ui-developer.md`
    *   `.claude/agents/design-qa.md`
*   **Skill definitions (How they work):**
    *   `.claude/skills/build-component/SKILL.md`
    *   `.claude/skills/ui-orchestrator/SKILL.md` (★ The Leader skill that coordinates the team)
*   **CLAUDE.md pointer:**
    *   Adds a rule to `CLAUDE.md`: *"For UI tasks, use the `ui-orchestrator` skill."*

#### Step 3: Daily Usage
The next day, you simply type:
> *"Create a dark-mode compatible login button component"*

The generated **Leader skill (`ui-orchestrator`)** immediately kicks in:
1.  The `ui-developer` agent writes the code.
2.  The `design-qa` agent reviews it and sends feedback (e.g., "The dark mode color variable doesn't match the design system").
3.  The `ui-developer` refines the code and submits the final output to you.

#### The real power: Safe Extensibility
A few days later, you realize you also need accessibility (a11y) checks. Instead of rebuilding everything, you run:
> `/generate-team "Add an accessibility QA agent to the existing UI team"`

The factory audits the `.claude/` folder, leaves existing agents untouched, creates a new `a11y-tester.md` agent, and smoothly updates the `ui-orchestrator` pipeline to route tasks through `ui-developer -> a11y-tester -> design-qa`.

## How it works

The same six phases of reasoning are split across the gated flow at the seam between *decisions* (Phase 0–2) and *materialization* (Phase 3–6):

| Phase | What happens | Stage |
|-------|-------------|-------|
| 0: Audit | Reads existing agents/skills; branches into new build, extend, or maintenance | design |
| 1: Domain Analysis | Identifies task types, tech stack, and user skill level | design |
| 2: Architecture Design | Selects execution mode (agent team / sub-agent / hybrid) and team pattern | design |
| 3: Agent Definitions | Writes `.claude/agents/{name}.md` for every agent | build |
| 4: Skill Generation | Writes `.claude/skills/{name}/SKILL.md` with aggressive trigger descriptions | build |
| 5: Orchestrator | Generates the orchestrator skill and CLAUDE.md pointers | build |
| 6: Testing | Runs each agent/skill through QA, iterates on failures | build |

In the **gated path** (default), `design` runs the decision phases (0–2) and emits `specs/<team>/design.md`; after human approval (`scripts/approve`), `build` runs the materialization phases (3–6) from the approved spec alone. The `--skip-design` escape hatch runs all six phases in one pass with no gate.

All agents use `model: opus` for maximum reasoning quality.

## Repository structure

```
harness-factory/
├── commands/
│   └── generate-team.md          # Slash command entry point
└── skills/
    └── generate-team/
        ├── SKILL.md               # Core skill logic (6-phase workflow)
        └── references/
            ├── agent-design-patterns.md   # Architecture patterns and agent separation criteria
            ├── orchestrator-template.md   # Orchestrator skill template
            ├── qa-agent-guide.md          # QA agent design guide
            ├── skill-testing-guide.md     # Skill evaluation and testing guide
            ├── skill-writing-guide.md     # Skill writing best practices
            └── team-examples.md           # Complete team example definitions
```

## harness-ops integration

If [harness-ops](https://github.com/hyunho058/harness-ops) is installed, you can also trigger this skill via:

```
/harness-ops:generate-team
```

The harness-ops wrapper checks whether harness-factory is installed and delegates to this skill automatically.

## Extending an existing harness

Re-run `/generate-team` at any time. The Phase 0 audit detects the current harness state and runs only the phases needed for the requested change (add agent, add skill, architecture change). Existing agents and skills are preserved unless explicitly modified.
