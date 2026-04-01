# Agent Responsibility

`colo-fe-flow`의 각 agent가 무엇을 하고 무엇을 하지 않는지, 어떤 skill에서 호출되고 어떤 artifact와 state를 다루는지 정리한 문서입니다.

이 문서는 사람이 읽는 기준 문서입니다. agent 역할이 섞이거나 권한이 넓어지지 않도록 경계를 고정하는 목적을 가집니다.

## 목적

이 문서는 아래를 명확히 하기 위해 존재합니다.

- 각 agent의 책임 범위
- 어떤 skill이 어떤 agent를 호출하는지
- agent별 읽기/쓰기 권한
- 어떤 artifact를 만들거나 갱신할 수 있는지
- 어떤 state를 직접 갱신하면 안 되는지
- agent 간 handoff와 협업 순서

## 핵심 원칙

- agent는 skill의 worker이며, skill을 대체하지 않습니다.
- `route-workflow`는 agent 없이 controller로 동작합니다.
- agent는 자기 역할 범위를 넘는 문서 작성, 코드 수정, 상태 변경을 하지 않습니다.
- state mutation의 최종 책임은 skill에 있습니다.
- agent는 필요한 최소 권한만 가져야 합니다.
- 문서 작성 agent와 코드 수정 agent를 분리합니다.

## Agent 목록

`colo-fe-flow`는 아래 5개 agent를 기준으로 합니다.

- `intake-agent`
- `context-agent`
- `planning-agent`
- `implementation-agent`
- `check-agent`

## Agent 분류

### 1. Read-only agent

- `intake-agent`
- `context-agent`
- `check-agent`

### 2. Document-writing agent

- `planning-agent`

### 3. Code-writing agent

- `implementation-agent`

## Responsibility Matrix

| Agent | 주요 역할 | 주로 호출하는 Skill | 읽기 범위 | 쓰기 범위 | 금지 범위 |
|---|---|---|---|---|---|
| `intake-agent` | Jira/Confluence/Figma 기본 컨텍스트 수집 및 정규화 | `intake` | 외부 참조, 상태, 코드베이스 일부 | 직접 artifact 작성은 안 함. 필요 시 structured notes만 반환 | 코드 수정, approval 변경, verification 판정 |
| `context-agent` | 코드베이스 구조, 관련 파일, 테스트 패턴 분석 | `intake`, `clarify`, `plan`, `design`, `check` | 코드베이스, 테스트, 라우트, 컴포넌트 | 직접 artifact 작성은 안 함. 분석 결과만 반환 | 코드 수정, artifact 확정 작성, approval 변경 |
| `planning-agent` | `clarify.md`, `plan.md`, `design.md`, `tasks.json`, `wrapup.md` 작성 | `clarify`, `plan`, `design`, `sync-docs` | 상태, upstream artifact, context 분석 결과 | 문서 artifact 작성 및 갱신 | 코드 수정, verification 판정 확정 |
| `implementation-agent` | `tasks.json` 기반 TDD 구현 | `implement`, 경우에 따라 `iterate` | codebase, `tasks.json`, `plan.md`, `design.md` | 코드 수정, 테스트 실행, 구현 관련 진행 상태 반환 | approval 변경, `check.md` 작성, wrapup 작성 |
| `check-agent` | 구현 결과 검증과 gap 판정 | `check` | codebase, `plan.md`, `design.md`, `tasks.json`, 테스트 결과 | 직접 코드 수정 없이 검증 보고 결과 반환 | 코드 수정, approval 변경, 구현 보정 |

## Agent별 상세 책임

### `intake-agent`

역할:

- Jira ticket 메타데이터 수집
- Confluence/Figma 참조 링크와 기본 맥락 정리
- 티켓 관련 외부 컨텍스트를 정규화된 입력으로 반환

주로 쓰이는 단계:

- `intake`

읽는 것:

- Jira issue metadata
- Confluence page references
- Figma file/node references
- 필요 시 현재 `.state/index.json`

쓰는 것:

- 직접 파일을 확정 작성하지 않음
- skill이 사용할 structured context 또는 요약만 반환

하지 않는 것:

