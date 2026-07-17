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

**You don't have to open a terminal.** When `design` finishes it presents the design in chat and offers **Approve now** / **Revise (tell me changes)** / **Review the file myself**. Picking *Approve now* runs the `approve` helper for you (freezing the checksum) so step 2 above becomes a single click; picking *Revise* lets you describe edits conversationally and Claude updates the spec, then re-presents it. The checksum gate is unchanged either way — approval is still an explicit act, and `build` still rejects a spec edited after approval.

### One-shot escape hatch (`--skip-design`)

The legacy single-run flow is preserved as an explicit opt-out:

```
/generate-team --skip-design [project description]
```

With `--skip-design`, the original Phase 0–6 flow runs in one pass and writes `.claude/*` directly, with no design spec and no approval gate.

Running `/generate-team` **without** `--skip-design` does not silently generate anything. It explains the gated path above and routes you toward `/harness-factory:design <team>` — but first (in Phase -1) it asks, via an in-chat prompt, whether you'd rather take the one-shot escape hatch right now, so you can opt into a single-run build without re-invoking with `--skip-design`. The gated path is the recommended default; a one-shot run happens only if you explicitly choose it. Leave the project description empty to let the skill scan the current working directory automatically.

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
├── .claude-plugin/
│   ├── plugin.json               # Plugin manifest (name, version)
│   └── marketplace.json          # Marketplace registration
├── commands/
│   ├── design.md                 # /harness-factory:design — interview → spec, then stop (gated step 1)
│   ├── build.md                  # /harness-factory:build — build from the approved spec (gated step 3)
│   └── generate-team.md          # /harness-factory:generate-team — router (gated by default, --skip-design one-shot)
├── skills/
│   ├── team-design/
│   │   └── SKILL.md              # Producer: interview → specs/<team>/design.md (status: draft); writes no .claude/*
│   ├── team-build/
│   │   ├── SKILL.md              # Consumer: gate (exists → approved → checksum) then materialize from spec only
│   │   └── references/
│   │       └── merge.md          # Idempotent re-build merge rules (structure = spec wins, prose = preserve-and-warn)
│   └── generate-team/
│       ├── SKILL.md              # Core 6-phase logic + Phase -1 router + --skip-design one-shot escape hatch
│       ├── scripts/
│       │   ├── approve           # Producer side of the checksum gate — sets status: approved, freezes sha256
│       │   ├── checksum.sh       # Canonical whole-spec digest, shared: approve AND build call the SAME script (0 false mismatch)
│       │   ├── validate.sh       # Shared structural validation — approve (pre-freeze) + build (post-gate) [added by improvement work]
│       │   └── section-checksum.sh # Per-section digest (reuses checksum.sh) — build's deterministic rebuild key [added by improvement work]
│       ├── assets/
│       │   └── design-template.md # design.md skeleton emitted by the design phase
│       └── references/
│           ├── agent-design-patterns.md   # Architecture patterns and agent separation criteria
│           ├── checksum-normalization.md  # Checksum normalization rules (cites specs/gated-team-generation/spec.md)
│           ├── design-schema.md           # design.md schema — the design↔build contract
│           ├── orchestrator-template.md   # Orchestrator skill template
│           ├── qa-agent-guide.md          # QA agent design guide
│           ├── skill-testing-guide.md     # Skill evaluation and testing guide
│           ├── skill-writing-guide.md     # Skill writing best practices
│           └── team-examples.md           # Complete team example definitions
├── specs/
│   └── gated-team-generation/
│       └── spec.md               # Design ledger (D1–D6 rationale) — where the script/reference citations resolve
├── tests/                        # Gate regression tests (approve/checksum/reject scenarios) [added by improvement work]
├── .github/
│   └── workflows/                # CI running the gate tests [added by improvement work]
└── plugins/
    └── harness-factory -> ../    # Self-referential symlink to the repo root (see the Compatibility note below)
```

> Entries marked *[added by improvement work]* (`validate.sh`, `section-checksum.sh`, `tests/`, `.github/workflows/`) land alongside this documentation refresh. `section-checksum.sh` stamps each generated artifact with a provenance marker (`<!-- generated-from: … @ sha256:… -->`) so a re-build's preserve-vs-regenerate decision is deterministic rather than an LLM re-render comparison. `specs/` is otherwise git-ignored; only `specs/gated-team-generation/` is tracked, so the citations in the scripts and references stay resolvable for installed users.

### Compatibility note — the `plugins/harness-factory` symlink

`plugins/harness-factory` is a **self-referential symlink** pointing at the repository root (`-> ../`). It lets the plugin resolve under a `plugins/<name>` path without duplicating any files. Symlinks can be fragile on **Windows** checkouts: Git only materializes them when symlink support is enabled (`git config core.symlinks true`, plus OS-level permission such as Developer Mode). Windows users who see a plain text file where the link should be may need to enable symlink support and re-checkout. Do **not** delete the symlink — it is intentional.

## harness-ops integration

If [harness-ops](https://github.com/hyunho058/harness-ops) is installed, you can also trigger this skill via:

```
/harness-ops:generate-team
```

The harness-ops wrapper checks whether harness-factory is installed and delegates to this skill automatically.

## Extending an existing harness

Re-run `/generate-team` at any time. The Phase 0 audit detects the current harness state and runs only the phases needed for the requested change (add agent, add skill, architecture change). Existing agents and skills are preserved unless explicitly modified.
