---
description: "Interview-driven team design — runs the audit + domain analysis + architecture design, emits specs/<team>/design.md (status: draft), and STOPS without generating any .claude/* files. Run when the user asks to 'design team', 'design harness', 'design agent team', 'plan a team', 'spec out a team', '설계만', '팀 설계', 'design only (no build)', or wants the reviewable design spec before approving and building."
argument-hint: "<team> [project description]"
allowed-tools: [Read, Grep, Glob, Bash, Write, Edit, AskUserQuestion]
---

Read `${CLAUDE_PLUGIN_ROOT}/skills/team-design/SKILL.md` and follow its instructions exactly.

User arguments: $ARGUMENTS