- `intake.md` 직접 확정 작성
- 코드 수정
- approval 갱신
- verification 판정

중요한 점:

- `intake-agent`는 data collector입니다.
- 최종 `intake.md` 생성과 state bootstrap은 `intake` skill 책임입니다.

### `context-agent`

역할:

- 현재 코드베이스 구조 분석
- 관련 모듈, 컴포넌트, 테스트, 라우트 식별
- 기존 구현 패턴과 제약사항 정리

주로 쓰이는 단계:

- `intake`
- `clarify`
- `plan`
- `design`
- `check`

읽는 것:

- source tree
- tests
- component hierarchy
- routing and state management code

쓰는 것:

- 직접 artifact를 확정 작성하지 않음
- 분석 메모, 후보 파일 목록, 패턴 요약만 반환

하지 않는 것:

- 코드 수정
- approval 갱신
- 검증 최종 판정

중요한 점:

- `context-agent`는 읽기 전용 탐색기입니다.
- planning-agent나 check-agent가 판단할 수 있게 근거를 제공하는 역할입니다.

### `planning-agent`

역할:

- 사람 승인 대상 문서와 문서형 artifact 작성
- 실행 전 계획과 설계 기준을 명시
- `tasks.json`을 실행 계약으로 생성
- `wrapup.md`로 마감 문서 작성

주로 쓰이는 단계:

- `clarify`
- `plan`
- `design`
- `sync-docs`

생성하거나 갱신할 수 있는 artifact:

- `clarify.md`
- `plan.md`
- `design.md`
- `tasks.json`
- `wrapup.md`

읽는 것:

- `intake.md`
- `clarify.md`
- `plan.md`
- `design.md`
- context-agent 분석 결과
- state와 verification 결과

쓰는 것:

- 문서 artifact 본문
- 필요 시 draft 갱신 결과

하지 않는 것:

- 코드 수정
- 테스트 수정
- 구현 보정
- 최종 verification pass/fail 판정

중요한 점:

- `planning-agent`는 문서 작성자입니다.
- `tasks.json`도 이 agent의 산출물로 보는 것이 현재 구조상 가장 자연스럽습니다.
- approval state 자체는 skill이 갱신합니다.

### `implementation-agent`

역할:

- `tasks.json`에 정의된 atomic task 실행
- TDD 순서 준수
- 코드와 테스트 수정
- 구현 결과와 남은 문제를 skill에 반환

주로 쓰이는 단계:

- `implement`
- 경우에 따라 `iterate`

읽는 것:

- `tasks.json`
- `plan.md`
- `design.md`
- 관련 codebase

쓰는 것:

- 코드 파일
- 테스트 파일
- 필요 시 task 진행 상태, 실행 로그

하지 않는 것:

- `check.md` 작성
- approval state 수정
- `wrapup.md` 작성
- 완료 판정

중요한 점:

- 이 agent만 코드 수정 권한을 가집니다.
- 설계 변경이 필요하면 조용히 설계를 바꾸지 말고 upstream 단계로 되돌릴 신호를 줘야 합니다.

### `check-agent`

역할:

- 구현 결과를 계획/설계 기준으로 검증
- 테스트와 E2E 결과 해석
- gap과 failure reason 정리

주로 쓰이는 단계:

- `check`

읽는 것:

- `plan.md`
- `design.md`
- `tasks.json`
- code diff 또는 현재 codebase
- 테스트 결과
- E2E 결과

쓰는 것:

- 직접 코드 수정 없이 검증 결과만 반환
- `check.md` 초안 또는 structured verification result 반환 가능

하지 않는 것:

- 코드 수정
- 구현 보정
- approval 변경

중요한 점:

- `check-agent`는 심판입니다.
- implement와 같은 주체가 되면 안 됩니다.
- verification 결과의 latest write는 `check` skill이 책임집니다.

## Skill과 Agent의 연결

각 skill은 아래 방식으로 agent를 사용할 수 있습니다.

