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

```
/generate-team
/generate-team [project description]
```

Leave the argument empty to let the skill scan the current working directory automatically.

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

The `generate-team` skill runs six phases:

| Phase | What happens |
|-------|-------------|
| 0: Audit | Reads existing agents/skills; branches into new build, extend, or maintenance |
| 1: Domain Analysis | Identifies task types, tech stack, and user skill level |
| 2: Architecture Design | Selects execution mode (agent team / sub-agent / hybrid) and team pattern |
| 3: Agent Definitions | Writes `.claude/agents/{name}.md` for every agent |
| 4: Skill Generation | Writes `.claude/skills/{name}/SKILL.md` with aggressive trigger descriptions |
| 5: Orchestrator | Generates the orchestrator skill and CLAUDE.md pointers |
| 6: Testing | Runs each agent/skill through QA, iterates on failures |

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
