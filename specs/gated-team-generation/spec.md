# Spec: gated-team-generation

## Meta
- **Created**: 2026-06-11
- **Type**: dev
- **Status**: Approved
- **Layer**: L4 - Tasks
- **Approved by**: user
- **Approved at**: 2026-06-11

## Goal
harness-factory의 `generate-team`을 지금의 원샷 생성 흐름에서 게이트가 걸린 2단계 흐름
(인터뷰 → 설계 스펙 산출 → [사람 승인] → 빌드)으로 리팩터링한다. "검토 비용을
O(출력)→O(설계)로" 명제를 플러그인 메커니즘으로 못 박는 것이 핵심.

## Non-goals
- harness-ops 쪽 orchestrate 로직 변경 (경계는 L1에서 확인; factory가 scaffold, ops가 orchestrate)
- 생성되는 도메인 팀의 *내용물* 품질 개선 (agent/skill 설계 품질) — 이번 변경은 생성 워크플로의 게이트 메커니즘만 다룬다
- 새로운 실행 모드(team/sub/hybrid) 추가

## Confirmed Goal
`generate-team`을 design 단계와 build 단계로 분리한다:
- **design**: 인터뷰 → 사람이 읽고 고칠 수 있는 설계 스펙 파일을 산출하고 멈춤
- **[사람 승인]**: 스펙 파일을 검토/수정/승인 (승인 시맨틱 정의 필요)
- **build**: 승인된 스펙만 읽어 harness(.claude/agents, .claude/skills, CLAUDE.md) 생성
- **하드 거부 게이트**: 스펙 없음 / status != approved / 승인 후 변조(체크섬 불일치) 시 build 거부
- **하위 호환**: 기존 원샷 경로를 탈출구로 유지

완료 기준: 실제 팀 하나를 design→승인→build로 통과시켜 scaffold가 나오고,
승인 없이/변조 후 build를 돌리면 거부되는 것이 재현된다.

## Research

### 현재 generate-team 구조 (단일 원샷)
- `skills/generate-team/SKILL.md`가 Phase 0~6을 한 번의 호출로 실행 (`skills/generate-team/SKILL.md:32`)
- Phase 0 현황 감사 → Phase 1 도메인 분석 → Phase 2 아키텍처 설계 → Phase 3 에이전트 정의 파일 생성 → Phase 4 스킬 생성 → Phase 5 오케스트레이터+CLAUDE.md → Phase 6 검증
- **핵심 seam (입력→출력 분기점)**: Phase 2와 Phase 3 사이. Phase 0~2는 순수 *결정*(팀명·에이전트 목록·스킬·패턴 선택)이고 파일 생성이 없음. Phase 3~6이 파일을 *물질화*(`.claude/agents/`, `.claude/skills/`, `CLAUDE.md`)함 (`skills/generate-team/SKILL.md:93`, `:116`, `:184`)
- 즉 **설계 스펙 = Phase 0~2의 산출물** = 사용자가 A2에서 요구한 스키마(팀명/목적, 에이전트 목록[역할·툴], 스킬 목록, 불변식/게이트, 에스컬레이션, 파일 레이아웃, non-goals)와 정확히 일치
- 현재 승인 게이트 없음 — 인터뷰 도중 AskUserQuestion으로 실행 계획만 확인 (`skills/generate-team/SKILL.md:50`)

### 플러그인 컨벤션
- 커맨드 패턴: frontmatter(description, argument-hint, allowed-tools) + `Read ${CLAUDE_PLUGIN_ROOT}/skills/{name}/SKILL.md and follow its instructions exactly.` (`commands/generate-team.md:7`)
- 스킬 위치: `skills/{name}/SKILL.md` + `references/` (`skills/generate-team/`)
- 커맨드 네임스페이스: `/harness-factory:{name}` 및 짧은 `/{name}` 별칭 (README.md:7)
- 플러그인 루트 심링크: `plugins/harness-factory -> ../` (marketplace `source: "./plugins/harness-factory"`) (`.claude-plugin/marketplace.json:13`)
- 커맨드는 모델/Claude가 SKILL.md를 읽어 실행하는 위임 방식 — 결정 로직(스펙 스키마·체크섬·거부)을 SKILL.md 본문에 둘 수 있음. 별도 실행 바이너리 없음

