# Route Workflow Contract

`route-workflow`의 역할, 내부 구조, 입력/출력 계약, 상태 전이 판정 규칙을 정리한 문서입니다.

이 문서는 사람이 읽고 이해하는 기준 문서입니다. 구현체는 이 문서를 따라야 하며, `route-workflow`가 직접 작업을 수행하는 worker처럼 커지지 않도록 범위를 고정하는 목적도 함께 가집니다.

## 한 줄 정의

`route-workflow`는 사용자 자연어 요청을 받아 현재 로컬 상태와 산출물을 읽고, 다음에 실행해야 할 skill을 자동으로 선택하는 public entry controller입니다.

## 무엇을 하고 무엇을 하지 않나

### 하는 일

- 사용자 자연어 요청을 public entry로 받음
- 현재 ticket context를 결정
- 요청 의도를 내부 action enum으로 정규화
- `.state`와 `docs/specs/...`를 읽어 다음 단계를 판정
- `route result JSON`을 생성
- 판정 결과에 따라 다음 skill을 자동 실행

### 하지 않는 일

- 문서 본문을 직접 작성하지 않음
- Jira, Confluence, Figma 데이터를 실제로 수집하지 않음
- 상태 파일의 business mutation을 직접 수행하지 않음
- 구현, 검증, 문서 동기화를 직접 하지 않음

즉, `route-workflow`는 controller이고 worker가 아닙니다.

## 전체 흐름

```text
raw user request
-> route-workflow
-> intent normalizer
-> resolved_action
-> decision engine
-> route result JSON
-> short human explanation
-> next skill auto-execute
```

### 내부 컴포넌트 역할

#### 1. `intent normalizer`

- 자유 입력을 내부 action enum으로 정규화
- 명시적 Jira key가 있으면 추출
- 상태 판정에는 자연어 원문을 직접 사용하지 않음

#### 2. `decision engine`

- active ticket, ticket state, artifacts, approvals, verification을 읽음
- 현재 상태에서 시스템이 요구하는 `required_next_skill`을 계산
- `resolved_action`과 `required_next_skill`를 비교해 `decision`을 정함

#### 3. `response formatter`

- `route result JSON`을 바탕으로 짧은 사람용 설명을 생성
- JSON이 진실원본이고 설명 문장은 파생 출력임

## 입력 계약

사용자 입장에서는 단순합니다.

- 입력은 자연어 요청
- 별도 action 명시는 필요 없음

하지만 내부적으로는 아래 구조로 정규화합니다.

```json
{
  "raw_request": "이제 구현 들어가자",
  "resolved_action": "run_implement",
  "requested_ticket": null,
  "resolved_ticket": "FE-123",
  "active_ticket": "FE-123"
}
```

필드 의미:

- `raw_request`
  사용자가 실제로 입력한 자연어
- `resolved_action`
  내부 판정에 사용하는 정규화된 action enum
- `requested_ticket`
  자연어에서 직접 추출한 Jira key가 있으면 기록
- `resolved_ticket`
  최종적으로 라우팅 기준으로 선택된 ticket key
- `active_ticket`
  `.state/index.json`에서 읽은 현재 기본 ticket

### 입력 원칙

- 사용자는 action enum을 몰라도 됨
- 내부 판정은 `resolved_action`만 사용
- `raw_request`는 로그와 설명 생성에는 쓰지만 상태 판정 기준으로 사용하지 않음
- `requested_ticket`이 없으면 `active_ticket`으로 보완

## 내부 action enum

`resolved_action`은 모두 동사형으로 고정합니다.

- `start_ticket`
- `run_intake`
- `run_clarify`
- `run_plan`
- `run_design`
- `run_implement`
- `run_check`
- `run_iterate`
- `run_sync_docs`
- `show_ticket_status`
- `list_tickets`
- `switch_ticket`
- `complete_ticket`

## `resolved_action`과 `next_skill`의 차이

둘은 의도적으로 분리합니다.

- `resolved_action`
  decision engine이 읽는 내부 정규화 값
- `next_skill`
  실제로 자동 실행할 skill 이름

예:

| resolved_action | next_skill |
|---|---|
| `start_ticket` | `start-jira-ticket` |
| `run_intake` | `intake` |
| `run_clarify` | `clarify` |
| `run_plan` | `plan` |
| `run_design` | `design` |
| `run_implement` | `implement` |
| `run_check` | `check` |
| `run_iterate` | `iterate` |
| `run_sync_docs` | `sync-docs` |
| `show_ticket_status` | `show-ticket-status` |
| `list_tickets` | `list-tickets` |
| `switch_ticket` | `switch-ticket` |
| `complete_ticket` | `complete-ticket` |

