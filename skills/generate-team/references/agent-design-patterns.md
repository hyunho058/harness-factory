# Agent Team Design Patterns

## Execution Modes: Agent Teams vs Sub-agents

Understand the key differences between the two execution modes and choose the appropriate one.

> **Primitive availability comes first (target-environment check).** Agent-team
> mode is built on `TeamCreate` / `TeamDelete` / `SendMessage` / `TaskCreate`.
> Those primitives are **not present in every Claude Code version or session** —
> availability can depend on the version and on whether FleetView is enabled.
> Sub-agent mode uses only the `Agent` tool, which is **always available**. So
> treat "are the team primitives exposed in the target environment?" as the
> **first** gate of the decision tree below: if `TeamCreate` is not available,
> choose **Sub-agent** regardless of collaboration needs — it is the safe fallback
> and the orchestrator is still correct, just without live inter-agent messaging.
> Team remains the preferred mode *where the primitives exist*. Do **not** globally
> redefine the default to Sub-agent without first **measuring** primitive
> availability in the target Claude Code version; team is genuinely better where it
> is available.

### Agent Teams — Default Mode

The team leader uses `TeamCreate` to form a team, and members run as independent Claude Code instances. Members communicate directly via `SendMessage` and self-coordinate using a shared task list (`TaskCreate`/`TaskUpdate`).

```
[Leader] ←→ [Member A] ←→ [Member B]
   ↕              ↕              ↕
   └──── Shared task list ────────┘
```

**Core tools:**
- `TeamCreate`: create team + spawn members
- `SendMessage({to: name})`: message a specific member
- `SendMessage({to: "all"})`: broadcast (high cost, use sparingly)
- `TaskCreate`/`TaskUpdate`: manage shared task list

**Characteristics:**
- Members can talk, challenge, and validate each other directly
- Members exchange information without going through the leader
- Self-coordinate via shared task list (members can claim their own tasks)
- Leader is automatically notified when a member goes idle
- Plan approval mode allows review before risky operations

**Constraints:**
- Only one team can be **active** per session (though you can dissolve and create a new team between phases)
- No nested teams (members cannot create their own team)
- Leader is fixed (cannot be transferred)
- High token cost

**Team reconfiguration pattern:**
If different specialist combinations are needed per phase, save the previous team's outputs to files → clean up the team → create a new team. Previous outputs are preserved in `_workspace/` so the new team can access them via Read.

### Sub-agents — Lightweight Mode

The main agent creates sub-agents using the `Agent` tool. Sub-agents return results only to the main agent and do not communicate with each other.

```
[Main] → [Sub A] → return result
       → [Sub B] → return result
       → [Sub C] → return result
```

**Core tool:**
- `Agent(prompt, subagent_type, run_in_background)`: create sub-agent

**Characteristics:**
- Lightweight and fast
- Results are summarized and returned to the main context
- Token-efficient

**Constraints:**
- No communication between sub-agents
- Main agent handles all coordination
- No real-time collaboration or challenge

### Mode Selection Decision Tree

```
Team primitives (TeamCreate/SendMessage/TaskCreate) available in the target env?
├── No → Sub-agent  (only the always-available Agent tool; safe fallback)
│
└── Yes → 2 or more agents?
          ├── Yes → Do agents need to communicate?
          │         ├── Yes → Agent team (default)
          │         │         Cross-validation, shared findings, real-time feedback improve quality.
          │         │
          │         └── No → Sub-agents also viable
          │                  For produce-verify, expert pools where only result passing is needed.
          │
          └── No (1 agent) → Sub-agent
                             No need for team setup with a single agent.
```

> **Core principle:** Agent teams are the default. When choosing sub-agents, ask: "Is inter-member communication truly unnecessary?"

---

## Agent Team Architecture Patterns

### 1. Pipeline
Sequential workflow. The output of one agent becomes the input of the next.

```
[Analyze] → [Design] → [Implement] → [Verify]
```

**When to use:** Each stage strongly depends on the previous stage's output
**Example:** Novel writing — world-building → characters → plot → writing → editing
**Note:** A bottleneck delays the entire pipeline. Design each stage to be as independent as possible.
**Team mode fit:** Limited benefit from team mode due to strong sequential dependencies. Useful if there are parallel sections within the pipeline.