### harness-ops 경계
- factory=scaffold(팀 생성), ops=orchestrate/audit — 역할 분리 확정 (`specs/integrate-harness-main/spec.md:40-43`)
- ops에는 `/harness-ops:generate-team` **래퍼 커맨드**만 존재; ops 스킬 로직 변경 없음이 기존 제약 (`specs/integrate-harness-main/spec.md:104`, D4)
- 래퍼는 `~/.claude/plugins/harness-factory/skills/generate-team/SKILL.md`를 읽어 위임 → **커맨드를 design/build로 쪼개면 ops 래퍼도 따라가야 하는지가 L2 결정 대상**
- 게이트 로직은 factory 내부에 갇힘 (ops 미접촉) — Non-goal과 정합

### 멱등성/하위호환 관련 현황
- 현재 generate-team은 Phase 0에서 기존 하네스를 감사하고 신규/확장/유지보수로 분기 — 재실행(확장) 개념이 이미 내장 (`skills/generate-team/SKILL.md:34-51`)
- 따라서 build 멱등성은 기존 Phase 0 audit 메커니즘 위에 얹을 수 있음 (덮어쓰기 vs diff는 L2 결정)
- 기존 원샷 진입점(`/generate-team`)이 README/커맨드에 노출되어 있어 하위호환 탈출구 설계 필요 (README.md:33)

## Decisions

### D1: 게이트 메커니즘 = 2-커맨드 + 스펙 파일 핸드오프
- **Status**: resolved
- **Rationale**: `design` 커맨드가 설계 스펙 파일을 산출하고 멈춤 → 사람이 파일을 검토/수정/승인 → `build` 커맨드가 승인된 스펙만 읽어 harness 생성. "검토 비용 O(출력)→O(설계)" 명제와 정확히 정합. 승인 산출물이 git에 남아 추적 가능, 헤드리스 자동화와 비충돌. 반려 대안: (b) 단일 커맨드 in-session 일시정지 — 비대화형/자동 실행에서 취약하고 승인 흔적이 git에 안 남음. (c) PR 기반 — 추적성은 강하나 GitHub 의존·로컬 단독 실행 UX 저하로 과중.
- **직렬화 손실 반론(steelman) 및 완화**: 2-커맨드는 build를 무상태 재유도로 만들어, 원샷 흐름이 Phase 0~2의 라이브 추론(코드 감사·도메인 분석·반려 대안의 *왜*)을 들고 Phase 3~6을 돌리던 컨텍스트를 잃는다 → build가 손실 스냅샷에서 에이전트/스킬 *본문*을 재생성하면 원샷보다 품질이 낮아질 위험(Non-goal "팀 품질 저하 금지"와 충돌). **완화**: D5의 풀 계약 스키마(Invariants·Escalation·에이전트별 툴/모델/책임까지)가 build의 *유일* 입력으로 충분하도록 의도적으로 풍부하게 설계됨 — 즉 직렬화가 무손실에 가깝도록 스키마가 계약을 담는다. design 단계는 *왜*(반려 근거)도 스펙에 기록해 build가 이미 기각된 대안을 재평가하지 않게 한다.

### D2: build 하드 거부 = 체크섬 불일치 시 거부 + 재승인 요구
- **Status**: resolved
- **Rationale**: 승인 시점의 스펙 해시를 동결해두고 build가 재계산해 비교. 불일치 시 하드 거부하고 사람에게 재승인을 요구. "승인 받고 몰래 바꿔서 빌드"(`{{ ds }}` 교훈) 경로를 기계 불변식으로 차단. 반려 대안: 자동 design 되돌림 — 의도적 재편집과 사고성 변조를 구분 못 함; 경고 후 진행 — 게이트 의미 무력화.

