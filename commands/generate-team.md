---
description: "Generate an agent team architecture (.claude/agents/, .claude/skills/, CLAUDE.md). The default is the gated design→approve→build flow: this command routes you to `/harness-factory:design` → `scripts/approve` → `/harness-factory:build`. Pass `--skip-design` to use the legacy one-shot escape hatch that generates everything in a single run without an approval gate. Run when the user asks to 'generate team', 'build agent team', 'build agent pod', 'set up agent architecture', or 'create agent team'."
argument-hint: "[--skip-design] [project description or leave empty to scan CWD]"
allowed-tools: [Read, Grep, Glob, Bash, Write, Edit, Agent, Task, AskUserQuestion, TeamCreate, TeamDelete, SendMessage, TaskCreate, TaskUpdate]
---

Read `${CLAUDE_PLUGIN_ROOT}/skills/generate-team/SKILL.md` and follow its instructions exactly.

User arguments: $ARGUMENTS
