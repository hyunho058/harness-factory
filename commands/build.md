---
description: "Gated harness build — hard-gates an APPROVED specs/<team>/design.md (exists + status: approved + checksum matches), then generates .claude/agents/, .claude/skills/, and CLAUDE.md from the spec ONLY (no interview). Run when the user asks to 'build team', 'build harness', 'build from spec', 'build agent team', 'generate from approved design', '빌드', '스펙으로 생성', or wants to materialize a design that has already been approved."
argument-hint: "<team>"
allowed-tools: [Read, Grep, Glob, Bash, Write, Edit]
---

Read `${CLAUDE_PLUGIN_ROOT}/skills/team-build/SKILL.md` and follow its instructions exactly.

User arguments: $ARGUMENTS
