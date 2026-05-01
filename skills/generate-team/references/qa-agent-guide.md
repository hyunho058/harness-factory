# QA Agent Design Guide

Reference guide for including a QA agent in a build harness. Based on bug patterns discovered in real projects (SatangSlide) and root-cause analysis, this guide provides a systematic verification methodology for catching defects that QA agents commonly miss.

---

## Table of Contents

1. Defect Patterns QA Agents Miss
2. Integration Coherence Verification
3. QA Agent Design Principles
4. Verification Checklist Template
5. QA Agent Definition Template

---

## 1. Defect Patterns QA Agents Miss

### 1-1. Boundary Mismatch

The most frequent defect type. Two components are each implemented "correctly," but the contract breaks at the connection point.

| Boundary | Mismatch Example | Why It Gets Missed |
|----------|-----------------|-------------------|
| API response → frontend hook | API returns `{ projects: [...] }`, hook expects `SlideProject[]` | Each side validates individually; no cross-comparison |
| API response field name → type definition | API uses `thumbnailUrl` (camelCase), type uses `thumbnail_url` (snake_case) | TypeScript generics cast it; compiler doesn't catch it |
| File path → link href | Page lives at `/dashboard/create`, link points to `/create` | File structure and href are not cross-compared |
| State transition map → actual status updates | Map defines `generating_template → template_approved`, code omits the transition | Only checks map exists; doesn't trace all update code |
| API endpoint → frontend hook | API exists but no corresponding hook (never called) | API list and hook list are not mapped 1:1 |
| Immediate response → async result | API immediately returns `{ status }`, frontend accesses `data.failedIndices` | Type-checks without distinguishing sync vs async response shape |

### 1-2. Why Static Code Review Misses These

- **TypeScript generic limitation**: `fetchJson<SlideProject[]>()` — passes compilation even if runtime response is `{ projects: [...] }`
- **`npm run build` passing ≠ correct behavior**: type casting, `any`, and generics let builds succeed while runtime fails
- **Existence check vs connection check**: "Does the API exist?" and "Does the API response match the caller's expectation?" are entirely different verifications

---

## 2. Integration Coherence Verification

**Cross-comparison verification** areas that must be included in every QA agent.

### 2-1. API Response ↔ Frontend Hook Type Cross-Verification

**Method**: Compare each API route's `NextResponse.json()` call shape against the corresponding hook's `fetchJson<T>` type parameter.

```
Verification steps:
1. Extract the shape of the object passed to NextResponse.json() in each API route
2. Check the T type in the corresponding hook's fetchJson<T>
3. Compare shape and T for a match
4. Check for wrapping (if API returns { data: [...] }, verify the hook unwraps .data)
```

**Patterns requiring special attention:**
- Pagination APIs: `{ items: [], total, page }` vs frontend expecting an array
- snake_case DB fields → camelCase API response → frontend type definition mismatches
- Immediate response (202 Accepted) vs final result shape difference

### 2-2. File Path ↔ Link/Router Path Mapping

**Method**: Extract URL paths from page files under `src/app/` and cross-reference with all `href`, `router.push()`, and `redirect()` values in the codebase.

```
Verification steps:
1. Extract URL patterns from page.tsx file paths under src/app/
   - (group) → removed from URL
   - [param] → dynamic segment
2. Collect all href=, router.push(, redirect( values in the codebase
3. Verify each link matches an actual existing page path
4. Account for URL prefixes of pages inside route groups (e.g. under dashboard/)
```

### 2-3. State Transition Completeness Tracking

**Method**: Extract all `status:` updates from the codebase and cross-reference with the state transition map.

```
Verification steps:
1. Extract the list of permitted transitions from the state transition map (STATE_TRANSITIONS)
2. Search all API routes for .update({ status: "..." }) patterns
3. Verify each transition is defined in the map
4. Identify transitions defined in the map but never executed in code (dead transitions)
5. Specifically: check that intermediate state (e.g. generating_template) → final state (template_approved) transitions are not missing
```

### 2-4. API Endpoint ↔ Frontend Hook 1:1 Mapping

**Method**: List all API routes and frontend hooks, then verify they pair up correctly.

```
Verification steps:
1. Extract the list of HTTP method/endpoint pairs from route.ts files under src/app/api/
2. Extract the list of fetch call URLs from use*.ts files under src/hooks/
3. Identify API endpoints not called by any hook → flag as "unused"
4. Determine whether "unused" is intentional (e.g. admin API) or an oversight (missing call)
```

---

## 3. QA Agent Design Principles

### 3-1. Use general-purpose type, not Explore type

A QA agent of type `Explore` is read-only. Effective QA requires:
- Grep for pattern searches (extract all `NextResponse.json()` calls)
- Script execution for automated cross-comparison (API shape vs hook type)
- The ability to make fixes when needed

