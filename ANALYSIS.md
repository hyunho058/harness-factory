# harness-factory — 분석 및 개선점

> 작성일: 2026-07-17 · 갱신: 2026-07-17 (백로그 검증 반영) · 대상 커밋: `9506d41` (main) · 플러그인 버전: 0.2.0
> 목적: 코드베이스 구조 분석과 개선 백로그를 한 문서로 정리한다.
>
> **검증 등급:** `CONFIRMED` = 코드/파일시스템 직접 확인 또는 재현 · `PLAUSIBLE` = 코드 근거 위 논리 추론 · `INFERRED` = 정황 추론(대상 환경 실측 필요).

---

## 1. 한 줄 요약

프로젝트 코드베이스를 분석해 그 도메인에 맞는 **멀티 에이전트 팀 아키텍처**(`.claude/agents/`,
`.claude/skills/`, `CLAUDE.md`)를 자동 생성하는 **Claude Code 플러그인**.
핵심은 "생성"이 아니라 **게이트 걸린 생성 워크플로** — 사람이 한 장짜리 설계 스펙을
먼저 승인해야만 파일이 만들어진다.

**핵심 명제:** 검토 비용을 **O(출력) → O(설계)** 로 낮춘다. 수백 줄 산출물을 사후
검토하는 대신, 작은 설계 스펙을 사전 검토·승인한다.

---

## 2. 아키텍처

### 2.1 게이트 3단계 흐름

```
/design <team>  →  scripts/approve <team>  →  /build <team>
   (인터뷰)          (체크섬 동결)              (스펙만 읽어 생성)
   status: draft       status: approved         .claude/* 물질화
```

원래 하나였던 6-Phase 원샷 흐름을 **결정(Phase 0–2)** 과 **물질화(Phase 3–6)** 사이의
seam에서 쪼갠 구조.

| Phase | 하는 일 | 소속 |
|-------|--------|------|
| 0 감사 / 1 도메인분석 / 2 아키텍처설계 | 순수 *결정* — 팀명·에이전트·스킬·실행모드 | **design** |
| 3 에이전트정의 / 4 스킬 / 5 오케스트레이터+CLAUDE.md / 6 검증 | *물질화* — 파일 생성 | **build** |

### 2.2 세 주역

| 구성요소 | 파일 | 역할 |
|----------|------|------|
| `team-design` | `skills/team-design/SKILL.md` | 생산자. 인터뷰만 하고 `specs/<team>/design.md`(draft)를 쓰고 멈춤. **`.claude/`는 절대 안 건드림(R1.2)**. |
| `team-build` | `skills/team-build/SKILL.md` | 소비자. **먼저 게이트(G1~G3)**, 통과 시에만 스펙만 읽어 생성. 인터뷰 재실행 없음. |
| `generate-team` | `skills/generate-team/SKILL.md` | 원본 6-Phase 로직 + `--skip-design` 원샷 탈출구. design/build가 참조 파일을 여기서 공유. |

### 2.3 게이트의 핵심 — 체크섬 anti-tamper

- **`scripts/approve`** (생산자): `status: approved` 설정 + 본문 sha256을 frontmatter에 **동결**.
- **`build` G3** (소비자): 같은 스크립트로 재계산해 비교. 불일치 = "승인 후 변조" → **하드 거부**.
- 양쪽 모두 **동일한 `scripts/checksum.sh`를 동일 규칙으로 호출** → *오탐(false mismatch) 0*이
  구조적으로 보장됨.
- 정규화: frontmatter의 `status:`/`checksum:` 라인 제외(자기참조 회피), LF·말미공백 정규화 후 sha256.

> "승인받고 몰래 바꿔서 빌드" 경로를 courtesy check가 아니라 **기계 불변식**으로 막은 것이 설계 핵심.

### 2.4 멱등 재실행 병합 (build Phase 0-M)

체크섬은 **스펙만** 검증하고 산출물 `.claude/*`은 검증하지 않는다(R5.4, 의도적).
사람이 생성된 에이전트 프롬프트를 직접 튜닝하도록 두기 위함. 재빌드 시:
- **구조(어떤 에이전트/스킬/툴/레이아웃) → spec wins** (정정)
- **본문(사람이 손댄 프롬프트 산문) → preserve-and-warn** (보존+경고)
- 니모닉: *"스펙은 뼈대, 사람은 살을 소유"*