### 2. Fan-out/Fan-in
Parallel processing followed by result integration. Performs independent tasks simultaneously.

```
           ┌→ [Expert A] ─┐
[Dispatch] ─┼→ [Expert B] ─┼→ [Integrate]
           └→ [Expert C] ─┘
```

**When to use:** Different perspectives or domains need to analyze the same input
**Example:** Comprehensive research — official/media/community/background sources investigated simultaneously → integrated report
**Note:** The quality of the integration stage determines overall quality.
**Team mode fit:** The most natural pattern for agent teams. **Always build as an agent team.** Members share findings and challenge each other; one agent's discovery can redirect another agent's investigation in real time, significantly improving quality over solo research.

### 3. Expert Pool
Select and call the appropriate expert based on context.

```
[Router] → { Expert A | Expert B | Expert C }
```

**When to use:** Different processing is needed depending on input type
**Example:** Code review — call only the relevant expert from security/performance/architecture specialists
**Note:** The router's classification accuracy is critical.
**Team mode fit:** Sub-agents are more appropriate. No need for a standing team when only the needed expert is called.

### 4. Producer-Reviewer
A producer agent and a reviewer agent operate in tandem.

```
[Produce] → [Review] → (if issues) → [Produce] retry
```

**When to use:** Output quality assurance is important and objective review criteria exist
**Example:** Webtoon — artist produces → reviewer inspects → re-generate problem panels
**Note:** Set a maximum retry count (2–3) to prevent infinite loops.
**Team mode fit:** Agent teams are useful. Real-time feedback between producer and reviewer via SendMessage.

### 5. Supervisor
A central agent manages task state and dynamically distributes work to worker agents.

```
             ┌→ [Worker A]
[Supervisor] ─┼→ [Worker B]    ← Supervisor monitors state and distributes dynamically
             └→ [Worker C]
```

**When to use:** Workload is variable or task distribution must be decided at runtime
**Example:** Large-scale code migration — supervisor analyzes file list and assigns batches to workers
**Difference from fan-out:** Fan-out pre-assigns tasks; supervisor adjusts dynamically based on progress
**Note:** Keep delegation units large enough to prevent the supervisor from becoming a bottleneck.
**Team mode fit:** The shared task list of agent teams maps naturally to the supervisor pattern. Register tasks with TaskCreate; members claim them.

### 6. Hierarchical Delegation
Higher-level agents delegate recursively to lower-level agents. Decomposes complex problems step by step.

```
[Director] → [Lead A] → [Worker A1]
                       → [Worker A2]
           → [Lead B] → [Worker B1]
```

**When to use:** The problem decomposes naturally into a hierarchical structure
**Example:** Full-stack app development — director → frontend lead → (UI/logic/tests) + backend lead → (API/DB/tests)
**Note:** 3+ levels of depth increases latency and context loss significantly. Keep to 2 levels max.
**Team mode fit:** Agent teams cannot be nested (members cannot create teams). Implement the first level as a team and the second level as sub-agents, or flatten into a single team.

## Composite Patterns

In practice, composite patterns are more common than single patterns:

| Composite Pattern | Composition | Example |
|----------|------|------|
| **Fan-out + Producer-Reviewer** | Parallel production then individual review | Multi-language translation — 4 languages translated in parallel → each reviewed by a native reviewer |
| **Pipeline + Fan-out** | Parallelize some stages within a sequential pipeline | Analysis (sequential) → Implementation (parallel) → Integration test (sequential) |
| **Supervisor + Expert Pool** | Supervisor dynamically calls experts | Customer inquiry handling — supervisor classifies inquiry then assigns to appropriate expert |

### Execution Modes in Composite Patterns

**Use agent teams for all composite patterns by default.** Active communication between members is the core driver of output quality.

| Scenario | Recommended Mode | Reason |
|---------|----------|------|
| **Research + Analysis** | Agent team | Investigators share findings, debate conflicting information in real time |
| **Design + Implementation + Verification** | Agent team | Feedback loop between designer ↔ implementer ↔ verifier |
| **Supervisor + Workers** | Agent team | Dynamic assignment via shared task list, workers share progress |
| **Produce + Review** | Agent team | Real-time feedback between producer ↔ reviewer minimizes rework |

