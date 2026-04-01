# colo-fe-flow task format

## 목적

이 문서는 `colo-fe-flow`가 구현 작업을 어떤 단위로 분해하고, 어떤 형식으로 저장하며, 어떤 기준으로 순차 또는 병렬 실행할지 정의합니다.

이 포맷의 목적은 아래와 같습니다.

- 구현 작업을 너무 크지 않은 atomic task로 쪼개기
- TDD 기반 실행 순서를 강제하기
- 병렬 실행 가능한 작업과 불가능한 작업을 구분하기
- `check -> iterate` 루프에서 어떤 작업이 실패했고 무엇을 다시 해야 하는지 명확히 하기
- `implementation-agent`와 `check-agent`가 공통으로 이해할 수 있는 작업 단위를 제공하기

## 기본 원칙

- 하나의 task는 하나의 명확한 목적만 가진다
- task는 가능하면 2~10분 수준의 작은 단위여야 한다
- 하나의 task는 가능한 한 하나의 책임 영역만 수정한다
- 같은 파일을 여러 task가 동시에 수정하지 않도록 설계한다
- 구현 task에는 반드시 테스트 기준이 포함되어야 한다
- `parallel_safe`는 기본값이 `false`라고 가정한다
- 병렬 실행은 명시적으로 안전하다고 판단된 task에만 허용한다

## 저장 위치

권장 저장 위치:

- `docs/specs/<ticket-key>/design.md` 안의 구현 작업 섹션
- 또는 별도 파일
  - `docs/specs/<ticket-key>/tasks.json`

MVP에서는 `design.md`에 사람이 읽는 요약을 두고, 실제 실행용 포맷은 `tasks.json`으로 저장하는 구조가 가장 적절합니다.

`tasks.json`은 `plan.md`, `design.md`에서 파생되는 실행용 artifact이며, 티켓 상태의 `artifacts.tasks`로 추적하는 것을 권장합니다. 다만 승인 대상 산출물은 아니며 `approvals`에는 포함하지 않습니다.

## 포맷 선택

권장 포맷은 JSON입니다.

이유:

- hooks/lib에서 파싱이 쉽다
- 상태 파일과 자연스럽게 연결된다
- 병렬 그룹과 의존성 처리가 편하다
- `check-agent`가 실패 task를 다시 추적하기 쉽다

## 최상위 구조

```json
{
  "schema_version": 1,
  "ticket_key": "FE-123",
  "generated_from": {
    "plan": "docs/specs/FE-123/plan.md",
    "design": "docs/specs/FE-123/design.md"
  },
  "tasks": []
}
```

## task 기본 스키마

각 task는 아래 필드를 가집니다.

```json
{
  "task_id": "FE-123-T01",
  "title": "Checkout summary 컴포넌트의 에러 상태 렌더링 추가",
  "type": "implementation",
  "owner_area": "checkout-summary",
  "phase": "implement",
  "depends_on": [],
  "parallel_safe": false,
  "files": {
    "create": [],
    "modify": [
      "src/features/checkout/components/CheckoutSummary.tsx",
      "src/features/checkout/components/__tests__/CheckoutSummary.test.tsx"
    ],
    "delete": []
  },
  "acceptance": [
    "에러 상태에서 fallback UI가 렌더링된다",
    "정상 상태에서는 기존 요약 정보가 유지된다"
  ],
  "test_plan": {
    "required": true,
    "levels": ["B"],
    "commands": [
      "pnpm test CheckoutSummary"
    ]
  },
  "figma_refs": [
    {
      "file_key": "abc123",
      "node_id": "12:34"
    }
  ],
  "steps": [],
  "status": "pending"
}
```

## 필드 정의

### `task_id`

- 티켓 내에서 고유해야 함
- 권장 형식: `<JIRA-KEY>-TNN`
- 예: `FE-123-T01`

### `title`

- 사람이 바로 이해할 수 있는 한 줄 설명

### `type`

권장 값:

- `implementation`
- `test`
- `refactor`
- `doc`
- `verification-fix`

MVP에서는 대부분 `implementation` 또는 `verification-fix` 중심이 될 가능성이 큽니다.

### `owner_area`

- 이 task가 속하는 기능 영역 또는 컴포넌트 영역
- 예:
  - `checkout-summary`
  - `payment-form`
  - `order-api-adapter`
  - `checkout-e2e`

이 값은 병렬 실행 시 충돌 감지에 활용할 수 있습니다.

### `phase`

- 현재 task가 어느 단계의 일인지 표시
- MVP 기본값은 대부분 `implement`
- iterate에서 생성된 task는 `iterate`로 표시 가능

### `depends_on`

