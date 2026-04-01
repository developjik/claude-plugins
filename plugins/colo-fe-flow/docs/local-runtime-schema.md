# Local Runtime Schema

`colo-fe-flow`의 로컬 런타임 스키마를 사람 기준으로 설명하는 문서입니다.

이 문서는 처음 이 플러그인을 접하는 사람이 아래를 한 번에 이해할 수 있도록 작성합니다.

- 로컬에 어떤 파일과 디렉터리가 생기는가
- 무엇이 상태이고 무엇이 산출물인가
- `route-workflow`가 어디를 읽고 무엇을 판단하는가
- `tasks.json`은 왜 필요한가

## 한눈에 보는 구조

`colo-fe-flow`는 로컬 데이터를 크게 네 영역으로 나눕니다.

1. `.state`
현재 워크플로우 제어 상태

2. `.cache`
Jira, Confluence, Figma에서 읽어온 외부 데이터 캐시

3. `.log`
단계 전이와 검증 이력

4. `docs/specs/<JIRA-KEY>/`
사람이 읽는 공식 산출물

핵심 원칙은 간단합니다.

- `.state`는 오케스트레이터의 제어 평면입니다.
- `docs/specs/...`는 Git에 남길 공식 문서입니다.
- `.cache`와 `.log`는 실행 보조 데이터입니다.

## 전체 디렉터리 구조

실행 중 프로젝트 루트에는 아래 구조가 생깁니다.

```text
.colo-fe-flow/
  .state/
    index.json
    tickets/
      FE-123.json
      FE-456.json

  .cache/
    jira/
      FE-123.json
    confluence/
      page-123.json
    figma/
      file-abc-node-12_34.json

  .log/
    FE-123/
      orchestration.log
      check-001.json
      check-002.json
```

그리고 사람이 읽고 리뷰하는 산출물은 프로젝트 `docs/` 아래에 저장합니다.

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

## 왜 상태와 산출물을 분리하나

처음 보면 `plan.md`나 `design.md`가 이미 있는데 왜 상태 파일이 또 필요한지 헷갈릴 수 있습니다.

역할이 다릅니다.

- `docs/specs/...`는 사람이 읽고 승인하는 문서입니다.
- `.state/...`는 `route-workflow`, skill, hook이 빠르게 판단하기 위한 제어 데이터입니다.

예를 들어 `route-workflow`는 아래 질문에 답해야 합니다.

- 지금 active ticket이 무엇인가
- `design.md`가 있는가
- `design` 승인이 끝났는가
- `tasks.json`이 준비됐는가
- 마지막 `check`가 실패했는가
- 아직 `sync-docs`로 가야 하는가

이런 판단을 매번 문서 본문 파싱으로 하면 불안정합니다. 그래서 상태 파일에 제어용 메타데이터를 따로 유지합니다.

## 1. 전역 상태: `.state/index.json`

`index.json`은 멀티 티켓 작업을 위한 전역 인덱스입니다.

예시:

```json
{
  "schema_version": 1,
  "active_ticket": "FE-123",
  "open_tickets": [
    "FE-123",
    "FE-456"
  ],
  "ticket_worktrees": {
    "FE-123": "/abs/path/to/repo/.worktrees/FE-123",
    "FE-456": "/abs/path/to/repo/.worktrees/FE-456"
  },
  "last_ticket": "FE-123",
  "updated_at": "2026-04-01T11:00:00+09:00"
}
```

필드 의미:

- `schema_version`
  상태 스키마 버전
- `active_ticket`
  기본 컨텍스트로 사용할 현재 티켓
- `open_tickets`
  로컬 상태 파일이 존재하는 티켓 목록
- `ticket_worktrees`
  티켓별 worktree 경로 인덱스
- `last_ticket`
  직전에 active였던 티켓
- `updated_at`
  마지막 갱신 시각

이 파일은 얇게 유지합니다. 실제 제어 정보는 티켓 상태 파일에 들어갑니다.

## 2. 티켓 상태: `.state/tickets/<JIRA-KEY>.json`

이 파일이 실제 워크플로우 제어의 중심입니다.

예시:

