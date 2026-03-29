# 기능 레지스트리 (Feature Registry)

본 문서는 Harness Engineering 프로젝트에서 진행 중이거나 완료된 모든 기능의 중앙 집중식 관리 목록입니다. 각 기능의 상태, 담당자, 의존성, 영향 범위를 한눈에 파악할 수 있도록 구성되어 있습니다.

**관리 담당**: `librarian` 에이전트

---

## 상태 정의

| 상태 | 설명 |
|:-----|:-----|
| `Planned` | 요구사항 분석 전 상태 |
| `Planning` | `/plan` 단계 진행 중 |
| `Designing` | `/design` 단계 진행 중 |
| `Implementing` | `/implement` 단계 진행 중 |
| `Checking` | `/check` 단계 진행 중 (자동 반복 포함) |
| `Completed` | 모든 PDCA 단계 완료 |
| `Blocked` | 의존성 미충족 또는 문제로 인한 일시 중단 |
| `On Hold` | 우선순위 조정으로 인한 일시 중단 |

---

## 기능 목록

### 예제 항목 (삭제 권장)

| `feature-slug` | 제목 | 상태 | 담당 | 의존성 | 영향 범위 | 생성일 | 예상 완료일 |
|:---|:---|:---|:---|:---|:---|:---|:---|
| `example-feature` | 예제 기능 (삭제 권장) | `Planned` | - | - | - | 2024-01-01 | - |

### P0 Foundation (Completed)

| `feature-slug` | 제목 | 상태 | 담당 | 의존성 | 영향 범위 | 생성일 | 완료일 |
|:---|:---|:---|:---|:---|:---|:---|:---|
| `p0-1-test-runner` | 다중 프레임워크 테스트 실행 | `Completed` | engineer | - | hooks/lib/test-runner.sh, hooks/lib/verification-classes.sh | 2026-03-26 | 2026-03-26 |
| `p0-2-subagent` | 서브에이전트 스포닝 | `Completed` | engineer | - | hooks/lib/subagent-spawner.sh | 2026-03-26 | 2026-03-26 |
| `p0-3-state-machine` | 상태 머신 엔진 | `Completed` | engineer | - | hooks/lib/state-machine.sh | 2026-03-26 | 2026-03-26 |

### P1 Enhancement (Completed)

| `feature-slug` | 제목 | 상태 | 담당 | 의존성 | 영향 범위 | 생성일 | 완료일 |
|:---|:---|:---|:---|:---|:---|:---|:---|
| `p1-1-review` | 2단계 리뷰 시스템 | `Completed` | guardian | p0-2-subagent, p0-3-state-machine | hooks/lib/review-engine.sh | 2026-03-27 | 2026-03-27 |
| `p1-2-skill-eval` | 스킬 평가 프레임워크 | `Completed` | librarian | - | hooks/lib/skill-evaluation.sh | 2026-03-27 | 2026-03-27 |
| `p1-3-crash-recovery` | 크래시 복구 & 포렌식 | `Completed` | debugger | p0-3-state-machine | hooks/lib/crash-recovery.sh | 2026-03-27 | 2026-03-27 |
| `p1-4-browser-test` | 브라우저 테스트 통합 | `Completed` | engineer | - | hooks/lib/browser-testing.sh | 2026-03-27 | 2026-03-27 |

### P2 Advanced (Completed)

| `feature-slug` | 제목 | 상태 | 담당 | 의존성 | 영향 범위 | 생성일 | 완료일 |
|:---|:---|:---|:---|:---|:---|:---|:---|
| `p2-1-hash-edit` | 해시 앵커 에디트 | `Completed` | engineer | - | hooks/lib/hash-anchored-edit.sh | 2026-03-29 | 2026-03-29 |
| `p2-2-wave-exec` | 웨이브 실행 (병렬 처리) | `Completed` | engineer | p0-2-subagent | hooks/lib/wave-executor.sh | 2026-03-29 | 2026-03-29 |

### Core Features (Completed)

| `feature-slug` | 제목 | 상태 | 담당 | 의존성 | 영향 범위 | 생성일 | 완료일 |
|:---|:---|:---|:---|:---|:---|:---|:---|
| `automation-levels` | L0-L4 자동화 레벨 시스템 | `Completed` | librarian | - | hooks/, .harness/ | 2026-03-24 | 2026-03-25 |
| `fresh-context` | Context Rot 방지 시스템 | `Completed` | librarian | automation-levels | hooks/, .harness/ | 2026-03-25 | 2026-03-25 |
| `cso` | Claude Search Optimization | `Completed` | librarian | - | skills/*/SKILL.md | 2026-03-25 | 2026-03-25 |
| `posix-compat` | POSIX 호환성 (bash 3.2) | `Completed` | engineer | - | hooks/lib/*.sh, hooks/__tests__/*.sh | 2026-03-29 | 2026-03-29 |

---

## 사용 가이드

### 1. 새 기능 추가
`/plan` 스킬이 실행될 때, `librarian` 에이전트는 다음 정보를 수집하여 본 레지스트리에 행을 추가합니다:
- **`feature-slug`**: `/plan` 스킬이 확정한 kebab-case 슬러그
- **제목**: 기능의 간략한 설명 (1줄)
- **상태**: 초기값은 `Planning`
- **담당**: 현재 작업을 주도하는 에이전트 또는 팀
- **의존성**: `plan.md`의 `Dependencies` 섹션에서 추출
- **영향 범위**: `design.md`의 `Impact Analysis` 섹션에서 추출
- **생성일**: 기능 생성 날짜
- **예상 완료일**: 계획된 완료 날짜 (선택 사항)

### 2. 상태 업데이트
각 PDCA 단계 진입 시 상태를 업데이트합니다:
- `/plan` 완료 → `Planning` → `Designing`
- `/design` 완료 → `Designing` → `Implementing`
- `/implement` 완료 → `Implementing` → `Checking`
- `/check` 완료 → `Checking` → `Completed`

### 3. 의존성 확인
새 기능을 `Implementing` 단계로 진입하기 전, `on-agent-start.sh` 훅에서 다음을 확인합니다:
- 이 기능의 `의존성` 열에 나열된 모든 기능이 `Completed` 상태인지 확인
- 미완료 기능이 있으면 에이전트에게 경고 메시지 출력
- 필요 시 작업 진행을 일시적으로 차단

### 4. 충돌 감지
`implement` 단계에서 파일 수정 시, `pre-tool.sh` 훅에서 다음을 확인합니다:
- 현재 수정하려는 파일이 다른 `Implementing` 또는 `Checking` 상태의 기능의 `영향 범위`에 포함되어 있는지 확인
- 충돌 가능성이 감지되면 에이전트에게 경고 메시지 출력
- 필요 시 수동 개입 요청

---

## 주의사항

- 본 레지스트리는 **Single Source of Truth (SSOT)**이므로, 각 기능의 상태 변화는 반드시 이 문서에 반영되어야 합니다.
- `librarian` 에이전트는 매 PDCA 단계 완료 후 본 문서를 업데이트해야 합니다.
- 의존성이나 영향 범위 변경이 발생하면 즉시 본 문서에 반영합니다.