---

## 3. 강점

1. **문서/설계 규율이 예외적으로 높음.** `specs/gated-team-generation/spec.md`가 D1~D6 결정마다
   *반려 대안과 그 이유*까지 steelman으로 기록. 스펙→구현 추적성(R↔T 매핑)이 완결적.
2. **Progressive disclosure 실천.** SKILL 본문은 짧게, 상세는 `references/`로 분리
   (각 100~330줄, 300줄 넘는 파일엔 ToC). 자기가 설파하는 원칙을 자기 코드에 적용.
3. **DRY.** design/build가 generate-team의 references를 상대경로로 재사용, 로직 중복 없음.
4. **셸 스크립트 품질이 실무 수준** — 이식성(BSD/GNU), 원자적 temp+mv, trap 정리, frontmatter 경계 파싱.

---

## 4. 개선 백로그 (영향도 순)

| 우선 | 항목 | 성격 | 노력 | 검증 |
|------|------|------|------|------|
| **P0** | ① 산출물에 출처-섹션 해시 → 결정론적 재빌드 | 정합성 | 중 | PLAUSIBLE |
| **P0** | ② approve에 동결 전 검증(validate.sh 공유) | 정합성 | 중 | **CONFIRMED** |
| **P1** | ③ 게이트 셸 테스트 + CI | 검증 | 소~중 | CONFIRMED |
| **P1** | ④ team primitive 가용성 확인 / sub 기본값 | 출력 품질 | 소 | INFERRED |
| **P2** | ⑤ README 구조 트리 갱신 | 위생 | 소 | CONFIRMED |
| **P2** | ⑥ specs/ gitignore 예외 / dangling 인용 | 위생 | 소 | CONFIRMED |
| **P2** | ⑦ 계약 3중복 → 섹션명 변경 시 approve 파손 | 위생 | 소 | CONFIRMED |
| **P3** | ⑧ CHANGELOG / 심링크 / 문구 불일치 | 위생 | 소 | CONFIRMED |

---

### Tier 1 — 핵심 가치를 위협하는 정합성 갭

#### ① 멱등 재빌드에 결정론적 앵커가 없다 (가장 중요 · 검증 등급: PLAUSIBLE)

`skills/team-build/references/merge.md:95-99`가 명시적으로 인정한다:
> "There is no stored prior-spec snapshot; the on-disk artifact *is* the record.
> '변경됐나?' = '온디스크 산출물 구조가 이 스펙 섹션이 생성할 것과 여전히 일치하나?'"

**문제(범위 정정):** merge의 비교 대상은 **구조 필드**(allowed-tools, model, owner-agent)와
**산문형 필드**(role, responsibility)로 나뉜다. 전자는 기계적 값이라 LLM 재렌더 없이도 결정론적
대조가 가능하다. 위험이 실재하는 곳은 **산문형 필드**다 — build는 LLM으로 산문을 생성하므로 같은
스펙 섹션도 재실행마다 다른 문장을 낸다. 그러니 "이 섹션이 생성할 것과 일치하나?"를 산문에 적용하면
정의상 거의 항상 "불일치"로 읽혀, **안 바뀐 에이전트가 UPDATE로 오분류**될 수 있다. R5.3("바뀐 것만
갱신")·R5.5의 preserve 약속이 산문형 필드에서 흔들린다. (초판은 이를 "전면적 오분류"로 서술했으나,
정확히는 *산문형 필드에서의 비결정론*이며 구조 필드는 대체로 안전하다.)

**아이러니:** 스펙 게이트에는 `checksum.sh`로 완벽한 결정론을 적용해놓고, 정작 재빌드 판정은
"눈대중 재렌더 비교"다.

**해결(자기네 관용구 그대로):** 생성된 각 산출물 frontmatter/주석에 **출처 섹션 해시**를 심는다.
```markdown
<!-- generated-from: agents/reviewer @ sha256:a1b2c3… -->
```
재빌드 시 저장된 섹션 해시 vs 현재 스펙 섹션 해시를 비교 → PRESERVE/UPDATE가 **결정론적**이 된다.
`checksum.sh`를 섹션 단위로 재사용하면 되고, 새 원칙 도입이 아니라 기존 규율의 확장이다.

