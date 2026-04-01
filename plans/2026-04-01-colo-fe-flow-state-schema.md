# colo-fe-flow state schema

## 목적

이 문서는 `colo-fe-flow`의 로컬 상태 파일 구조를 정의합니다.

상태 스키마의 목적은 아래와 같습니다.

- `route-workflow`가 현재 단계와 다음 단계 판단에 사용할 기준 제공
- 멀티 티켓 작업을 로컬에서 안전하게 관리
- `check -> iterate -> sync-docs` 루프를 추적
- worktree, branch, approvals, verification, docs sync 상태를 일관되게 저장

이 문서에서 정의하는 상태는 `.colo-fe-flow/.state/` 아래에 저장됩니다.

## 상태 저장 원칙

- 상태는 파일 기반 JSON으로 저장
- 전역 상태와 티켓별 상태를 분리
- 전역 상태는 최소 정보만 저장
- 티켓별 상태가 실제 제어의 중심
- 문서 산출물은 상태 파일이 아니라 `docs/specs/...`에 저장
- 상태 파일은 산출물의 존재 여부와 현재 진행 상태를 기록

## 디렉터리 구조

```text
.colo-fe-flow/
  .state/
    index.json
    tickets/
      FE-123.json
      FE-456.json
```

## 1. 전역 상태: `index.json`

### 역할

- 현재 활성 티켓 관리
- 열려 있는 티켓 목록 관리
- 티켓과 worktree의 빠른 매핑 제공
- router가 기본 티켓 컨텍스트를 고를 때 사용

### 필드 정의

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

### 필드 설명

- `schema_version`
  - 상태 스키마 버전
- `active_ticket`
  - 현재 기본 컨텍스트로 사용할 티켓 키
- `open_tickets`
  - 로컬 상태가 존재하는 티켓 목록
- `ticket_worktrees`
  - 티켓별 worktree 경로 인덱스
- `last_ticket`
  - 마지막으로 활성 상태였던 티켓
- `updated_at`
  - 전역 상태 마지막 갱신 시각

## 2. 티켓 상태: `.state/tickets/<JIRA-KEY>.json`

### 역할

- 특정 Jira 티켓의 전체 워크플로우 상태 저장
- phase, 승인, 검증, 문서 동기화 상태 관리
- router의 핵심 판단 기준

### 전체 예시

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

## 3. 필드 상세 정의

### 기본 필드

- `schema_version`
  - 상태 스키마 버전
- `ticket_key`
  - Jira 티켓 키
- `status`
  - 전체 상태
  - 예: `active`, `blocked`, `done`, `archived`
- `phase`
  - 현재 워크플로우 단계
  - 예: `intake`, `clarify-draft`, `plan-approved`, `checking`, `iterating`, `syncing-docs`
- `created_at`
  - 티켓 상태 최초 생성 시각
- `updated_at`
  - 티켓 상태 마지막 갱신 시각

### `sources`

외부 소스 연결 정보를 저장합니다.

#### `sources.jira`

- `issue_id`
- `summary`
- `url`
- `last_synced_at`

#### `sources.confluence`

- 관련 Confluence 페이지 목록
- 각 항목은 `page_id`, `title`, `url`

#### `sources.figma`

- 관련 Figma 노드 목록
- 각 항목은 `file_key`, `node_id`, `url`

### `workspace`

실제 구현이 이뤄지는 로컬 작업 공간 정보를 저장합니다.

- `project_root`
  - 원본 저장소 루트
- `worktree_path`
  - 티켓 전용 worktree 경로
- `branch_name`
  - 티켓 전용 브랜치 이름
- `base_branch`
  - 분기 기준 브랜치

### `artifacts`

각 단계 산출물의 경로와 존재 여부를 저장합니다.

권장 키:

- `intake`
- `clarify`
- `plan`
- `design`
- `tasks`
- `check`
- `wrapup`

각 산출물 공통 필드:

- `path`
- `exists`
- `updated_at`

추가 원칙:

- `tasks`는 `plan.md`, `design.md`에서 파생된 실행용 산출물입니다.
- `tasks.json`은 정식 artifact이지만 승인 게이트 대상은 아닙니다.
- `design.md`가 변경되면 `tasks.json` 재생성이 필요할 수 있습니다.

### `approvals`

승인 게이트 상태를 저장합니다.

권장 키:

- `clarify`
- `plan`
- `design`

비포함 원칙:

- `tasks`는 승인 대상이 아니라 실행용 파생 artifact이므로 `approvals`에 넣지 않습니다.

각 승인 공통 필드:

- `approved`
- `approved_at`

### `implementation`

구현 진행 상태를 저장합니다.

- `started`
- `started_at`
- `finished`
- `finished_at`
- `task_summary.total`
- `task_summary.completed`
- `task_summary.parallel_groups`

### `verification`

검증 상태를 저장합니다.

- `last_check_status`
  - `passed`, `failed`, `not_run`
- `last_check_at`
- `open_gaps`
- `plan_compliance_score`
- `classes.A`
- `classes.B`
- `classes.C`
- `classes.D`

### `doc_sync`

로컬 문서 최신화 상태를 저장합니다.

- `required`
- `completed`
- `last_synced_at`
- `affected_docs`

### `iteration`

재작업 이력을 저장합니다.

- `count`
- `last_reason`

## 4. phase 값 정의

허용되는 phase 값:

- `intake`
- `branch-ready`
- `clarify-draft`
- `clarify-approved`
- `plan-draft`
- `plan-approved`
- `design-draft`
- `design-approved`
- `implementing`
- `checking`
- `iterating`
- `syncing-docs`
- `done`
- `blocked`

## 5. status 값 정의

권장 status 값:

- `active`
- `blocked`
- `done`
- `archived`

`phase`는 현재 단계이고, `status`는 상위 수준의 상태입니다.

예:

- `status=active`, `phase=checking`
- `status=blocked`, `phase=blocked`
- `status=done`, `phase=done`

## 6. router에서 필수로 읽는 필드

`route-workflow`는 최소 아래 필드를 읽어야 합니다.

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

## 7. 상태 전이 예시

### 예시 1: 새 티켓 시작

초기 상태:

```json
{
  "ticket_key": "FE-123",
  "status": "active",
  "phase": "intake"
}
```

### 예시 2: design 승인 후 구현 가능

```json
{
  "ticket_key": "FE-123",
  "status": "active",
  "phase": "design-approved",
  "artifacts": {
    "tasks": { "exists": true }
  },
  "approvals": {
    "clarify": { "approved": true },
    "plan": { "approved": true },
    "design": { "approved": true }
  }
}
```

### 예시 3: check 실패로 iterate

```json
{
  "ticket_key": "FE-123",
  "status": "active",
  "phase": "iterating",
  "verification": {
    "last_check_status": "failed",
    "open_gaps": 2
  },
  "iteration": {
    "count": 1,
    "last_reason": "plan 요구사항 일부 누락"
  }
}
```

### 예시 4: 최종 완료

```json
{
  "ticket_key": "FE-123",
  "status": "done",
  "phase": "done",
  "verification": {
    "last_check_status": "passed",
    "open_gaps": 0
  },
  "doc_sync": {
    "required": true,
    "completed": true
  }
}
```

## 8. 운영 규칙

- `.state`는 기본적으로 Git ignore
- 전역 상태는 최소한만 저장
- 상세 상태는 티켓별 JSON에 저장
- 상태 파일은 사람이 읽을 수 있어야 함
- router와 hooks는 상태 파일을 단일 기준으로 사용
- `artifacts.exists`는 문서 존재 여부를 빠르게 판단하기 위한 캐시이며, 필요 시 파일 시스템으로 재확인 가능해야 함
- `artifacts.tasks`는 구현과 검증이 소비하는 실행 계약으로 유지하되, 승인 여부 판단에는 사용하지 않음

## 9. 향후 확장 가능 필드

MVP 이후 필요 시 추가 가능한 필드:

- `github`
  - PR 링크
  - commit 목록
- `slack`
  - 알림 발송 여부
- `ownership`
  - 담당 agent 또는 담당 개발자
- `risk`
  - 위험도 점수
- `metrics`
  - lead time, iterate 횟수, verification duration

## 최종 정리

`colo-fe-flow`의 상태 스키마는 전역 상태와 티켓 상태를 분리하고, router가 판단해야 하는 최소 필드를 안정적으로 제공하는 데 초점을 둡니다.

핵심은 아래입니다.

- 전역 상태는 얇게
- 티켓 상태는 풍부하게
- `phase`, `approvals`, `verification`, `doc_sync`가 제어의 핵심
- `artifacts.tasks`는 `plan/design`에서 파생된 실행 artifact로 별도 추적
- `check -> iterate -> sync-docs -> done` 흐름을 상태 파일만 보고도 판정할 수 있어야 함
