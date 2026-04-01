# Skill Responsibility

`colo-fe-flow`의 각 skill이 어디서 시작해서 어디서 끝나는지, 무엇을 읽고 무엇을 쓰는지, 어떤 artifact와 state를 책임지는지 정리한 문서입니다.

이 문서는 skill 경계가 섞이지 않도록 하기 위한 기준 문서입니다.

## 목적

이 문서는 아래를 명확히 하기 위해 존재합니다.

- 각 skill의 책임 범위
- skill 간 handoff 지점
- 어떤 skill이 어떤 artifact를 만들거나 갱신하는지
- 어떤 skill이 어떤 state 필드를 읽고 쓰는지
- 어떤 skill이 자동 실행 대상이고 어떤 skill이 utility 성격인지

## 핵심 원칙

- `route-workflow`는 controller이고 worker가 아닙니다.
- 각 worker skill은 자기 단계의 artifact와 state mutation만 책임집니다.
- upstream skill의 책임을 downstream skill이 대신하지 않습니다.
- 승인 대상 artifact는 `clarify.md`, `plan.md`, `design.md`만입니다.
- `tasks.json`은 `design` 단계의 실행용 파생 artifact입니다.
- `start-jira-ticket`와 `intake`는 분리합니다.

## Skill 분류

### 1. Controller Skill

- `route-workflow`

### 2. Core Workflow Skill

- `start-jira-ticket`
- `intake`
- `clarify`
- `plan`
- `design`
- `implement`
- `check`
- `iterate`
- `sync-docs`
- `complete-ticket`

### 3. Utility Skill

- `show-ticket-status`
- `list-tickets`
- `switch-ticket`

## Responsibility Matrix

| Skill | 역할 | 주요 입력 | 주요 출력 | 생성/갱신 Artifact | 주요 state 갱신 |
|---|---|---|---|---|---|
| `route-workflow` | 자연어 요청을 다음 skill로 라우팅 | `raw_request`, active ticket, ticket state | `route result JSON`, auto-execute target | 없음 | 없음 |
| `start-jira-ticket` | 작업할 Jira ticket 선택 및 active ticket 결정 | 사용자 요청, Jira ticket 목록 | 선택된 ticket context | 없음 | `index.json.active_ticket`, 필요시 기본 ticket index |
| `intake` | 상태 bootstrap과 기본 컨텍스트 정규화 | selected ticket, Jira/Confluence/Figma/codebase 기본 정보 | intake context | `intake.md` | ticket state 초기화, `artifacts.intake.*`, `phase=intake/branch-ready` |
| `clarify` | 모호성 해소와 질문/가정 정리 | `intake.md`, 관련 context | clarified scope | `clarify.md` | `artifacts.clarify.*`, `approvals.clarify.*`, `phase=clarify-*` |
| `plan` | 구현 계획 수립 | `clarify.md` | execution plan | `plan.md` | `artifacts.plan.*`, `approvals.plan.*`, `phase=plan-*` |
| `design` | 구현 구조 확정과 실행 task 준비 | `plan.md`, Figma/codebase context | final design + task breakdown | `design.md`, `tasks.json` | `artifacts.design.*`, `artifacts.tasks.*`, `approvals.design.*`, `phase=design-*` |
| `implement` | `tasks.json` 기준 구현 수행 | `tasks.json`, codebase | code changes | 없음 | `implementation.*`, 필요시 task progress |
| `check` | 구현 검증 및 gap 리포트 | code, `plan.md`, `design.md`, `tasks.json` | latest verification result | `check.md` | `artifacts.check.*`, `verification.*`, `phase=checking` |
| `iterate` | 실패한 check 기준 보정 작업 수행 | `check.md`, open gaps, existing tasks | fix tasks / follow-up implementation | 필요시 `tasks.json` 재생성 또는 갱신 | `iteration.*`, `implementation.*`, 필요시 `artifacts.tasks.*`, `phase=iterating` |
| `sync-docs` | wrapup 작성과 로컬 docs 동기화 | passed check, changed docs | final doc sync result | `wrapup.md` | `artifacts.wrapup.*`, `doc_sync.*`, `phase=syncing-docs` |
| `complete-ticket` | 완료 조건 최종 확인 및 terminal handoff | verification passed, docs synced | done result | 없음 | `status=done`, `phase=done` |
| `show-ticket-status` | 현재 ticket 상태 조회 | ticket key or active ticket | status summary | 없음 | 없음 |
| `list-tickets` | 로컬 open ticket 목록 조회 | `index.json` | ticket list | 없음 | 없음 |
| `switch-ticket` | active ticket 변경 | current active, target ticket | switched ticket context | 없음 | `index.json.active_ticket`, `index.json.last_ticket` |

