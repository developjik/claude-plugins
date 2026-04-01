# colo-fe-flow route-workflow 판정표

## 목적

이 문서는 `route-workflow`가 사용자 요청과 현재 티켓 상태를 바탕으로 다음 실행 단계를 어떻게 판정할지 정의합니다.

`route-workflow`는 직접 구현을 수행하지 않습니다.
역할은 아래와 같습니다.

- 현재 작업 상태 확인
- 요청 의도 분류
- 다음으로 허용되는 단계 결정
- 순서 위반 차단
- 적절한 스킬로 라우팅

즉 이 문서는 `colo-fe-flow`의 오케스트레이션 규칙표입니다.

## 기본 원칙

- 모든 요청은 먼저 `route-workflow`를 거친다
- 하위 스킬은 독립적으로 최종 판단하지 않는다
- 현재 상태와 산출물 기준으로 다음 단계만 허용한다
- 외부 시스템 접근은 MCP를 통해서만 수행한다
- 필수 MCP 선언이 없으면 관련 단계 진입을 차단한다
- 구현 후에는 반드시 `check`
- gap이 있으면 반드시 `iterate`
- 문서 최신화 전에는 `done` 금지

## 입력 요소

`route-workflow`는 아래 정보를 기준으로 판정합니다.

### 1. 사용자 요청

예:

- 새 티켓 시작
- 현재 티켓 상태 확인
- 구현 진행
- 검증 실행
- 문서 최신화
- 다른 티켓으로 전환

### 2. 로컬 상태

위치:

- `.colo-fe-flow/.state/index.json`
- `.colo-fe-flow/.state/tickets/<JIRA-KEY>.json`

확인 항목:

- active ticket
- current phase
- approvals
- verification 결과
- iteration count

### 3. 산출물 존재 여부

- `intake.md`
- `clarify.md`
- `plan.md`
- `design.md`
- `tasks.json`
- `check.md`
- `wrapup.md`

### 4. 검증 상태

- Class A 통과 여부
- Class B 통과 여부
- Class D 통과 여부
- `open_gaps`
- 마지막 `check` 상태

### 5. MCP 상태

- `.mcp.json` 존재 여부
- `atlassian` 선언 여부
- `figma` 선언 여부
- 단계별 probe 필요 여부

## 상태 기반 라우팅 규칙

| 조건 | router 판단 | 다음 단계 |
|---|---|---|
| 필수 MCP 선언 누락 | 의존성 문제 | `dependency-check` 또는 설정 수정 유도 |
| 티켓 상태 파일이 없음 | 새 작업으로 간주 | `start-jira-ticket` |
| 티켓은 있으나 `intake.md` 없음 | intake 필요 | `start-jira-ticket` |
| `intake.md` 있음, `clarify.md` 없음 | 구체화 필요 | `clarify` |
| `clarify.md` 있음, clarify 미승인 | 승인 필요 | `clarify` 유지 |
| clarify 승인됨, `plan.md` 없음 | 계획 필요 | `plan` |
| `plan.md` 있음, plan 미승인 | 승인 필요 | `plan` 유지 |
| plan 승인됨, `design.md` 없음 | 설계 필요 | `design` |
| `design.md` 있음, design 미승인 | 승인 필요 | `design` 유지 |
| design 승인됨, `tasks.json` 없음 | 실행 task 생성 필요 | `design` 유지 |
| design 승인됨, `tasks.json` 있음, 구현 시작 전 | 구현 가능 | `implement` |
| 구현 완료 표시 있음, `check.md` 없음 | 검증 필요 | `check` |
| 마지막 check 결과가 fail | 재작업 필요 | `iterate` |
| `open_gaps > 0` | 재작업 필요 | `iterate` |
| check 통과, `wrapup.md` 없음 | 문서 최신화 필요 | `sync-docs` |
| check 통과, docs 영향 있음, docs 미갱신 | 문서 최신화 필요 | `sync-docs` |
| check 통과, docs 최신화 완료 | 완료 가능 | `done` |

## 요청 기반 라우팅 규칙

| 사용자 요청 | 현재 상태 | router 동작 |
|---|---|---|
| 새 Jira 티켓 시작 | 필수 MCP 선언 누락 | 차단 후 MCP 설정 유도 |
| 새 Jira 티켓 시작 | 상태 없음 | `start-jira-ticket` 실행 |
| 구현해달라 | `design-approved` 이전 | 구현 차단 후 `clarify/plan/design` 중 필요한 단계로 이동 |
| 구현해달라 | `design-approved` 이후, `tasks.json` 없음 | 구현 차단 후 `design`으로 이동 |
| 구현해달라 | `design-approved` 이후, `tasks.json` 있음 | `implement` |
| 검증해달라 | 구현 전 | 검증 차단 후 구현 단계 유도 |
| 검증해달라 | 구현 후 | `check` |
| 완료 처리해달라 | `check` 미완료 | 완료 차단 후 `check` |
| 완료 처리해달라 | gap 있음 | 완료 차단 후 `iterate` |
| 완료 처리해달라 | docs 미동기화 | 완료 차단 후 `sync-docs` |
| 현재 상태 보여달라 | 언제든 가능 | `show-ticket-status` |
| 다른 티켓 보고싶다 | 다중 티켓 존재 | `switch-ticket` 또는 `list-tickets` |