### D3: 승인+동결 = `scripts/approve` 헬퍼 스크립트
- **Status**: resolved
- **Rationale**: 사람이 design.md를 자유롭게 수정한 뒤 `scripts/approve <team>` 실행 → `status: approved` 설정 + 그 시점 본문(`checksum` **및** `status` 메타 필드 제외 — approve가 `status`를 mutate하는 순간이라 반드시 제외해야 오탐 0)의 sha256을 frontmatter에 동결. build가 동일 규칙으로 재계산해 비교. 결정적이며 수기 해시 입력 불필요. **체크섬 자기참조 회피**: 해시 대상에서 `checksum`/`status` 메타 필드 제외(U/U Tier3). 반려 대안: build 첫 실행 시 동결 — 첫 빌드 전 변조 미차단; .lock 사이드카 — 파일 2개 관리 부담에 비해 이점 없음(사이드카도 변조 가능).

### D4: 하위호환 = 게이트 기본 + `--skip-design` 탈출구, ops 래퍼는 design/build 둘 다 위임
- **Status**: resolved
- **Rationale**: design/build 2-커맨드가 기본 게이트 경로. 기존 `/generate-team`은 `--skip-design` 플래그로 원샷 탈출구 유지(플래그 없이 호출 시 게이트 경로로 안내). harness-ops 래퍼는 design·build 둘 다 위임하도록 확장(ops 스킬 로직 미변경, 커맨드 파일만 추가 — 기존 제약 준수). 반려 대안: 원샷 완전 폐기 — 기존 사용자 흐름·README 파손; 원샷 기본 유지+게이트 옵션 — 도그푸딩 압박이 약해 게이트가 안 쓰임.

### D5: 설계 스펙 스키마 = 풀 계약
- **Status**: resolved
- **Rationale**: 승인 대상 `design.md`는 다음을 포함한다 — frontmatter(`team`, `status`, `checksum`) + 본문 섹션: Purpose, Non-goals, Agents(이름·역할·책임·허용툴·모델), Skills(이름·목적·소속 에이전트), Execution Mode, **Invariants/Gates(이 팀이 강제하는 것)**, Escalation Rules, File Layout(생성될 경로). 이 필드 집합이 곧 design↔build 계약이며 build는 이 섹션들만 읽어 생성. 반려 대안: 코어 계약(불변식·에스컬레이션 제외) — 게이트가 강제할 불변식이 스펙에 안 박혀 핵심 가치 누락; 스키마 자유 — build가 기대할 필드가 없어 검증·파싱 불안정.

### D6: 재실행 멱등성 = Phase 0 audit 기반 병합
- **Status**: resolved
- **Rationale**: 기존 generate-team의 Phase 0 audit 분기(신규/확장/유지보수)를 build가 재사용. 스펙에 있으나 파일에 없는 것은 생성, 변경된 것만 갱신, 손대지 않은 것은 보존. 전체 덮어쓰기 아님. 반려 대안: 전체 덮어쓰기 — 사람이 산출물에 직접 가한 수정 유실; diff/patch 미리보기 — 게이트 위에 또 하나의 승인 단계를 얹어 과중.
- **체크섬 범위 = 스펙 전용(산출물 미포함)**: D2의 체크섬 게이트는 *스펙(design.md)* 변조만 검출하며 *산출물(.claude/\*)* 무결성은 검사하지 않는다. 이는 의도적 — D6가 사람의 산출물 직접 수정을 보존하기 때문. 따라서 게이트 의미는 "승인된 *설계*대로 빌드함"이지 "산출물이 설계와 일치함"이 아니다.
- **병합 우선순위(merge precedence)**: build가 Phase 0 audit에서 산출물이 승인된 스펙과 분기(divergence)한 것을 발견하면 — **존재/구조(어떤 에이전트·스킬이 존재하는가, 선언된 허용툴·파일 레이아웃)는 스펙이 진실의 원천(spec wins)**, **본문(에이전트/스킬 .md의 사람 수정 내용)은 보존하되 분기를 경고(preserve-and-warn)**. 즉 스펙에 없는데 파일에 있으면 경고만, 스펙에 있는데 파일이 구조적으로 어긋나면 스펙 기준으로 정정.
- **변경 검출 키(L3에서 정밀화)**: "변경된 것만 갱신"의 판정 키 = 스펙의 File Layout 항목 및 각 에이전트/스킬 섹션을 직전 빌드 산출물과 대조 — 섹션이 바뀐 에이전트/스킬만 재생성. (Phase 0 audit는 drift만 감지하므로 이 per-file 병합 의미를 L3 요구사항에서 구체화)