**Recommendation**: Set type to `general-purpose`, and explicitly specify the "verify → report → request fix" protocol in the agent definition.

### 3-2. Prioritize cross-comparison over existence checks in checklists

| Weak Checklist | Strong Checklist |
|---------------|-----------------|
| Does the API endpoint exist? | Does the API endpoint's response shape match the corresponding hook's type? |
| Is the state transition map defined? | Do all status update code paths match the transitions in the map? |
| Does the page file exist? | Do all links in the codebase point to pages that actually exist? |
| Is TypeScript strict mode enabled? | Is there any type safety bypassed via generic casting? |

### 3-3. "Read both sides simultaneously" principle

To catch boundary bugs, reading only one side is insufficient. Always:
- Read the API route **and** the corresponding hook **together**
- Read the state transition map **and** the actual update code **together**
- Read the file structure **and** the link paths **together**

State this principle explicitly in the agent definition.

### 3-4. Run QA immediately after each module completes, not after the full build

Placing QA only at "Phase 4: after full completion" in the orchestrator causes:
- Bug accumulation, increasing the cost of fixes
- Early boundary mismatches propagating to downstream modules

**Recommended pattern**: Run cross-verification for each backend API and its corresponding hook immediately after the API is complete (incremental QA).

---

## 4. Verification Checklist Template

Integration coherence checklist for web applications to include in QA agent definitions.

```markdown
### Integration Coherence Verification (Web App)

#### API ↔ Frontend Connection
- [ ] Response shape of every API route matches the generic type of the corresponding hook
- [ ] Wrapped responses ({ items: [...] }) are unwrapped in the hook
- [ ] snake_case ↔ camelCase conversion is applied consistently
- [ ] Immediate responses (202) and final result shapes are distinguished correctly on the frontend
- [ ] Every API endpoint has a corresponding frontend hook that is actually called

#### Routing Coherence
- [ ] Every href/router.push value in the codebase matches an actual page file path
- [ ] Route group ((group)) URL removal is accounted for in path verification
- [ ] Dynamic segments ([id]) are populated with the correct parameters

#### State Machine Coherence
- [ ] Every defined state transition is executed in code (no dead transitions)
- [ ] Every status update in code is defined in the transition map (no unauthorized transitions)
- [ ] Intermediate → final state transitions are not missing
- [ ] Status-based branches on the frontend (if status === "X") use values that are actually reachable

#### Data Flow Coherence
- [ ] DB schema field names and API response field names are mapped consistently
- [ ] Frontend type definitions and API response field names match
- [ ] null/undefined handling for optional fields is consistent on both sides
```

---

## 5. QA Agent Definition Template

Core sections to include in a build harness QA agent.

```markdown
---
name: qa-inspector
description: "QA verification specialist. Validates spec compliance, integration coherence, and design quality."
---

# QA Inspector

## Core Role
Verify implementation quality against spec and **integration coherence between modules**.

## Verification Priority

1. **Integration coherence** (highest) — boundary mismatches are the primary cause of runtime errors
2. **Functional spec compliance** — API / state machine / data model
3. **Design quality** — colors / typography / responsiveness
4. **Code quality** — unused code, naming conventions

## Verification Method: "Read Both Sides Simultaneously"

For boundary verification, always **open both sides of the code at once** and compare:

| Verification Target | Left Side (Producer) | Right Side (Consumer) |
|--------------------|---------------------|----------------------|
| API response shape | route.ts NextResponse.json() | hooks/ fetchJson<T> |
| Routing | src/app/ page file paths | href, router.push values |
| State transitions | STATE_TRANSITIONS map | .update({ status }) code |
| DB → API → UI | table column names | API response fields → type definitions |

## Team Communication Protocol

- On discovery: send a specific fix request to the responsible agent (file:line + how to fix)
- For boundary issues: notify **both** agents on either side of the boundary
- To leader: verification report (pass / fail / unverified items clearly distinguished)
```

---

## Real Cases: Bugs Found in SatangSlide

All content in this guide is drawn from lessons extracted from the following real bugs:

| Bug | Boundary | Root Cause |
|-----|----------|-----------|
| `projects?.filter is not a function` | API→hook | API returned `{projects:[]}`, hook expected array |
| All dashboard links returned 404 | File path→href | Missing `/dashboard/` prefix |
| Theme image not displayed | API→component | `thumbnailUrl` vs `thumbnail_url` |
| Theme selection not saved | API→hook | select-theme API existed, hook was missing |
| Generation page waited forever | State transition→code | `template_approved` transition code was missing |
| `data.failedIndices` crash | Immediate response→frontend | Background result accessed from immediate response |
| View slides after completion returned 404 | File path→href | `/projects/` → `/dashboard/projects/` |