**숨은 이점 — 두 질문의 분리:** merge는 사실 서로 다른 두 질문을 하나의 비교로 뭉쳐 놓았다.
- **Q1: 스펙 섹션이 지난 빌드 이후 바뀌었나?** → UPDATE/PRESERVE 판정
- **Q2: 산출물이 스펙에서 drift했나?** → 구조 정정(spec wins) 판정

출처-섹션 해시는 **Q1을 결정론적으로 분리**하고, LLM 판단은 Q2에만 남긴다. 이 "질문 분리"가
해결책의 진짜 가치다 — 현재는 둘이 뒤엉켜 Q1까지 비결정론에 오염돼 있다.

#### ② approve가 검증 없이 동결한다 — 잘못된 스펙을 승인해버림 (검증 등급: CONFIRMED)

`scripts/approve`는 agent/skill **개수만 셀 뿐**(`approve:100-120`), 8개 섹션 존재·에이전트 5필드·
**owner-agent 참조 무결성(R2.4)** 을 전혀 확인하지 않는다. 검증은 전부 build의 Phase 0에서
*나중에* LLM이 한다.

**결과:** 사람이 dangling owner-agent나 섹션 누락이 있는 malformed 스펙을 **approve로 동결**할 수
있고, 오류는 빌드 시점에야 드러난다. "빠른 실패"의 반대.

**부수 버그 — 재현으로 확정(2026-07-17):** design.md에 frontmatter가 없으면 approve의 status-flip
awk(`approve:128-151`)가 `in_fm`을 못 켜서 **`status`·`checksum`을 아예 안 쓰고도 "Approved" 성공
메시지**를 낸다. 격리 디렉토리에서 재현한 실제 출력:

```text
$ approve demo          # specs/demo/design.md 에 frontmatter 없음
Approved: demo
  spec:     specs/demo/design.md
  status:   approved     ← 메시지는 approved라 주장하지만
  checksum: 5d17e24cdcbf (frozen)

$ head -1 specs/demo/design.md
## Purpose               ← 파일엔 frontmatter도 status:도 checksum:도 없음
```

다이제스트를 계산해놓고 쓸 프론트매터가 없어 버려지는데도 exit 0 + "frozen" 메시지가 나간다.
build G2에서 거부되니 최종적으로 안전-실패이나, approve의 성공 보고가 거짓이라는 게 문제.
(대조군: 정상 frontmatter 스펙은 approve→변조→checksum 재계산에서 정확히 MISMATCH → 게이트가
올바르게 거부함을 같은 세션에서 확인.)

**해결:** `checksum.sh`처럼 공유 `validate.sh`를 만들어 **approve가 동결 전에**, build가 **G3 후에**
둘 다 호출. 승인 시점에 구조 오류(프론트매터 누락 포함)를 잡는다.

---

### Tier 2 — 스펙이 요구하는데 없는 검증 인프라

#### ③ 테스트/CI가 전혀 없다

`specs/gated-team-generation/spec.md:29`의 **완료 기준**이 "승인 없이/변조 후 build 하면 거부되는
것이 재현된다"인데, 지금 이 재현은 **전부 수동**이다.

`checksum.sh`·`approve`는 순수 셸이라 단위 테스트가 trivial. ROI가 매우 높다:
- `tests/gate_test.sh` — approve 후 status/checksum 동결, 변조 후 checksum 불일치, no-frontmatter
  엣지, LF/CRLF 정규화 오탐 0
- 게이트 시나리오 — missing/draft/tampered 3종 거부 재현
- `.github/workflows/` — 위를 CI로

체크섬 게이트가 이 프로젝트의 심장인데 회귀 방지 없이 방치돼 있다.

---

### Tier 3 — 생성되는 모든 하네스에 영향

#### ④ 기본 실행 모드가 가용성 불확실한 primitive에 의존 (검증 등급: INFERRED)

generate-team SKILL의 **기본값이 "agent team" 모드**이고, 이는 `TeamCreate`+`SendMessage`+`TaskCreate`
자기조율에 기반한다(`skills/generate-team/SKILL.md:86-90`, allowed-tools에 `TeamCreate`/`TeamDelete`).
그런데 이 세션의 tool 목록에는 `SendMessage`/`TaskCreate`는 있어도 **`TeamCreate`/`TeamDelete`가
보이지 않는다**.