## Constraints
- **체크섬 정규화**: `scripts/approve`(동결)와 build(검증)는 동일한 해시 알고리즘+정규화를 공유해야 한다 — 본문에서 `checksum`/`status` 메타 필드를 제외하고, 줄바꿈(LF)·말미 공백을 정규화한 후 sha256. approve↔build 간 오탐(false mismatch) 0건이 불변식. (Inversion Probe에서 도출 — 오탐 시 사용자가 `--skip-design`로 도피해 게이트 사망)
- harness-ops 스킬 로직 미변경 — 래퍼 커맨드 파일 추가만 허용 (기존 integrate-harness-main 제약 계승)
- generate-team SKILL.md 본문 500줄 이내 유지 (게이트 로직 추가로 초과 시 references/로 분리)
- 기존 `/harness-factory:generate-team` 원샷 진입점은 `--skip-design`로 보존 — 기존 사용자 흐름 비파손

## Known Gaps
- design 단계 중단→재개 흐름 (인터뷰 중간 종료 후 다시 design 실행 시 이전 진행 복원 여부) — L2 provisional, 구현 시 `status: draft` 재진입으로 처리 가능
- "사람이 읽지 않고 rubber-stamp 승인" 리스크 — 게이트 설계 본질상 완전 차단 불가(인적 요소), 수용. approve 헬퍼가 변경 요약을 출력해 완화 가능

## Requirements

### R0: 게이트 걸린 2단계 generate-team (Confirmed Goal)

#### R0.1: design→승인→build 엔드투엔드 해피패스
- **Given**: 빈 대상 프로젝트에서 사용자가 `/harness-factory:design <team>` 실행
- **When**: 인터뷰로 design.md 산출 → `scripts/approve <team>`로 승인 → `/harness-factory:build <team>` 실행
- **Then**: `.claude/agents/`, `.claude/skills/`, `CLAUDE.md` 3종이 승인된 스펙대로 생성된다

### R1: design 커맨드 — 스펙 산출 후 정지 (D1)

#### R1.1: design이 인터뷰(Phase 0~2)를 수행하고 스펙을 쓴다
- **Given**: 사용자가 `/harness-factory:design <team>` 실행
- **When**: Phase 0 audit → Phase 1 도메인 분석 → Phase 2 아키텍처 설계 완료
- **Then**: `specs/<team>/design.md`가 생성되고 frontmatter `status: draft`, `checksum:` 빈 값으로 초기화된다

#### R1.2: design은 산출물 파일을 생성하지 않고 멈춘다
- **Given**: design이 design.md 작성을 마친 상태
- **When**: design 커맨드 실행이 종료될 때
- **Then**: `.claude/agents/`, `.claude/skills/`, `CLAUDE.md`는 생성/수정되지 않고, 사용자에게 "검토 후 `scripts/approve <team>` 실행" 안내가 출력된다

#### R1.3: design 재실행 시 draft 재진입
- **Given**: `status: draft`인 design.md가 이미 존재
- **When**: `/harness-factory:design <team>` 재실행
- **Then**: 기존 draft를 읽어 이어서 수정하며, 승인된(`approved`) 스펙은 경고 없이 덮어쓰지 않는다

