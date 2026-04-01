# Implementation Phases

`colo-fe-flow`를 실제로 구현할 때 어떤 순서로 나누어 진행할지 정리한 문서입니다.

이 문서는 사람이 읽는 기준 문서입니다. 목적은 “무엇을 만들 것인가”가 아니라 “무엇부터 어떤 의존성 순서로 만들 것인가”를 고정하는 것입니다.

## 목적

이 문서는 아래를 명확히 하기 위해 존재합니다.

- 구현 순서를 어떤 phase로 자를지
- 각 phase의 목표와 완료 조건이 무엇인지
- 어떤 phase가 다음 phase의 전제조건인지
- 어떤 부분을 나중으로 미뤄도 되는지

## 핵심 원칙

- 구현은 `contract-first`로 진행합니다.
- state, router, artifact, skill, agent 계약이 먼저 고정되어야 합니다.
- controller와 runtime contract를 worker skill보다 먼저 세웁니다.
- bootstrap flow를 planning flow보다 먼저 연결합니다.
- planning flow를 execution loop보다 먼저 연결합니다.
- hook은 횡단 관심사이므로 마지막에 붙입니다.

## 선행 기준 문서

이 구현 순서는 아래 문서들을 기준으로 합니다.

- `./local-runtime-schema.md`
- `./route-workflow-contract.md`
- `./artifact-lifecycle.md`
- `./skill-responsibility.md`
- `./agent-responsibility.md`

## 전체 Phase 개요

| Phase | 이름 | 핵심 결과 |
|---|---|---|
| 0 | Canonical Contract Freeze | 기준 문서와 naming 확정 |
| 1 | Core Runtime Library | 공통 runtime 함수 확보 |
| 2 | Route Workflow Skeleton | controller와 decision engine 골격 |
| 3 | Ticket Bootstrap | `start-jira-ticket` + `intake` end-to-end |
| 4 | Planning Chain | `clarify` -> `plan` -> `design` + `tasks.json` |
| 5 | Execution Loop | `implement` -> `check` -> `iterate` -> `sync-docs` -> `complete-ticket` |
| 6 | Utility Skills | status/list/switch 유틸리티 |
| 7 | Agent Hardening | 5개 agent 연결과 역할 강화 |
| 8 | Hooks | session/tool/agent hook 자동화 |

## Phase 0: Canonical Contract Freeze

### 목표

사람이 읽는 기준 문서와 용어를 더 이상 흔들리지 않게 고정합니다.

### 포함 범위

- skill naming 확정
- state schema 확정
- route-workflow 계약 확정
- artifact lifecycle 확정
- skill 책임 확정
- agent 책임 확정

### 완료 조건

- canonical docs 세트가 존재함
- naming conflict가 없음
- `tasks.json`의 역할이 명확함
- `intake`가 `start-jira-ticket`와 분리되어 있음

### 비고

현재 이 단계는 사실상 거의 완료된 상태입니다.

## Phase 1: Core Runtime Library

### 목표

모든 skill과 hook이 공통으로 사용할 runtime helper를 먼저 구현합니다.

### 포함 범위

- `hooks/lib/state.sh`
- `hooks/lib/cache.sh`
- `hooks/lib/log.sh`
- `hooks/lib/routing.sh`
- `hooks/lib/approval.sh`
- `hooks/lib/worktree.sh`
- `hooks/lib/verification.sh`
- 필요 시 `hooks/lib/common.sh`

### 이 단계에서 해결할 것

- `.state/index.json` 읽기/쓰기
- `.state/tickets/<JIRA-KEY>.json` 읽기/쓰기
- artifact 존재/최신성 확인
- approval 값 읽기/쓰기
- verification 필드 갱신 helper
- reason_code/decision 계산에 필요한 공통 유틸

### 완료 조건

- shell helper만으로 state 파일을 안정적으로 읽고 쓸 수 있음
- artifact revalidation 함수가 있음
- worktree path와 active ticket을 일관되게 찾을 수 있음

## Phase 2: Route Workflow Skeleton

### 목표

`route-workflow`를 public entry controller로 먼저 세웁니다.

### 포함 범위

- intent normalizer
- decision engine
- `route result JSON` 생성
- `decision=execute|redirect|block`
- `requires_user_input`
- `reason_code` enum 처리
- critical revalidation 골격

### 이 단계에서 아직 안 해도 되는 것

- 모든 worker skill의 완전 구현
- 모든 utility skill의 완전 구현
- hook 자동화

### 완료 조건

- 자연어 요청이 `resolved_action`으로 정규화됨
- state를 읽고 `required_next_skill`을 계산할 수 있음
- 다음 skill 이름을 자동으로 결정할 수 있음
- 최소한 stub skill 대상으로라도 라우팅 가능함

## Phase 3: Ticket Bootstrap

### 목표

ticket selection과 workflow bootstrap을 end-to-end로 연결합니다.

### 포함 범위

- `start-jira-ticket`
- `intake`
- active ticket 설정
- ticket state 생성
- worktree/branch 준비
- `intake.md` 생성

### 이 단계에서 연결할 것

- Atlassian MCP 기반 ticket 선택
- `index.json.active_ticket` 갱신
- ticket state 초기화
- `sources.*`, `workspace.*`, `artifacts.intake.*` 채우기

### 완료 조건