> **검증 등급 주의(INFERRED):** ①~③이 코드/재현 근거인 것과 달리 이 항목은 *정황 추론*이다.
> "이 세션의 tool 목록에 없다"는 것은 **사용자 환경 전반의 부재 증거가 아니다** — tool 구성은
> 세션·버전·FleetView 활성화 여부에 따라 다를 수 있다. 확정하려면 대상 Claude Code 환경에서
> team primitive 가용성을 **실측**해야 한다. 이 선행 확인 없이 sub 기본값으로 바꾸지 말 것.

대상 Claude Code 버전에 `TeamCreate`가 없다면 **factory가 뽑는 모든 오케스트레이터가 존재하지
않는 패턴으로 기본 생성**된다 — 출력 품질 전체에 직결.

**권장:** (a) 타깃 버전에서 team primitive 가용성 **실측**(선행), (b) 부재가 확인되면 **sub-agent
모드를 안전 기본값**으로 하고 team은 옵트인, (c) 최소한 버전 요구사항을 문서화.

---

### Tier 4 — 문서/저장소 위생

#### ⑤ README "Repository structure" 트리 stale
`README.md:118-134`가 여전히 `generate-team`만 나열 — `design.md`/`build.md`/`team-design`/
`team-build`/`scripts/`/`assets/`가 빠짐.

#### ⑥ specs/ gitignore → 설계 근거 미추적 + reference의 dangling 인용
`.gitignore`의 `specs/`로 `spec.md`의 D1~D6 근거가 커밋에서 빠진다. 게다가
`checksum-normalization.md`·`approve` 주석이 `spec D3, R3.2`, `Constraints "체크섬 정규화"`를
인용하는데, **설치된 플러그인 사용자에겐 specs/가 없어 이 포인터가 전부 허공**이다.
`!specs/gated-team-generation/` 예외로 최소한 설계 원장은 shipping 권장.

#### ⑦ 계약이 3곳에 중복 → 섹션명 변경 시 approve가 조용히 깨짐
design↔build 계약이 `design-schema.md` + `design-template.md` + **approve의 awk 섹션명 매처**
(`## Agents`/`## Skills` 하드코딩, `approve:119-120`)에 흩어져 있다. `## Agents`를 리네임하면
approve의 카운터가 **경고 없이 0**을 낸다. schema.md 스스로 "필드 바뀌면 양쪽 다 바꿔라"라고
하지만 실제론 세 곳이다.

#### ⑧ 기타 소소
- `CHANGELOG.md` 없음 (0.2.0인데 변경 이력 추적 부재)
- `plugins/harness-factory -> ../` 심링크 커밋 → Windows 체크아웃 취약
- README("플래그 없으면 아무것도 안 만들고 design 안내") vs generate-team Phase -1(그 자리서
  AskUserQuestion으로 "One-shot now" 제공) — 뉘앙스 불일치
- **이 문서(`ANALYSIS.md`)의 자기모순:** "대상 커밋 9506d41"로 코드 버전을 고정했지만 ANALYSIS.md
  자체는 커밋되지 않아, 문서↔코드 동기화가 깨져도 감지할 방법이 없다 — ⑥(설계 원장 미추적)과
  같은 계열의 문제를 문서 스스로 안고 있다. 커밋하거나 상단에 대상 커밋 해시를 계속 명시할 것.

---

## 5. 핵심 통찰

**이 프로젝트는 "스펙 게이트"에는 결정론(checksum)을 완벽히 적용했지만, "재빌드 멱등성"과
"스펙 검증"에는 같은 규율을 아직 안 썼다.** ①②가 그 비대칭을 메우는, 가장 가치 있는 개선이다.

**착수 순서 제안:** **② approve 검증을 먼저** 권한다 — P0이면서 노력이 적고, **재현으로 결함이
확정(2026-07-17)**되어 근거가 가장 단단하다. 이어서 ③ 게이트 셸 테스트(즉효·저위험)로 회귀를 못
박고, ①(재빌드 결정론)은 설계 논의가 필요하므로 그 다음. ④는 착수 전 **대상 환경 실측**이 선행.