### R2: 설계 스펙 풀 계약 스키마 (D5)

#### R2.1: 필수 frontmatter 존재
- **Given**: design이 생성한 design.md
- **When**: 스키마를 검사할 때
- **Then**: frontmatter에 `team`, `status`(draft|approved), `checksum` 필드가 존재한다

#### R2.2: 필수 본문 섹션 존재
- **Given**: design이 생성한 design.md
- **When**: 본문을 검사할 때
- **Then**: `Purpose`, `Non-goals`, `Agents`, `Skills`, `Execution Mode`, `Invariants/Gates`, `Escalation Rules`, `File Layout` 8개 섹션이 모두 존재한다

#### R2.3: Agents 섹션 항목 완전성
- **Given**: design.md의 Agents 섹션
- **When**: 각 에이전트 항목을 검사할 때
- **Then**: 각 항목은 이름·역할·책임·허용툴(allowed-tools)·모델을 포함한다

#### R2.4: Skills 섹션 항목 완전성 + 소속 무결성
- **Given**: design.md의 Skills 섹션
- **When**: 각 스킬 항목을 검사할 때
- **Then**: 각 항목은 이름·목적·소속 에이전트를 포함하고, 소속 에이전트가 Agents 섹션에 존재한다

### R3: approve 헬퍼 — 체크섬 동결 (producer 측, D3)

#### R3.1: approve가 status를 approved로 설정
- **Given**: 사람이 수정을 마친 `status: draft` design.md
- **When**: `scripts/approve <team>` 실행
- **Then**: frontmatter `status`가 `approved`로 변경된다

#### R3.2: approve가 정규화 본문의 sha256을 checksum에 동결
- **Given**: 승인 대상 design.md
- **When**: `scripts/approve <team>` 실행
- **Then**: 본문에서 `checksum`·`status` 메타 필드를 제외하고 LF·말미공백을 정규화한 뒤 계산한 sha256이 `checksum` 필드에 기록된다

#### R3.3: approve가 변경 요약을 출력 (rubber-stamp 완화)
- **Given**: 직전 승인 이후 수정이 있는 design.md
- **When**: `scripts/approve <team>` 실행
- **Then**: 무엇이 동결되는지(에이전트/스킬 수, 변경된 섹션) 요약이 출력된다

### R4: build 하드 거부 게이트 (consumer 측, D2)

#### R4.1: 스펙 없음 → 거부
- **Given**: `specs/<team>/design.md`가 존재하지 않음
- **When**: `/harness-factory:build <team>` 실행
- **Then**: 생성 없이 거부하고 먼저 `/harness-factory:design <team>` 실행을 안내한다

#### R4.2: status != approved → 거부
- **Given**: design.md가 존재하나 `status: draft`
- **When**: `/harness-factory:build <team>` 실행
- **Then**: 생성 없이 거부하고 `scripts/approve <team>` 실행을 안내한다

#### R4.3: 체크섬 불일치(승인 후 변조) → 거부
- **Given**: `status: approved`인 design.md가 승인 후 한 줄 수정됨
- **When**: `/harness-factory:build <team>` 실행이 R3.2와 동일 규칙으로 체크섬을 재계산할 때
- **Then**: 저장된 `checksum`과 불일치하여 생성 없이 하드 거부하고 재승인(`scripts/approve <team>`)을 요구한다

#### R4.4: 모든 게이트 통과 → 생성 진행
- **Given**: design.md가 존재하고 `status: approved`이며 체크섬이 일치
- **When**: `/harness-factory:build <team>` 실행
- **Then**: 게이트를 통과해 산출물 생성 단계로 진행한다

### R5: build 생성 + 멱등 병합 (D5 읽기 + D6)