```json
{
  "schema_version": 1,
  "ticket_key": "FE-123",
  "status": "active",
  "phase": "checking",
  "created_at": "2026-04-01T10:00:00+09:00",
  "updated_at": "2026-04-01T11:20:00+09:00",
  "sources": {
    "jira": {
      "issue_id": "10001",
      "summary": "Checkout 페이지 개선",
      "url": "https://jira.example.com/browse/FE-123",
      "last_synced_at": "2026-04-01T10:02:00+09:00"
    },
    "confluence": [
      {
        "page_id": "88991",
        "title": "Checkout UX 개선안",
        "url": "https://confluence.example.com/..."
      }
    ],
    "figma": [
      {
        "file_key": "abc123",
        "node_id": "12:34",
        "url": "https://figma.com/..."
      }
    ]
  },
  "workspace": {
    "project_root": "/abs/path/to/repo",
    "worktree_path": "/abs/path/to/repo/.worktrees/FE-123",
    "branch_name": "feature/FE-123-checkout-improvement",
    "base_branch": "main"
  },
  "artifacts": {
    "intake": {
      "path": "docs/specs/FE-123/intake.md",
      "exists": true,
      "updated_at": "2026-04-01T10:10:00+09:00"
    },
    "clarify": {
      "path": "docs/specs/FE-123/clarify.md",
      "exists": true,
      "updated_at": "2026-04-01T10:30:00+09:00"
    },
    "plan": {
      "path": "docs/specs/FE-123/plan.md",
      "exists": true,
      "updated_at": "2026-04-01T10:45:00+09:00"
    },
    "design": {
      "path": "docs/specs/FE-123/design.md",
      "exists": true,
      "updated_at": "2026-04-01T11:00:00+09:00"
    },
    "tasks": {
      "path": "docs/specs/FE-123/tasks.json",
      "exists": true,
      "updated_at": "2026-04-01T11:01:00+09:00"
    },
    "check": {
      "path": "docs/specs/FE-123/check.md",
      "exists": true,
      "updated_at": "2026-04-01T11:18:00+09:00"
    },
    "wrapup": {
      "path": "docs/specs/FE-123/wrapup.md",
      "exists": false,
      "updated_at": null
    }
  },
  "approvals": {
    "clarify": {
      "approved": true,
      "approved_at": "2026-04-01T10:31:00+09:00"
    },
    "plan": {
      "approved": true,
      "approved_at": "2026-04-01T10:46:00+09:00"
    },
    "design": {
      "approved": true,
      "approved_at": "2026-04-01T11:02:00+09:00"
    }
  },
  "implementation": {
    "started": true,
    "started_at": "2026-04-01T11:03:00+09:00",
    "finished": true,
    "finished_at": "2026-04-01T11:15:00+09:00",
    "task_summary": {
      "total": 4,
      "completed": 4,
      "parallel_groups": 1
    }
  },
  "verification": {
    "last_check_status": "failed",
    "last_check_at": "2026-04-01T11:18:00+09:00",
    "open_gaps": 2,
    "plan_compliance_score": 84,
    "classes": {
      "A": "passed",
      "B": "passed",
      "C": "not_run",
      "D": "failed"
    }
  },
  "doc_sync": {
    "required": true,
    "completed": false,
    "last_synced_at": null,
    "affected_docs": [
      "docs/README.md",
      "docs/guides/checkout.md"
    ]
  },
  "iteration": {
    "count": 1,
    "last_reason": "에러 상태 UI 누락 및 E2E checkout 실패 시나리오 미통과"
  }
}
```

## 3. 티켓 상태 필드 읽는 법

### 기본 식별 필드

- `ticket_key`
  이 상태 파일이 어떤 Jira 티켓을 위한 것인지
- `status`
  상위 수준 상태
  예: `active`, `blocked`, `done`, `archived`
- `phase`
  현재 워크플로우 단계
  예: `plan-approved`, `implementing`, `checking`

`status`와 `phase`는 다릅니다.

- `status`는 티켓의 큰 상태
- `phase`는 지금 정확히 어느 단계인지

예:

- `status=active`, `phase=implementing`
- `status=done`, `phase=done`

### `sources`

외부 컨텍스트 연결 정보입니다.

- `sources.jira`
  기본 Jira 이슈 정보
- `sources.confluence`
  관련 요구사항/정책 문서 목록
- `sources.figma`
  관련 Figma 노드 목록

### `workspace`

실제 구현이 이뤄지는 로컬 작업 공간 정보입니다.

- `project_root`
- `worktree_path`
- `branch_name`
- `base_branch`

### `artifacts`

단계별 산출물의 경로와 존재 여부입니다.

권장 키:

- `intake`
- `clarify`
- `plan`
- `design`
- `tasks`
- `check`
- `wrapup`

각 항목은 공통으로 아래 필드를 가집니다.

- `path`
- `exists`
- `updated_at`

중요한 점:

- `artifacts`는 문서 본문을 저장하지 않습니다.
- 산출물의 위치와 존재/최신성만 저장합니다.
- 필요하면 파일 시스템으로 다시 확인할 수 있습니다.

### `approvals`

승인 게이트 상태입니다.

권장 키:

- `clarify`
- `plan`
- `design`

각 항목은:

- `approved`
- `approved_at`

중요한 점:

- `tasks`는 `approvals`에 들어가지 않습니다.
- `tasks.json`은 승인 대상이 아니라 실행용 파생 산출물입니다.

### `implementation`

구현 진행 상황입니다.