| Skill | 주 Agent | 보조 Agent | 비고 |
|---|---|---|---|
| `route-workflow` | 없음 | 없음 | controller only |
| `start-jira-ticket` | 없음 | 없음 | ticket selection은 skill이 직접 처리 |
| `intake` | `intake-agent` | `context-agent` | 외부 참조 수집 + 코드베이스 1차 맥락 |
| `clarify` | `planning-agent` | `context-agent` | 문서 작성 전 기술 맥락 보강 가능 |
| `plan` | `planning-agent` | `context-agent` | 구현 범위와 파일 책임 정리 |
| `design` | `planning-agent` | `context-agent` | 설계 확정과 `tasks.json` 생성 |
| `implement` | `implementation-agent` | 없음 | 필요 시 planning artifact만 읽음 |
| `check` | `check-agent` | `context-agent` | 검증 기준 보강용 읽기 지원 가능 |
| `iterate` | `implementation-agent` | 필요 시 `planning-agent` | 설계 수정이 필요하면 upstream 재진입 |
| `sync-docs` | `planning-agent` | 없음 | `wrapup.md`와 로컬 docs 업데이트 |
| `complete-ticket` | 없음 | 없음 | 얇은 terminal handoff 가능 |
| `show-ticket-status` | 없음 | 없음 | utility |
| `list-tickets` | 없음 | 없음 | utility |
| `switch-ticket` | 없음 | 없음 | utility |

## 권한 모델

### `intake-agent`

- 권장 도구: read-only
- 코드 수정 금지
- 문서 확정 작성 금지

### `context-agent`

- 권장 도구: read-only
- 코드 수정 금지
- artifact 확정 작성 금지

### `planning-agent`

- 권장 도구: 문서 작성 가능
- 코드 수정 금지
- 검증 판정 전담 금지

### `implementation-agent`

- 권장 도구: 코드/테스트 수정 가능
- 문서 approval 변경 금지
- 검증 판정 금지

### `check-agent`

- 권장 도구: read-only + test execution
- 코드 수정 금지
- repair 작업 금지

## 상태 갱신 책임

중요한 원칙은 agent와 state mutation을 분리하는 것입니다.

- agent는 결과를 생성하거나 반환
- skill이 그 결과를 받아 state를 갱신

예:

- `planning-agent`가 `plan.md`를 작성
- 실제 `artifacts.plan.*`, `approvals.plan.*`, `phase=plan-draft` 갱신은 `plan` skill이 수행

이렇게 해야 agent 교체, 재시도, 병렬 실행이 쉬워집니다.

## 병렬 사용 원칙

병렬화는 제한적으로만 허용합니다.

### 병렬 가능한 경우

- `intake-agent`와 `context-agent`를 함께 돌려 기본 context 수집
- `check-agent`가 검증하는 동안 필요한 read-only context 재확인

### 병렬 금지 또는 보수적으로 처리할 경우

- `implementation-agent`와 다른 code-writing agent의 동시 코드 수정
- `planning-agent`가 `design.md`를 갱신하는 동안 `implementation-agent`가 같은 ticket 구현 진행
- `check-agent`가 판정 중일 때 구현 결과가 계속 바뀌는 상황

## 가장 중요한 경계

### `planning-agent` vs `implementation-agent`

- `planning-agent`
  문서와 실행 계획 작성
- `implementation-agent`
  그 계획을 실제 코드로 실행

### `implementation-agent` vs `check-agent`

- `implementation-agent`
  구현 주체
- `check-agent`
  검증 주체

같은 agent가 둘 다 맡으면 검증 품질이 떨어집니다.

### `intake-agent` vs `context-agent`

- `intake-agent`
  외부 시스템과 ticket context 중심
- `context-agent`
  로컬 코드베이스 중심

## 처음 읽는 사람이 기억할 것

이 문서를 다 읽지 않아도 아래만 기억하면 충분합니다.

- `intake-agent`, `context-agent`, `check-agent`는 읽기 중심이다.
- `planning-agent`는 문서 artifact 작성자다.
- `implementation-agent`만 코드 수정 권한을 가진다.
- state mutation의 최종 책임은 agent가 아니라 skill에 있다.
- 검증 주체와 구현 주체는 분리한다.

## 함께 읽을 문서

- `./local-runtime-schema.md`
- `./route-workflow-contract.md`
- `./artifact-lifecycle.md`
- `./skill-responsibility.md`
- `./workflow.md`