- Jira ticket 하나를 선택해 active ticket으로 만들 수 있음
- `.state/tickets/<JIRA-KEY>.json`이 생성됨
- `docs/specs/<JIRA-KEY>/intake.md`가 생성됨
- `route-workflow`가 다음 단계로 `clarify`를 계산할 수 있음

## Phase 4: Planning Chain

### 목표

승인 게이트 기반 planning flow를 완성합니다.

### 포함 범위

- `clarify`
- `plan`
- `design`
- approval gate 처리
- `tasks.json` 생성

### 이 단계에서 연결할 것

- `planning-agent`
- 필요 시 `context-agent`
- `artifacts.clarify/plan/design/tasks`
- `approvals.clarify/plan/design`
- `phase=clarify-*`, `plan-*`, `design-*`

### 완료 조건

- `intake` 이후 `clarify -> plan -> design`이 순서대로 진행됨
- 승인 전에는 다음 단계로 넘어가지 않음
- `design` 완료 후 `tasks.json`이 반드시 존재함
- `route-workflow`가 `implement` 가능 여부를 정확히 판정함

## Phase 5: Execution Loop

### 목표

실제 개발 루프를 완성합니다.

### 포함 범위

- `implement`
- `check`
- `iterate`
- `sync-docs`
- `complete-ticket`

### 이 단계에서 연결할 것

- `implementation-agent`
- `check-agent`
- `planning-agent`의 wrapup/doc 역할
- `implementation.*`
- `verification.*`
- `doc_sync.*`
- `status=done`, `phase=done`

### 세부 흐름

1. `tasks.json` 기반 구현
2. `check.md` 생성
3. `open_gaps > 0` 또는 failed면 `iterate`
4. 통과하면 `sync-docs`
5. `wrapup.md`와 docs 최신화 후 `complete-ticket`

### 완료 조건

- `tasks.json` 기반 구현이 가능함
- `check.md`와 verification state가 갱신됨
- gap loop가 동작함
- `wrapup.md`와 docs sync가 가능함
- `done` 전이가 가능함

## Phase 6: Utility Skills

### 목표

운영성과 디버깅에 필요한 utility skill을 붙입니다.

### 포함 범위

- `show-ticket-status`
- `list-tickets`
- `switch-ticket`

### 이유

핵심 플로우보다 우선순위는 낮지만, 멀티 ticket 환경에서는 빠르게 상태를 확인하고 전환할 수 있어야 합니다.

### 완료 조건

- 현재 active ticket과 phase를 빠르게 확인 가능
- open ticket 목록을 조회 가능
- active ticket을 안전하게 전환 가능

## Phase 7: Agent Hardening

### 목표

agent 역할을 문서 기준대로 강화하고 연결합니다.

### 포함 범위

- `intake-agent`
- `context-agent`
- `planning-agent`
- `implementation-agent`
- `check-agent`

### 이 단계에서 집중할 것

- skill과 agent의 역할 분리 유지
- state mutation은 skill이 담당
- agent는 결과 생성에 집중
- 구현 주체와 검증 주체 분리 유지

### 완료 조건

- 각 phase에서 적절한 agent가 호출됨
- 권한 모델이 깨지지 않음
- agent가 과도한 책임을 떠안지 않음

## Phase 8: Hooks

### 목표

횡단 관심사를 자동화합니다.

### 포함 범위

- `session-start.sh`
- `pre-tool.sh`
- `post-tool.sh`
- `on-agent-start.sh`
- `on-agent-stop.sh`

### 이 단계에서 자동화할 것

- dependency check
- state sanity check
- stale artifact detection
- route logging
- agent lifecycle logging
- 공통 guardrail enforcement

### 왜 마지막인가

hook은 거의 모든 단계에 걸치는 횡단 기능입니다. core contract와 worker flow가 안정되기 전에 붙이면 오히려 개발 속도를 떨어뜨립니다.

### 완료 조건

- 필수 전제 검증이 자동으로 동작함
- 잘못된 단계 점프나 상태 불일치 탐지가 빨라짐
- 수동 디버깅 비용이 줄어듦

## 추천 구현 순서 요약

```text
Phase 0: contract freeze
Phase 1: runtime library
Phase 2: route-workflow skeleton
Phase 3: start-jira-ticket + intake
Phase 4: clarify + plan + design + tasks.json
Phase 5: implement + check + iterate + sync-docs + complete-ticket
Phase 6: utility skills
Phase 7: agents hardening
Phase 8: hooks
```

## 왜 이 순서가 좋은가

- state와 router가 먼저 있어야 이후 skill이 공통 계약 위에서 움직입니다.
- bootstrap flow가 먼저 있어야 실제 ticket 단위 개발을 시작할 수 있습니다.
- `design -> tasks.json`이 먼저 완성돼야 execution loop가 의미를 가집니다.
- hook은 마지막에 붙여야 churn이 적습니다.

## 처음 읽는 사람이 기억할 것

이 문서를 다 읽지 않아도 아래만 기억하면 충분합니다.

- 먼저 contract를 고정한다.
- 그 다음 runtime library와 router를 만든다.
- 그 다음 bootstrap과 planning chain을 붙인다.
- execution loop를 만든 뒤 utility, agents, hooks를 붙인다.

## 함께 읽을 문서

- `./local-runtime-schema.md`
- `./route-workflow-contract.md`
- `./artifact-lifecycle.md`
- `./skill-responsibility.md`
- `./agent-responsibility.md`
- `./workflow.md`