- 선행되어야 하는 task id 목록
- 비어 있으면 독립 실행 가능

예:

```json
"depends_on": ["FE-123-T01"]
```

### `parallel_safe`

- 병렬 실행 가능 여부
- `true`이면 router 또는 runner가 병렬 후보로 볼 수 있음
- `false`이면 반드시 순차 실행

다음 경우는 기본적으로 `false`:

- 전역 상태 변경
- 라우팅 변경
- 공유 유틸 변경
- 같은 파일 수정
- 공통 디자인 시스템 핵심 컴포넌트 수정

### `files`

- 이 task가 어떤 파일을 생성/수정/삭제하는지 명시

구조:

```json
{
  "create": [],
  "modify": [],
  "delete": []
}
```

이 정보는 병렬 충돌 탐지와 check 단계의 구현 일치 검증에 사용합니다.

### `acceptance`

- 이 task가 끝났는지 판별하는 기준
- 구현 후 check-agent가 참고할 수 있도록 명시

### `test_plan`

구현 task에는 필수입니다.

예:

```json
{
  "required": true,
  "levels": ["A", "B"],
  "commands": [
    "pnpm vitest run src/features/checkout/components/__tests__/CheckoutSummary.test.tsx",
    "pnpm lint"
  ]
}
```

### `figma_refs`

- 해당 task가 참조하는 Figma 노드 목록
- UI 구현 task에서 사용

### `steps`

- 실제 TDD 실행 단계 목록
- 아래 `step format` 참고

### `status`

권장 값:

- `pending`
- `in_progress`
- `done`
- `blocked`
- `failed`

## step format

각 task는 실제 실행 단계인 `steps`를 가집니다.

권장 단계는 TDD 기준으로 아래 구조를 따릅니다.

```json
{
  "step_id": "FE-123-T01-S01",
  "kind": "write_test",
  "description": "에러 상태 렌더링에 대한 실패하는 테스트를 추가한다",
  "run": [
    "pnpm vitest run src/features/checkout/components/__tests__/CheckoutSummary.test.tsx"
  ],
  "expected": "새 테스트가 실패해야 한다",
  "status": "pending"
}
```

권장 `kind` 값:

- `write_test`
- `run_test_fail`
- `write_code`
- `run_test_pass`
- `refactor`
- `run_regression`
- `update_docs`

## 권장 TDD step 순서

구현 task는 가능하면 아래 구조를 따릅니다.

1. `write_test`
2. `run_test_fail`
3. `write_code`
4. `run_test_pass`
5. `refactor`
6. `run_regression`

UI나 문서 영향이 있으면 아래를 추가할 수 있습니다.

7. `update_docs`

## 병렬 실행 규칙

병렬 실행은 아래 조건을 모두 만족해야 합니다.

- `parallel_safe = true`
- `depends_on`가 모두 해결됨
- `files.modify`, `files.create`, `files.delete`에서 다른 병렬 task와 충돌 없음
- 동일 `owner_area`를 동시에 수정하지 않음

### 병렬 실행 가능한 예시

- 서로 다른 독립 컴포넌트 구현
- 독립된 테스트 파일 추가
- 문서 초안 작성

### 병렬 실행 금지 예시

- 같은 페이지 파일 수정
- 같은 전역 store 수정
- 같은 공통 UI primitive 수정
- 라우팅과 E2E를 동시에 꼬이게 만드는 작업

## iterate용 task

`check`에서 gap이 발견되면 새 task를 만들거나 기존 task를 재개할 수 있습니다.

권장 방식:

- 기존 task에 `status=failed` 기록
- 새로운 `verification-fix` task 생성

예:

```json
{
  "task_id": "FE-123-T05",
  "title": "체크아웃 실패 시 에러 토스트 누락 수정",
  "type": "verification-fix",
  "owner_area": "checkout-flow",
  "phase": "iterate",
  "depends_on": ["FE-123-T04"],
  "parallel_safe": false,
  "files": {
    "create": [],
    "modify": [
      "src/features/checkout/pages/CheckoutPage.tsx",
      "tests/e2e/checkout.spec.ts"
    ],
    "delete": []
  },
  "acceptance": [
    "결제 실패 시 에러 토스트가 표시된다",
    "관련 E2E가 통과한다"
  ],
  "test_plan": {
    "required": true,
    "levels": ["D"],
    "commands": [
      "pnpm playwright test tests/e2e/checkout.spec.ts"
    ]
  },
  "figma_refs": [],
  "steps": [],
  "status": "pending"
}
```

## check-agent가 보는 기준

check-agent는 task format을 바탕으로 아래를 검사할 수 있어야 합니다.

