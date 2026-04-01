# Artifact Lifecycle

`colo-fe-flow`에서 생성하고 추적하는 산출물의 역할, 생성 시점, 승인 여부, 상태 갱신 규칙을 정리한 문서입니다.

이 문서는 사람이 읽고 이해하는 기준 문서입니다. 각 skill과 agent는 이 문서에서 정의한 artifact lifecycle을 따라야 합니다.

## 목적

이 문서는 아래 질문에 답하기 위해 존재합니다.

- 어떤 파일이 공식 artifact인가
- 누가 그 artifact를 만드는가
- 언제 생성되고 언제 다시 만들어야 하는가
- 어떤 artifact가 승인 대상인가
- 어떤 artifact가 다음 단계의 gate 역할을 하는가

## 전제

먼저 구분부터 명확히 합니다.

- `.state/index.json`, `.state/tickets/<JIRA-KEY>.json` 는 state입니다.
- `intake.md`, `clarify.md`, `plan.md`, `design.md`, `tasks.json`, `check.md`, `wrapup.md` 는 artifacts입니다.

즉:

- state는 오케스트레이터의 제어 데이터
- artifact는 사람이 읽거나 실행이 소비하는 공식 산출물

## Artifact 목록

프로젝트 루트의 공식 artifact 위치는 아래를 기준으로 합니다.

```text
docs/
  specs/
    FE-123/
      intake.md
      clarify.md
      plan.md
      design.md
      tasks.json
      check.md
      wrapup.md
```

## 핵심 원칙

- formal approval 대상은 `clarify.md`, `plan.md`, `design.md`만입니다.
- `tasks.json`은 정식 artifact이지만 승인 대상이 아닌 실행용 파생 산출물입니다.
- `check.md`는 최신 검증 결과를 설명하는 보고서입니다.
- `wrapup.md`는 완료 직전 문서 동기화 결과를 요약하는 마감 산출물입니다.
- upstream artifact가 바뀌면 downstream artifact는 stale로 취급할 수 있어야 합니다.

## Artifact Lifecycle 표

| Artifact | Owner Skill | Primary Producer | 생성 시점 | Formal Approval | 수정/재생성 규칙 | 상태 갱신 | 다음 게이트 의미 |
|---|---|---|---|---|---|---|---|
| `intake.md` | `intake` | `intake-agent` 중심, 필요시 `context-agent` 보조 | `start-jira-ticket` 후 ticket/worktree/bootstrap 준비 직후 | 아니오 | Jira 링크, Confluence/Figma 참조, 기본 범위가 바뀌면 재생성 가능 | `artifacts.intake.*` | 있으면 `clarify` 가능 |
| `clarify.md` | `clarify` | `planning-agent` | `intake` 완료 후 | 예 | 승인 전 자유 수정 가능. 승인 후 수정되면 `approvals.clarify=false` 로 되돌림 | `artifacts.clarify.*`, `approvals.clarify.*`, `phase=clarify-draft/approved` | 승인되면 `plan` 가능 |
| `plan.md` | `plan` | `planning-agent` | `clarify` 승인 후 | 예 | 승인 전 자유 수정 가능. 승인 후 수정되면 `approvals.plan=false` | `artifacts.plan.*`, `approvals.plan.*`, `phase=plan-draft/approved` | 승인되면 `design` 가능 |
| `design.md` | `design` | `planning-agent` | `plan` 승인 후 | 예 | 승인 전 자유 수정 가능. 승인 후 수정되면 `approvals.design=false` | `artifacts.design.*`, `approvals.design.*`, `phase=design-draft/approved` | 승인되면 `tasks.json` 생성 필수 |
| `tasks.json` | `design` | `planning-agent` 또는 design stage task generator | `design` 승인 직후, 구현 전 | 아니오 | `plan.md` 또는 `design.md` 변경 시 재생성 필요 | `artifacts.tasks.*` | 있어야 `implement` 가능 |
| `check.md` | `check` | `check-agent` | 구현 후 `check` 실행 시 | 아니오 | 매 check 실행마다 최신 결과로 갱신 | `artifacts.check.*`, `verification.*`, `phase=checking` | 실패면 `iterate`, 성공이면 `sync-docs` 후보 |
| `wrapup.md` | `sync-docs` | `planning-agent` 또는 doc writer 역할 | `check` 통과 후 `sync-docs` 단계 | 아니오 | 코드/문서가 다시 바뀌면 stale 처리 후 재작성 가능 | `artifacts.wrapup.*`, `doc_sync.*`, `phase=syncing-docs` | 있으면 `done` 직전 조건 일부 충족 |

## Artifact별 설명

### `intake.md`

`intake.md`는 작업 bootstrapping artifact입니다.

주요 역할:

- 작업할 Jira ticket을 실제 워크플로우에 올림
- 기본 메타데이터와 참조 링크를 정리
- 지금 시점에서 확보된 범위와 근거를 기록

중요한 점:

- formal approval gate는 두지 않습니다.
- `start-jira-ticket`와 다르게, 실제 working context를 문서와 상태로 초기화하는 단계입니다.

### `clarify.md`

`clarify.md`는 아직 모호한 점을 해소하기 위한 artifact입니다.

주요 역할:

- 질문과 가정 정리
- 리스크와 열린 이슈 정리
- 구현 전에 해소해야 할 불확실성 명시

중요한 점:

- formal approval 대상입니다.
- 승인 전까지는 draft입니다.
- 승인 후 수정되면 다시 미승인 상태로 돌아가야 합니다.

### `plan.md`