> Consider mixing in sub-agents only when a single agent performs a completely isolated one-shot task.

## Agent Type Selection

Specify the type using the `subagent_type` parameter of the Agent tool when calling an agent. Team members can also use custom agent definitions.

### Built-in Types

| Type | Tool access | Best for |
|------|----------|-----------|
| `general-purpose` | Full access (including WebSearch, WebFetch) | Web research, general tasks |
| `Explore` | Read-only (no Edit/Write) | Codebase exploration, analysis |
| `Plan` | Read-only (no Edit/Write) | Architecture design, planning |

### Custom Types

Define an agent in `.claude/agents/{name}.md` and call it with `subagent_type: "{name}"`. Custom agents have full tool access.

### Selection Criteria

| Situation | Recommended | Reason |
|------|------|------|
| Complex role reused across multiple sessions | **Custom type** (`.claude/agents/`) | Manage persona and working principles in a file |
| Simple research/collection where a prompt is sufficient | **`general-purpose`** + detailed prompt | No agent file needed; include instructions in the prompt |
| Read-only code access needed (analysis/review) | **`Explore`** | Prevents accidental file modification |
| Design/planning only | **`Plan`** | Focus on analysis, prevent code changes |
| Implementation work requiring file modification | **Custom type** | Full tool access + specialized instructions |

**Principle:** Always define every agent as a `.claude/agents/{name}.md` file. Even for built-in types, create an agent definition file to specify the role, principles, and protocol. Files enable reuse across sessions, and explicit team communication protocols ensure collaboration quality.

**Model:** All agents use `model: "opus"`. Always specify the `model: "opus"` parameter when calling the Agent tool.

## Agent Definition Structure

```markdown
---
name: agent-name
description: "1-2 sentence role description. List trigger keywords."
---

# Agent Name — One-line role summary

You are a [role] expert in [domain].

## Core Responsibilities
1. Responsibility 1
2. Responsibility 2

## Working Principles
- Principle 1
- Principle 2

## Input/Output Protocol
- Input: [what is received and from where]
- Output: [what is written and where]
- Format: [file format, structure]

## Team Communication Protocol (Agent Team Mode)
- Receive messages: [from whom and what type of messages]
- Send messages: [to whom and what type of messages]
- Claim tasks: [what types of tasks to claim from the shared task list]

## Error Handling
- [behavior on failure]
- [behavior on timeout]

## Collaboration
- Relationships with other agents
```

## Agent Separation Criteria

| Criterion | Separate | Merge |
|------|------|------|
| Expertise | Separate if domains differ | Merge if domains overlap |
| Parallelism | Separate if can run independently | Consider merging if sequentially dependent |
| Context | Separate if context load is large | Merge if lightweight and fast |
| Reusability | Separate if used by other teams | Consider merging if only used by this team |

## Skills vs Agents

| | Skill | Agent |
|------|-------------|-----------------|
| Definition | Procedural knowledge + tool bundle | Expert persona + behavioral principles |
| Location | `.claude/skills/` | `.claude/agents/` |
| Trigger | User request keyword matching | Explicit call via Agent tool |
| Size | Small to large (workflows) | Small (role definition) |
| Purpose | "How to do it" | "Who does it" |

Skills are **procedural guides** that agents reference when performing tasks.
Agents are **expert role definitions** that leverage skills.

## Skill ↔ Agent Connection Methods

Three ways agents can leverage skills:

| Method | Implementation | When to use |
|------|------|-----------|
| **Skill tool call** | Specify `call /skill-name via the Skill tool` in the agent prompt | Skill is an independent workflow and can be user-invoked |
| **Inline in prompt** | Include skill content directly in the agent definition | Skill is short (≤50 lines) and exclusive to this agent |
| **Reference load** | Load the skill's `references/` files via `Read` on demand | Skill content is large and only conditionally needed |

Recommendation: use Skill tool for high reusability, inline for exclusive use, reference load for large content.