이렇게 분리하면 내부 판정 언어와 외부 실행 대상을 섞지 않을 수 있습니다.

`complete-ticket`은 terminal handoff를 명시적으로 표현하기 위한 이름입니다. 실제 구현에서는 매우 얇은 wrapper skill이거나 completion handler여도 괜찮지만, 라우터 계약에서는 명시적 대상으로 유지합니다.

## 출력 계약

정식 계약은 구조화된 JSON입니다.

```json
{
  "raw_request": "이제 구현 들어가자",
  "resolved_action": "run_implement",
  "requested_ticket": null,
  "resolved_ticket": "FE-123",
  "current_phase": "design-approved",
  "decision": "execute",
  "next_skill": "implement",
  "reason_code": "ready_to_run_implement",
  "reason": "design 승인 완료, tasks.json 준비됨",
  "requires_user_input": false
}
```

### 필드 설명

- `raw_request`
  원문 요청
- `resolved_action`
  정규화된 내부 action
- `requested_ticket`
  원문에서 추출한 Jira key
- `resolved_ticket`
  실제 판정 기준 ticket
- `current_phase`
  현재 티켓 phase
- `decision`
  `execute | redirect | block`
- `next_skill`
  자동 실행할 skill
- `reason_code`
  고정 enum reason
- `reason`
  사람용 짧은 설명
- `requires_user_input`
  자동 진행 불가 시 사용자 입력 필요 여부

## `decision` 의미

### `execute`

현재 상태와 요청이 맞으므로 해당 skill을 그대로 실행합니다.

### `redirect`

요청은 이해했지만 현재 상태상 더 앞선 단계가 필요합니다. 요청 skill 대신 `required_next_skill`을 실행합니다.

### `block`

자동 진행이 불가능합니다.

예:

- 필수 MCP 누락
- ticket context 부재
- 상태 파일이 손상됨
- 사용자 선택이 먼저 필요함

## `requires_user_input` 의미

`block`과 별도로 유지합니다.

이유는 “오류”와 “사용자 선택 필요”를 구분하기 위해서입니다.

예:

- MCP 누락
  - `decision=block`
  - `requires_user_input=false`
- 티켓 선택 필요
  - `decision=block`
  - `requires_user_input=true`

## `reason_code` enum

`reason_code`는 자유 문자열이 아니라 고정 enum으로 유지합니다.

### 환경/입력 계열

- `missing_required_mcp`
- `unknown_action`
- `no_ticket_context`
- `ticket_switch_required`
- `user_input_required`
- `invalid_state_schema`
- `state_artifact_mismatch`

### 단계 누락/차단 계열

- `missing_ticket_state`
- `missing_intake`
- `missing_clarify`
- `clarify_not_approved`
- `missing_plan`
- `plan_not_approved`
- `missing_design`
- `design_not_approved`
- `missing_tasks`
- `implementation_incomplete`
- `missing_check`
- `check_failed`
- `open_gaps_remaining`
- `docs_not_synced`
- `already_done`

### 실행 가능 계열

- `ready_to_run_intake`
- `ready_to_run_clarify`
- `ready_to_run_plan`
- `ready_to_run_design`
- `ready_to_run_implement`
- `ready_to_run_check`
- `ready_to_run_iterate`
- `ready_to_run_sync_docs`
- `ready_to_complete`

## 판정 데이터 원천

판정 원칙은 `state-first + critical revalidation` 입니다.

### 1차 기준: state-first

기본 판정은 아래 상태를 기준으로 합니다.

- `.colo-fe-flow/.state/index.json`
- `.colo-fe-flow/.state/tickets/<JIRA-KEY>.json`

### 2차 기준: critical revalidation

중요한 전이 직전에는 파일 시스템 재확인을 수행합니다.

예:

- `implement` 진입 전
  - `design.md`
  - `tasks.json`
- `check` 진입 전
  - 구현 완료 여부와 `check.md` 부재 여부
- `sync-docs` 진입 전
  - `check.md`
  - `wrapup.md`
- `complete-ticket` 진입 전
  - `wrapup.md`
  - docs sync 결과

상태와 실제 파일이 다르면 `state_artifact_mismatch`로 처리합니다.

## `required_next_skill` 계산 규칙

`route-workflow`는 먼저 “지금 시스템이 다음에 무엇을 해야 하는가”를 계산합니다.

이 결과가 `required_next_skill`입니다.