## 차단 규칙

아래 경우에는 다음 단계로 진행하면 안 됩니다.

### 구현 차단

구현은 아래 중 하나라도 해당하면 차단합니다.

- 필수 MCP 선언 누락
- clarify 미완료
- plan 미완료
- design 미완료
- design 미승인
- `tasks.json` 미생성

### 완료 차단

완료는 아래 중 하나라도 해당하면 차단합니다.

- `check` 미실행
- 테스트 실패
- E2E 실패
- `open_gaps > 0`
- 문서 최신화 미완료

### 단계 점프 차단

예:

- intake 없이 plan 진행
- plan 없이 design 진행
- design 없이 implement 진행
- check 없이 done 진행

이 경우 router는 점프를 허용하지 않고 필요한 이전 단계로 돌려보냅니다.

### MCP 차단

아래 경우 관련 단계 진입을 차단합니다.

- `atlassian` 선언 없음
  - `start-jira-ticket`
  - `clarify`
  - `plan`
- `figma` 선언 없음
  - `design`
  - `check`

## iterate 판정 규칙

아래 중 하나라도 참이면 `iterating`으로 전환합니다.

- `plan.md` 요구사항 누락
- `design.md`의 핵심 변경 사항 누락
- `tasks.json`과 구현 범위가 불일치
- 테스트 실패
- E2E 실패
- 핵심 UI state 누락
- 에러 처리 누락
- check 결과 문서에 unresolved gap 존재

## sync-docs 판정 규칙

`sync-docs`는 아래 조건에서 반드시 수행해야 합니다.

- 구현과 검증이 끝났음
- `open_gaps = 0`
- `wrapup.md`가 아직 없음
- 기존 `docs/` 영향 문서가 아직 최신화되지 않음

`sync-docs` 완료 기준:

- `wrapup.md` 생성
- 영향받은 로컬 `docs/` 문서 업데이트 완료
- 문서와 코드 간 불일치 없음

## done 판정 규칙

아래 조건을 모두 만족해야 `done`입니다.

- design 승인 완료
- 구현 완료
- Class A 통과
- Class B 통과
- Class D 통과
- `check.md` 기준 `open_gaps = 0`
- `wrapup.md` 생성 완료
- 로컬 `docs/` 최신화 완료

## 멀티 티켓 판정 규칙

### active ticket 없음

- 사용자가 특정 `JIRA-KEY`를 주면 해당 티켓 기준으로 상태 조회 또는 시작
- 특정 키가 없으면 `list-tickets` 또는 티켓 지정 요구

### active ticket 있음

- 명시적 다른 `JIRA-KEY`가 들어오면 해당 티켓으로 컨텍스트 전환
- 키가 없으면 active ticket 기준으로 라우팅

### 티켓 전환 필요

아래 경우 router는 `switch-ticket`를 유도할 수 있습니다.

- 현재 active ticket과 요청 티켓이 다름
- 사용자가 다른 티켓 상태를 조회하고 싶음
- 여러 티켓이 열려 있고 명시적 지정이 없음

## router 출력 형식 제안

```json
{
  "ticket_key": "FE-123",
  "current_phase": "design-approved",
  "requested_action": "implement",
  "decision": "allow",
  "next_skill": "implement",
  "reason": "design 승인 완료, 구현 가능 상태"
}
```

차단 예시:

```json
{
  "ticket_key": "FE-123",
  "current_phase": "plan-approved",
  "requested_action": "implement",
  "decision": "block",
  "next_skill": "design",
  "reason": "design 산출물 및 design 승인 없이 구현 단계로 갈 수 없음"
}
```

## 구현 원칙

- router는 얇게 유지
- 실제 판정 로직은 상태 조회 함수와 규칙 함수로 분리
- 상태 파일과 산출물 체크 결과를 조합해서 판정
- MCP 선언 검증과 단계별 probe 필요성도 함께 판정
- 감이 아니라 명시적 규칙으로만 다음 단계를 결정

## 최종 정리

`route-workflow`는 `colo-fe-flow`의 핵심 제어기입니다.

이 컴포넌트는:

- 사용자의 자유 입력을 받아도
- 현재 상태와 산출물을 근거로
- 올바른 다음 단계만 허용하고
- 잘못된 점프를 차단하며
- `check -> iterate -> sync-docs`까지 강제하는 역할을 맡습니다.