- 모든 required task가 완료되었는가
- acceptance 기준이 충족되었는가
- test_plan이 실행되었는가
- 구현된 파일이 design과 일치하는가
- 병렬 실행 중 충돌이 발생하지 않았는가

## planning-agent 생성 규칙

planning-agent는 task를 만들 때 아래 규칙을 따라야 합니다.

- 한 task는 한 목적만 가질 것
- 구현과 문서 수정은 가능하면 분리할 것
- E2E가 필요한 흐름은 별도 task로 명시할 것
- 병렬 실행은 보수적으로 판단할 것
- `parallel_safe`를 남발하지 말 것
- 같은 파일이 두 task에 겹치면 기본적으로 순차 처리로 설계할 것

## doc task 규칙

문서 최신화가 필요한 경우 별도 `doc` 타입 task를 둘 수 있습니다.

예:

```json
{
  "task_id": "FE-123-T99",
  "title": "Checkout 변경사항에 맞춰 로컬 docs 최신화",
  "type": "doc",
  "owner_area": "docs",
  "phase": "sync-docs",
  "depends_on": ["FE-123-T01", "FE-123-T02", "FE-123-T05"],
  "parallel_safe": true,
  "files": {
    "create": [],
    "modify": [
      "docs/README.md",
      "docs/guides/checkout.md",
      "docs/specs/FE-123/wrapup.md"
    ],
    "delete": []
  },
  "acceptance": [
    "Checkout 관련 로컬 문서가 현재 구현과 일치한다",
    "wrapup 문서가 작성된다"
  ],
  "test_plan": {
    "required": false,
    "levels": [],
    "commands": []
  },
  "figma_refs": [],
  "steps": [],
  "status": "pending"
}
```

## 전체 예시

```json
{
  "schema_version": 1,
  "ticket_key": "FE-123",
  "generated_from": {
    "plan": "docs/specs/FE-123/plan.md",
    "design": "docs/specs/FE-123/design.md"
  },
  "tasks": [
    {
      "task_id": "FE-123-T01",
      "title": "Checkout summary 에러 상태 UI 추가",
      "type": "implementation",
      "owner_area": "checkout-summary",
      "phase": "implement",
      "depends_on": [],
      "parallel_safe": true,
      "files": {
        "create": [],
        "modify": [
          "src/features/checkout/components/CheckoutSummary.tsx",
          "src/features/checkout/components/__tests__/CheckoutSummary.test.tsx"
        ],
        "delete": []
      },
      "acceptance": [
        "에러 상태 UI가 렌더링된다"
      ],
      "test_plan": {
        "required": true,
        "levels": ["B"],
        "commands": [
          "pnpm vitest run src/features/checkout/components/__tests__/CheckoutSummary.test.tsx"
        ]
      },
      "figma_refs": [
        {
          "file_key": "abc123",
          "node_id": "12:34"
        }
      ],
      "steps": [
        {
          "step_id": "FE-123-T01-S01",
          "kind": "write_test",
          "description": "실패하는 컴포넌트 테스트 작성",
          "run": [],
          "expected": "테스트 파일이 추가된다",
          "status": "pending"
        },
        {
          "step_id": "FE-123-T01-S02",
          "kind": "run_test_fail",
          "description": "새 테스트가 실패하는지 확인",
          "run": [
            "pnpm vitest run src/features/checkout/components/__tests__/CheckoutSummary.test.tsx"
          ],
          "expected": "새 테스트가 실패한다",
          "status": "pending"
        },
        {
          "step_id": "FE-123-T01-S03",
          "kind": "write_code",
          "description": "최소 구현으로 에러 상태 UI 추가",
          "run": [],
          "expected": "컴포넌트 코드가 수정된다",
          "status": "pending"
        },
        {
          "step_id": "FE-123-T01-S04",
          "kind": "run_test_pass",
          "description": "테스트가 통과하는지 확인",
          "run": [
            "pnpm vitest run src/features/checkout/components/__tests__/CheckoutSummary.test.tsx"
          ],
          "expected": "테스트가 통과한다",
          "status": "pending"
        }
      ],
      "status": "pending"
    }
  ]
}
```

## 최종 정리

`colo-fe-flow`의 task format은 구현을 작은 단위로 나누고, 각 작업의 의존성, 병렬 가능 여부, 테스트 기준을 명시적으로 관리하는 데 초점을 둡니다.

핵심은 아래입니다.

- task는 작고 명확해야 한다
- 병렬 실행은 보수적으로 허용한다
- 구현 task는 TDD 단계를 포함해야 한다
- check-agent가 task 단위로 실패 원인을 추적할 수 있어야 한다
- iterate 시 새 수정 task를 안정적으로 생성할 수 있어야 한다
