---
description: "Design and build agent team architecture — analyzes the project codebase and auto-generates .claude/agents/, .claude/skills/, and CLAUDE.md. Run when the user asks to 'generate team', 'build agent team', 'build agent pod', 'set up agent architecture', or 'create agent team'."
argument-hint: "[project description or leave empty to scan CWD]"
allowed-tools: [Read, Grep, Glob, Bash, Write, Edit, Agent, Task, AskUserQuestion, TeamCreate, TeamDelete, SendMessage, TaskCreate, TaskUpdate]
---

Read `${CLAUDE_PLUGIN_ROOT}/skills/generate-team/SKILL.md` and follow its instructions exactly.

User arguments: $ARGUMENTS