`plan.md`는 구현 계획 artifact입니다.

주요 역할:

- 구현 범위 명시
- must-have 요구사항 정리
- 검증 방향 정리

중요한 점:

- formal approval 대상입니다.
- 승인 후 수정되면 downstream 산출물에 영향이 갑니다.

### `design.md`

`design.md`는 구현 구조와 변경 설계를 확정하는 artifact입니다.

주요 역할:

- 어떤 구조로 구현할지 정의
- UI, 상태, 데이터 흐름, 파일 책임을 명시
- 실행 단위로 분해하기 전 최종 설계 기준 제공

중요한 점:

- formal approval 대상입니다.
- `design.md` 승인만으로는 구현 시작이 아닙니다.
- 그 다음 반드시 `tasks.json`이 생성돼야 합니다.

### `tasks.json`

`tasks.json`은 실행 계약 artifact입니다.

주요 역할:

- `plan.md`, `design.md`를 실제 구현 task로 분해
- 파일 변경 범위, 병렬 가능 여부, TDD step, test command를 명시

중요한 점:

- 정식 artifact입니다.
- 승인 대상은 아닙니다.
- `plan.md` 또는 `design.md`가 바뀌면 재생성 대상입니다.
- 없으면 `implement` 단계로 진입할 수 없습니다.

### `check.md`

`check.md`는 최신 검증 결과 artifact입니다.

주요 역할:

- 구현이 계획/설계와 얼마나 맞는지 설명
- 테스트와 E2E 결과 요약
- `open_gaps`와 unresolved 문제 기록

중요한 점:

- 승인 대상은 아닙니다.
- 매번 `check` 실행 시 최신 결과로 갱신됩니다.
- 이력 보존은 `.log/check-*.json`이 맡고, `check.md`는 사람용 최신 보고서입니다.

### `wrapup.md`

`wrapup.md`는 마감 artifact입니다.

주요 역할:

- 최종 변경사항 요약
- 영향받은 로컬 문서 동기화 결과 정리
- 완료 직전 상태를 사람이 리뷰할 수 있게 정리

중요한 점:

- 승인 대상은 아닙니다.
- `sync-docs` 단계의 결과물입니다.
- 코드나 문서가 다시 변경되면 stale 처리 후 다시 써야 할 수 있습니다.

## Invalidation 규칙

upstream artifact가 바뀌면 downstream artifact는 stale로 간주할 수 있어야 합니다.

### 권장 규칙

- `intake.md` 변경
  - `clarify`, `plan`, `design`, `tasks`, `check`, `wrapup` 재검토 필요
- `clarify.md` 변경
  - `plan`, `design`, `tasks`, `check`, `wrapup` stale
- `plan.md` 변경
  - `design`, `tasks`, `check`, `wrapup` stale
- `design.md` 변경
  - `tasks`, `check`, `wrapup` stale
- `tasks.json` 변경
  - 진행 중 구현과 `check`, `wrapup` stale 가능
- `check.md` 변경
  - upstream invalidation 없음
- `wrapup.md` 변경
  - completion 판단만 영향

## 상태 갱신 원칙

artifact 자체는 `docs/specs/...` 아래에 저장하고, 상태 파일은 메타데이터만 추적합니다.

예:

- `artifacts.<name>.path`
- `artifacts.<name>.exists`
- `artifacts.<name>.updated_at`

승인 대상 artifact는 별도 approval 상태도 같이 갱신합니다.

예:

- `approvals.clarify.*`
- `approvals.plan.*`
- `approvals.design.*`

## Skill 경계 원칙

artifact lifecycle을 깨뜨리지 않기 위해 아래 경계를 유지합니다.

### `start-jira-ticket`

- ticket 선택과 active ticket 설정만 책임집니다.
- 공식 artifact를 만들지 않습니다.

### `intake`

- 상태 초기화
- 기본 컨텍스트 수집
- `intake.md` 생성

즉, `start-jira-ticket`와 `intake`는 분리합니다.

### `design`

- `design.md` 작성과 승인 이후
- `tasks.json`이 준비된 상태까지 책임집니다.

즉, `design` 단계는 설계 문서만 쓰고 끝나지 않습니다.

### `check`

- `check.md`와 `verification.*`를 갱신합니다.
- 실패 시 `iterate`로 넘길 근거를 남깁니다.

### `sync-docs`

- `wrapup.md` 작성
- 영향받은 로컬 `docs/` 최신화
- `doc_sync.*` 갱신

## 라우터와의 연결

`route-workflow`는 artifact lifecycle을 바탕으로 다음 단계를 판정합니다.

예:

- `design.md` 승인 완료 + `tasks.json` 없음
  - `design`으로 redirect
- `tasks.json` 있음 + 구현 미완료
  - `implement` 가능
- `check.md` 실패 또는 `open_gaps > 0`
  - `iterate`
- `wrapup.md` 없음 또는 docs 미동기화
  - `sync-docs`

## 처음 읽는 사람이 기억할 것

이 문서를 다 읽지 않아도 아래만 기억하면 충분합니다.

- 승인 대상은 `clarify.md`, `plan.md`, `design.md`만이다.
- `tasks.json`은 실행용 파생 artifact다.
- `check.md`는 최신 검증 보고서다.
- `wrapup.md`는 마감 문서다.
- upstream 문서가 바뀌면 downstream artifact는 stale가 될 수 있다.

## 함께 읽을 문서

- `./local-runtime-schema.md`
- `./route-workflow-contract.md`
- `./workflow.md`
- `./state-schema.md`