#### R5.1: build는 스펙만 읽고 인터뷰를 재실행하지 않는다
- **Given**: 승인·검증된 design.md
- **When**: build가 산출물을 생성할 때
- **Then**: design.md의 섹션(Agents/Skills/ExecMode/Invariants/Escalation/File Layout)만 입력으로 사용하고, 사용자에게 재질문(인터뷰)하지 않는다

#### R5.2: build가 산출물 3종을 스펙대로 생성
- **Given**: 게이트 통과한 신규 빌드(기존 `.claude/` 없음)
- **When**: build 실행 완료
- **Then**: File Layout이 선언한 경로에 `.claude/agents/*.md`, `.claude/skills/*/SKILL.md`, `CLAUDE.md` 포인터가 생성된다

#### R5.3: 재실행 시 Phase 0 audit 병합 (덮어쓰기 아님)
- **Given**: 한 번 build된 `.claude/` 산출물이 있고, 스펙을 고쳐 재승인한 상태
- **When**: `/harness-factory:build <team>` 재실행
- **Then**: 스펙에 새로 추가된 항목만 생성, 섹션이 바뀐 에이전트/스킬만 갱신, 손대지 않은 항목은 보존한다(전체 덮어쓰기 안 함)

#### R5.4: 체크섬 범위 = 스펙 전용
- **Given**: build가 게이트를 통과한 상태
- **When**: 체크섬을 검증할 때
- **Then**: 검증 대상은 design.md 본문뿐이며 `.claude/*` 산출물은 체크섬 검증 대상이 아니다

#### R5.5: 병합 분기 시 우선순위 (구조=spec wins, 본문=preserve-and-warn)
- **Given**: 재실행 build가 산출물이 승인된 스펙과 분기한 것을 발견
- **When**: Phase 0 audit가 병합을 수행할 때
- **Then**: 존재/구조(어떤 에이전트·스킬·툴·레이아웃)는 스펙 기준으로 정정하고, 에이전트/스킬 .md 본문의 사람 수정은 보존하되 분기를 경고로 surface한다

### R6: 하위호환 + harness-ops 래퍼 (D4)

#### R6.1: `--skip-design` 원샷 탈출구
- **Given**: 사용자가 `/harness-factory:generate-team --skip-design` 실행
- **When**: 커맨드가 플래그를 인식할 때
- **Then**: 기존 Phase 0~6 원샷 흐름이 게이트 없이 그대로 실행된다

#### R6.2: 플래그 없는 원샷 호출 → 게이트 경로 안내
- **Given**: 사용자가 `/harness-factory:generate-team`을 플래그 없이 실행
- **When**: 커맨드가 진입할 때
- **Then**: 기본 게이트 경로(`design`→`approve`→`build`)를 안내하고, 원샷을 원하면 `--skip-design`을 쓰도록 알린다

#### R6.3: ops 래퍼가 design으로 위임
- **Given**: harness-factory가 설치된 환경에서 `/harness-ops:generate-team` 계열 design 진입
- **When**: ops 래퍼 커맨드 실행
- **Then**: harness-factory의 design 경로(SKILL.md)를 찾아 위임하며, ops 스킬 로직은 변경되지 않는다

#### R6.4: ops 래퍼가 build로 위임
- **Given**: harness-factory가 설치된 환경에서 build 진입
- **When**: ops 래퍼 커맨드 실행
- **Then**: harness-factory의 build 경로로 위임하고, harness-factory 미설치 시 설치 안내 에러를 출력한다

## Tasks

### T1: 설계 스펙 스키마 + design.md 템플릿 [infra]
- **Fulfills**: R2 (R2.1~R2.4)
- **Depends on**: (none)
- **Action**: `skills/generate-team/references/design-schema.md`에 풀 계약 스키마(frontmatter 3필드 + 본문 8섹션, Agents/Skills 항목 필드, 소속 무결성 규칙) 정의 + design.md 템플릿 작성. design과 build가 공유하는 단일 계약 소스.