- `started`
- `started_at`
- `finished`
- `finished_at`
- `task_summary.total`
- `task_summary.completed`
- `task_summary.parallel_groups`

### `verification`

`check` 결과와 테스트 상태입니다.

- `last_check_status`
- `last_check_at`
- `open_gaps`
- `plan_compliance_score`
- `classes.A`
- `classes.B`
- `classes.C`
- `classes.D`

### `doc_sync`

문서 동기화 상태입니다.

- `required`
- `completed`
- `last_synced_at`
- `affected_docs`

### `iteration`

재작업 이력입니다.

- `count`
- `last_reason`

## 4. `tasks.json`은 정확히 무엇인가

처음 보는 사람에게 가장 헷갈리는 지점이 이것입니다.

`tasks.json`은 구현 단계에서 사용할 실행 계약입니다.

역할:

- `plan.md`, `design.md`를 실제 구현 task로 분해
- 어떤 task가 어떤 파일을 건드리는지 명시
- 병렬 실행 가능 여부를 명시
- TDD step과 test command를 명시

즉:

- `plan.md`, `design.md`는 사람 중심의 의사결정 문서
- `tasks.json`은 agent와 runner가 소비하는 실행 문서

중요 규칙:

- `tasks.json`은 정식 artifact입니다.
- 하지만 승인 대상은 아닙니다.
- `design.md`가 바뀌면 `tasks.json` 재생성이 필요할 수 있습니다.
- `route-workflow`는 `design` 승인 후에도 `tasks.json`이 없으면 바로 `implement`로 보내지 않습니다.

## 5. phase 값

티켓 상태의 `phase`는 아래 값을 사용합니다.

```text
intake
branch-ready
clarify-draft
clarify-approved
plan-draft
plan-approved
design-draft
design-approved
implementing
checking
iterating
syncing-docs
done
blocked
```

이 값은 단계 전이를 명시적으로 표현하기 위한 것입니다. 감으로 해석하지 않고 그대로 읽으면 됩니다.

## 6. `route-workflow`가 실제로 읽는 것

`route-workflow`는 티켓 상태 파일에서 대략 아래 필드들을 읽으면 다음 단계를 판단할 수 있습니다.

- `ticket_key`
- `status`
- `phase`
- `artifacts.intake.exists`
- `artifacts.clarify.exists`
- `artifacts.plan.exists`
- `artifacts.design.exists`
- `artifacts.tasks.exists`
- `artifacts.check.exists`
- `artifacts.wrapup.exists`
- `approvals.clarify.approved`
- `approvals.plan.approved`
- `approvals.design.approved`
- `implementation.finished`
- `verification.last_check_status`
- `verification.open_gaps`
- `doc_sync.completed`

예를 들어:

- `design` 승인 완료 + `tasks.json` 없음
  아직 구현 진입 금지
- `tasks.json` 있음 + 구현 미시작
  `implement` 가능
- 마지막 `check` 실패
  `iterate`
- `check` 통과 + `wrapup.md` 없음
  `sync-docs`

## 7. 캐시와 로그는 무엇을 담나

### `.cache`

외부 시스템에서 읽어온 데이터를 다시 사용하기 위한 캐시입니다.

예:

- Jira 이슈 상세
- Confluence 페이지 메타데이터
- Figma 파일/노드 메타데이터

목적:

- 반복 조회 비용 절감
- 같은 데이터를 여러 단계에서 재사용
- 라우팅과 계획 단계의 응답 속도 개선

### `.log`

실행 이력과 포렌식 데이터입니다.

예:

- `orchestration.log`
- `check-001.json`
- `check-002.json`

목적:

- 어떤 단계가 언제 실행됐는지 확인
- 실패한 `check` 결과를 보존
- `iterate` 이력을 추적

## 8. Git에 넣는 것과 넣지 않는 것

기본 원칙:

- `.state`, `.cache`, `.log`는 Git ignore
- `docs/specs/...` 산출물은 Git tracked

이유:

- 상태, 캐시, 로그는 실행 중 바뀌는 로컬 데이터
- `intake.md`, `plan.md`, `design.md`, `wrapup.md`는 협업과 리뷰 대상

## 9. 처음 쓰는 사람이 기억할 것

이 플러그인을 처음 보면 아래 세 줄만 기억해도 충분합니다.

- `.state`는 오케스트레이터가 읽는 제어 상태입니다.
- `docs/specs/<ticket>/`는 사람이 읽는 공식 문서입니다.
- `tasks.json`은 `plan/design`에서 파생된 실행 계약입니다.

그리고 마지막으로 가장 중요한 구분은 이것입니다.

- 승인 대상: `clarify`, `plan`, `design`
- 실행 대상: `tasks`
- 검증 대상: `check`
- 마감 대상: `wrapup`과 영향받은 로컬 `docs/`