## Skill별 상세 책임

### `route-workflow`

역할:

- 자연어 요청의 public entry
- `intent normalizer -> decision engine` 구조로 동작
- 다음에 실행해야 할 skill 결정
- 선택된 skill 자동 실행

읽는 것:

- `.state/index.json`
- `.state/tickets/<JIRA-KEY>.json`
- critical revalidation이 필요한 artifact 존재 여부

쓰는 것:

- 없음
- 선택적으로 route log를 남길 수는 있어도 business state는 직접 갱신하지 않음

하지 않는 것:

- artifact 생성
- 외부 데이터 수집
- 코드 수정
- approval 변경

### `start-jira-ticket`

역할:

- 작업할 Jira ticket 선택
- active ticket 설정
- 필요시 Jira status transition 시작

읽는 것:

- Jira assignee ticket 목록
- `.state/index.json`

쓰는 것:

- `.state/index.json`
- active ticket 관련 최소 인덱스 정보

하지 않는 것:

- `intake.md` 생성
- ticket state full bootstrap
- worktree 전체 상태 초기화

### `intake`

역할:

- 선택된 ticket을 실제 워크플로우에 올리는 bootstrap 단계
- 기본 context 수집과 정규화
- worktree/branch 준비 상태 반영
- `intake.md` 생성

읽는 것:

- selected ticket
- Jira/Confluence/Figma 링크
- codebase 1차 탐색 결과

쓰는 것:

- `.state/tickets/<JIRA-KEY>.json` 초기화
- `artifacts.intake.*`
- `workspace.*`
- `sources.*`

생성 artifact:

- `intake.md`

종료 조건:

- ticket state 존재
- `intake.md` 존재
- 기본 workspace 정보 존재

### `clarify`

역할:

- 요구사항의 빈칸과 모호성 제거
- 질문, 가정, 리스크 정리
- 구현 전 해석 차이를 줄이는 문서 작성

생성 artifact:

- `clarify.md`

state 책임:

- `artifacts.clarify.*`
- `approvals.clarify.*`
- `phase=clarify-draft` 또는 `clarify-approved`

중요 규칙:

- 승인 후 수정되면 `approvals.clarify.approved=false`

### `plan`

역할:

- 구현 계획 수립
- must-have 요구사항과 검증 기준 정리

생성 artifact:

- `plan.md`

state 책임:

- `artifacts.plan.*`
- `approvals.plan.*`
- `phase=plan-draft` 또는 `plan-approved`

중요 규칙:

- 승인 후 수정되면 `approvals.plan.approved=false`

### `design`

역할:

- 구현 구조 확정
- 파일/컴포넌트/상태 흐름 설계
- 실행 가능한 task로 분해

생성 artifact:

- `design.md`
- `tasks.json`

state 책임:

- `artifacts.design.*`
- `artifacts.tasks.*`
- `approvals.design.*`
- `phase=design-draft` 또는 `design-approved`

중요 규칙:

- `design`의 종료 조건은 `design.md` 승인 + `tasks.json` 준비 완료
- 승인 후 `design.md` 변경 시 `approvals.design.approved=false`
- `plan.md` 또는 `design.md` 변경 시 `tasks.json` 재생성 가능

### `implement`

역할:

- `tasks.json` 기준 구현
- TDD 순서 준수
- task 단위 진행 상태 반영

읽는 것:

- `tasks.json`
- codebase
- 관련 `plan.md`, `design.md`

쓰는 것:

- code
- `implementation.*`
- 필요시 task 진행 상태