| 상태 조건 | required_next_skill | 기본 reason_code |
|---|---|---|
| active ticket 없음 | `start-jira-ticket` | `no_ticket_context` |
| active ticket은 있으나 ticket state 없음 | `intake` | `missing_ticket_state` |
| `intake.md` 없음 | `intake` | `missing_intake` |
| `clarify.md` 없음 | `clarify` | `missing_clarify` |
| clarify 미승인 | `clarify` | `clarify_not_approved` |
| `plan.md` 없음 | `plan` | `missing_plan` |
| plan 미승인 | `plan` | `plan_not_approved` |
| `design.md` 없음 | `design` | `missing_design` |
| design 미승인 | `design` | `design_not_approved` |
| `tasks.json` 없음 | `design` | `missing_tasks` |
| 구현 미완료 | `implement` | `ready_to_run_implement` |
| `check.md` 없음 또는 check 미실행 | `check` | `missing_check` |
| 마지막 check 실패 | `iterate` | `check_failed` |
| `open_gaps > 0` | `iterate` | `open_gaps_remaining` |
| `wrapup.md` 없음 또는 docs 미동기화 | `sync-docs` | `docs_not_synced` |
| 모든 게이트 통과 | `complete-ticket` | `ready_to_complete` |
| 이미 done | `show-ticket-status` | `already_done` |

## `decision` 계산 규칙

`required_next_skill`이 정해지면, 이제 `resolved_action`과 비교해 최종 `decision`을 정합니다.

| 조건 | decision | 동작 |
|---|---|---|
| `resolved_action`이 없더라도 `required_next_skill` 계산 가능 | `execute` | `required_next_skill` 자동 실행 |
| `resolved_action`과 `required_next_skill`가 사실상 일치 | `execute` | 해당 skill 실행 |
| 사용자가 더 뒤 단계를 요청했지만 현재는 앞 단계가 필요 | `redirect` | `required_next_skill` 실행 |
| `show_ticket_status`, `list_tickets`, `switch_ticket` 같은 유틸리티 요청 | `execute` | 해당 utility skill 실행 |
| 사용자 선택이 먼저 필요 | `block` | `requires_user_input=true` |
| MCP 누락, 상태 파손, 복구 불가 오류 | `block` | `requires_user_input=false` |

## 단계별 해석 원칙

### `start-jira-ticket`와 `intake`는 다르다

- `start-jira-ticket`
  작업할 티켓을 정하고 active ticket을 설정
- `intake`
  상태 초기화, 컨텍스트 정규화, `intake.md` 생성

즉, 티켓 선택과 실제 워크플로우 bootstrapping은 분리합니다.

### `design`과 `tasks.json`

`design`이 승인되어도 `tasks.json`이 없으면 `implement`로 바로 가지 않습니다.

이때 라우터는:

- `decision=redirect`
- `next_skill=design`
- `reason_code=missing_tasks`

로 판정합니다.

### `check`, `iterate`, `sync-docs`

- `check`는 구현 후 반드시 거칩니다.
- 실패 또는 `open_gaps > 0`이면 `iterate`
- 통과 후 `wrapup.md` 또는 영향 문서가 최신이 아니면 `sync-docs`

## 예시

### 예시 1. 구현 가능

조건:

- `phase=design-approved`
- `artifacts.tasks.exists=true`
- `implementation.finished=false`

결과:

```json
{
  "resolved_action": "run_implement",
  "decision": "execute",
  "next_skill": "implement",
  "reason_code": "ready_to_run_implement",
  "reason": "design 승인 완료, tasks.json 준비됨",
  "requires_user_input": false
}
```

### 예시 2. 구현 요청이 들어왔지만 tasks가 없음

조건:

- 사용자 요청: `이제 구현 들어가자`
- `phase=design-approved`
- `artifacts.tasks.exists=false`

결과:

```json
{
  "resolved_action": "run_implement",
  "decision": "redirect",
  "next_skill": "design",
  "reason_code": "missing_tasks",
  "reason": "design은 승인되었지만 tasks.json이 없어 implement로 진행할 수 없음",
  "requires_user_input": false
}
```

### 예시 3. 티켓이 정해지지 않음

조건:

- active ticket 없음
- 자연어에서 명시적 Jira key도 없음

결과:

```json
{
  "resolved_action": "run_plan",
  "decision": "block",
  "next_skill": null,
  "reason_code": "no_ticket_context",
  "reason": "현재 작업할 ticket context가 없어 다음 단계를 결정할 수 없음",
  "requires_user_input": true
}
```

## 구현 시 꼭 지킬 것

- `route-workflow`는 worker가 되지 않도록 유지
- 자연어 원문을 직접 상태 판정 조건으로 쓰지 않음
- `reason_code`는 enum으로 유지
- 상태 파일이 주 기준이지만 중요한 전이에서는 파일 시스템 재검증
- `route result JSON`이 진실원본이고 사람용 설명은 파생 출력

## 함께 읽을 문서

- `./local-runtime-schema.md`
- `./workflow.md`
- `./state-schema.md`
- `./task-format.md`