### T2: 공유 체크섬 정규화 스크립트 [infra]
- **Fulfills**: (R3.2·R4.3 지원 인프라 — 정규화 불변식)
- **Depends on**: (none) — T1과 병렬
- **Action**: `skills/generate-team/scripts/checksum.sh` 작성 — `checksum`·`status` 메타 제외, LF·말미공백 정규화 후 sha256 출력. approve(동결)와 build(검증)가 동일 호출 → 오탐 0. 정규화 규칙을 references에 1쪽 문서화.

### T3: design 커맨드 — 인터뷰→스펙 산출 후 정지 [vertical]
- **Fulfills**: R1 (R1.1~R1.3), R0
- **Depends on**: T1
- **Action**: `commands/design.md` + design 전용 스킬(예: `skills/team-design/SKILL.md`, Phase 0~2 로직). design.md를 `status: draft`로 쓰고 산출물 미생성 정지 + approve 안내. draft 재진입 처리.
- **Note**: T4·T5와 병렬 (파일 겹침 없음)

### T4: scripts/approve 헬퍼 — 체크섬 동결 (producer) [vertical]
- **Fulfills**: R3 (R3.1~R3.3)
- **Depends on**: T1, T2
- **Action**: `scripts/approve` 작성 — status를 approved로 설정 + T2 스크립트로 sha256 동결 + 변경 요약 출력.
- **Note**: T3·T5와 병렬 (scripts/approve 단독 파일)

### T5: build 커맨드 — 게이트 거부 + 생성 (consumer) [vertical]
- **Fulfills**: R4 (R4.1~R4.4), R5.1, R5.2, R5.4
- **Depends on**: T1, T2
- **Action**: `commands/build.md` + build 전용 스킬(예: `skills/team-build/SKILL.md`, Phase 3~6 로직). 게이트 3종(스펙없음/미승인/체크섬 불일치 via T2) 하드 거부 + 안내. 통과 시 스펙만 읽어(인터뷰 미재실행) `.claude/agents`·`.claude/skills`·`CLAUDE.md` 생성.
- **Note**: T3·T4와 병렬 (team-build 파일 단독)

### T6: build 멱등 병합 — Phase 0 audit + 분기 우선순위 [vertical]
- **Fulfills**: R5.3, R5.5
- **Depends on**: T5
- **Action**: build에 재실행 병합 로직 추가 — 신규 생성/변경분 갱신/미변경 보존, 구조=spec wins·본문=preserve-and-warn, 변경 검출 키(File Layout·섹션 대조).

### T7: 하위호환 — `--skip-design` 탈출구 + 게이트 안내 [vertical]
- **Fulfills**: R6.1, R6.2
- **Depends on**: T3, T5
- **Action**: 기존 `commands/generate-team.md` + `skills/generate-team/SKILL.md`에 `--skip-design` 플래그 분기(원샷 보존) + 플래그 없을 때 게이트 경로 안내. README 흐름 갱신.
- **Note**: T6·T8과 병렬 (generate-team 원본 파일 단독)

### T8: harness-ops 래퍼 커맨드 (design + build) [vertical]
- **Fulfills**: R6.3, R6.4
- **Depends on**: T3, T5
- **Action**: harness-ops 저장소에 design/build 위임 커맨드 추가 — harness-factory SKILL.md 경로 탐색, 미설치 시 설치 안내. ops 스킬 로직 미변경(커맨드 파일만).
- **Note**: T6·T7과 병렬 (harness-ops 저장소 — 파일 겹침 없음)

## External Dependencies

### Pre-work
- 도그푸드용 빈 테스트 프로젝트 디렉토리 1개 (실제 팀 design→approve→build 통과 검증 대상)
- 새 커맨드(`design`/`build`) 인식을 위한 플러그인 재링크/재설치

### Post-work
- README.md를 게이트 흐름(design → approve → build, `--skip-design`)으로 갱신 — T7에 일부 포함, 최종 동기화 필요
- harness-factory + harness-ops 동시 설치 환경에서 ops 래퍼 위임 통합 확인