생성 artifact:

- 없음

중요 규칙:

- `tasks.json` 없이는 진입 불가
- 구현 중 설계 변경이 필요하면 임의 수정하지 말고 upstream으로 되돌릴 수 있어야 함

### `check`

역할:

- 구현 결과를 `plan.md`, `design.md`, `tasks.json` 기준으로 검증
- 테스트와 E2E 결과 정리
- gap과 failure reason 기록

생성 artifact:

- `check.md`

state 책임:

- `artifacts.check.*`
- `verification.last_check_status`
- `verification.last_check_at`
- `verification.open_gaps`
- `verification.plan_compliance_score`
- `verification.classes.*`
- `phase=checking`

중요 규칙:

- `check.md`는 latest report
- 이력은 `.log/check-*.json`이 따로 보관

### `iterate`

역할:

- 실패한 check를 바탕으로 보정 작업 수행
- 필요시 기존 task 실패 처리 또는 fix task 생성
- 구현 재진입 준비

읽는 것:

- `check.md`
- `verification.*`
- 기존 `tasks.json`

쓰는 것:

- `iteration.*`
- 필요시 `tasks.json`
- `implementation.*`

생성 artifact:

- 기본적으로 별도 md artifact는 없음
- 필요 시 `tasks.json` 수정 또는 재생성

중요 규칙:

- `iterate`는 단순 재실행이 아니라 gap-driven repair 단계
- 설계 수준 수정이 필요하면 `design`으로 되돌릴 수 있어야 함

### `sync-docs`

역할:

- `wrapup.md` 작성
- 영향받은 로컬 `docs/` 최신화
- `doc_sync.*` 갱신

생성 artifact:

- `wrapup.md`

state 책임:

- `artifacts.wrapup.*`
- `doc_sync.required`
- `doc_sync.completed`
- `doc_sync.last_synced_at`
- `doc_sync.affected_docs`
- `phase=syncing-docs`

중요 규칙:

- `sync-docs`는 `wrapup.md`만 쓰는 단계가 아님
- 영향받은 일반 `docs/`까지 함께 최신화해야 함

### `complete-ticket`

역할:

- 완료 조건 최종 확인
- terminal handoff
- ticket을 `done`으로 표시

읽는 것:

- `verification.*`
- `doc_sync.*`
- `artifacts.wrapup.*`

쓰는 것:

- `status=done`
- `phase=done`

중요 규칙:

- 매우 얇은 wrapper skill이어도 괜찮음
- 하지만 라우터 계약에는 명시적 terminal target으로 남겨둠

### `show-ticket-status`

역할:

- 현재 ticket의 핵심 상태를 사람이 빠르게 볼 수 있게 요약

읽는 것:

- `index.json`
- `tickets/<JIRA-KEY>.json`

쓰는 것:

- 없음

### `list-tickets`

역할:

- 로컬에서 관리 중인 ticket 목록과 active ticket 표시

읽는 것:

- `index.json`

쓰는 것:

- 없음

### `switch-ticket`

역할:

- active ticket 전환
- 전환 후 새로운 ticket context를 기본값으로 사용

읽는 것:

- `index.json`
- 대상 ticket 존재 여부

쓰는 것:

- `index.json.active_ticket`
- `index.json.last_ticket`

## 가장 중요한 경계

### `start-jira-ticket` vs `intake`

- `start-jira-ticket`
  어떤 ticket으로 일할지 정함
- `intake`
  그 ticket을 실제 워크플로우에 올림

### `design` vs `implement`

- `design`
  `design.md` 승인과 `tasks.json` 준비까지
- `implement`
  `tasks.json`을 실제 코드 작업으로 실행

### `check` vs `iterate`

- `check`
  검증과 gap 리포트
- `iterate`
  gap 기반 보정 작업

### `sync-docs` vs `complete-ticket`

- `sync-docs`
  wrapup + 로컬 docs 최신화
- `complete-ticket`
  최종 완료 판정과 terminal state 변경

## 함께 읽을 문서

- `./local-runtime-schema.md`
- `./route-workflow-contract.md`
- `./artifact-lifecycle.md`
- `./workflow.md`
