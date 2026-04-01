# 프론트엔드 워크플로우 플러그인 MVP 계획

## 목표

`plugins/colo-fe-flow/` 아래에 신규 플러그인을 만들고, 사내 프론트엔드 개발을 Jira 중심의 워크플로우 오케스트레이터로 표준화합니다.

이 플러그인이 반드시 제공해야 하는 핵심은 아래와 같습니다.

- 시작점은 항상 Jira 티켓
- Jira, Confluence, Figma 정보는 MCP를 통해 수집
- 부족한 맥락은 Confluence, Figma, 로컬 코드베이스로 보강
- `clarify -> plan -> design -> implement -> check -> iterate -> sync-docs` 흐름 강제
- 역할이 분리된 5개 에이전트 사용
- 구현 단계에서는 TDD 강제
- 완료 조건에 E2E 포함
- 최종 완료 전 로컬 `docs/` 최신화 필수
- 구현 작업은 작은 단위로 분해하고, 안전한 것만 제한적으로 병렬 실행

## 입력 소스

외부 시스템 접근 원칙:

- Jira 접근은 `atlassian MCP`를 통해 수행
- Confluence 접근은 `atlassian MCP`를 통해 수행
- Figma 접근은 `figma MCP`를 통해 수행
- 외부 시스템 직접 파싱이나 별도 API 래퍼를 MVP 핵심 경로로 두지 않음
- 로컬 코드베이스 분석만 파일 시스템 직접 접근

### Jira

- 작업의 시작점
- 메타데이터, 제목, 설명, 우선순위, 담당자
- 링크된 이슈와 관련 참조

### Confluence

- 요구사항
- 정책 문서
- 배경 문서
- 의사결정 근거

### Figma

- 화면 기준
- 컴포넌트 기준
- UI 플로우 기준

### Codebase

- 현재 아키텍처
- 재사용 가능한 컴포넌트
- 기술적 제약
- 테스트 패턴

## 제품 정의

이 플러그인은 단순한 코딩 보조 도구가 아닙니다.

이 플러그인은 다음 역할을 수행하는 워크플로우 오케스트레이터입니다.

- Jira, Confluence, Figma, Codebase에서 컨텍스트 수집
- 외부 컨텍스트 수집은 MCP-first 방식으로 수행
- 현재 작업이 어떤 단계에 있는지 판정
- 다음으로 허용되는 단계로 라우팅
- 위험한 단계 점프 차단
- 구현 결과를 `plan.md`, `design.md` 기준으로 검증
- 완료 전 로컬 문서 동기화 강제

## MCP 의존성

### 필수 MCP

- `atlassian`
  - Jira
  - Confluence
- `figma`

### MCP 사용 원칙

- 플러그인 루트에 `.mcp.json`을 둔다
- 필수 MCP는 플러그인 수준에서 선언한다
- hooks는 MCP 선언 누락 또는 기본 설정 문제를 검증한다
- 실제 단계 진입 시에는 해당 단계에 필요한 MCP probe를 수행한다

예:

- `start-jira-ticket`: Atlassian MCP probe
- `clarify`, `plan`: Atlassian MCP probe
- `design`, `check`: Figma MCP probe

## 차용 개념

### bkit에서 차용

- 상태 머신
- 승인 게이트
- 단계 전이 규칙
- `check -> iterate` 루프
- 산출물 규약

### Superpowers에서 차용

- 구현 전 `clarify/plan/design` 강제
- TDD 규율
- 검증 전 완료 금지

### 최소 추가 차용

- GSD: 에이전트별 fresh context, 파일 기반 상태 관리
- OmO: 역할별 최소 권한, 검증 후 완료
- gstack: Figma 참조 확인 흐름

## 최상위 구조

### 진입 스킬

- `route-workflow`

이 스킬은 필수 MCP 선언 여부와 현재 단계에 필요한 MCP probe 필요성을 함께 판정합니다.

### 단계 스킬

- `start-jira-ticket`
- `clarify`
- `plan`
- `design`
- `implement`
- `check`
- `sync-docs`
- `show-ticket-status`
- `list-tickets`
- `switch-ticket`

## 에이전트 모델

### 1. intake-agent

책임:

- Jira, Confluence, Figma 참조 수집
- 티켓 컨텍스트 정규화

권한:

- 읽기 전용

### 2. context-agent

책임:

- 현재 코드베이스 분석
- 관련 모듈, 컴포넌트, 라우트, 테스트 식별

권한:

- 읽기 전용

### 3. planning-agent

책임:

- `clarify.md` 작성
- `plan.md` 작성
- `design.md` 작성
- `wrapup.md` 작성

권한:

- 문서 작성 가능
- 코드 수정 금지

### 4. implementation-agent

책임:

- `design.md` 기준 구현
- TDD 준수
- atomic task 단위 구현

권한:

- 코드 수정 가능

### 5. check-agent

책임:

- `plan.md`, `design.md` 대비 구현 검증
- 테스트 및 E2E 결과 판정
- gap 리포트 생성

권한:

- 읽기/검증 전용
- 코드 수정 금지

## 워크플로우

1. `/start-jira-ticket <JIRA-KEY>`
2. 필수 MCP 선언 및 단계별 probe 확인
3. Jira 티켓 정보 조회
4. Confluence, Figma, GitHub 링크 추출
5. 로컬 코드베이스 분석
6. 티켓 전용 `worktree + branch` 생성
7. `intake.md` 생성
8. 개발자 승인
9. `clarify.md` 생성
10. 개발자 승인
11. `plan.md` 생성
12. 개발자 승인
13. `design.md` 생성
14. 개발자 승인
15. `tasks.json` 생성 또는 최신화
16. 구현 작업을 작은 단위로 분해
17. 안전한 작업은 순차 또는 제한적 병렬 모드로 실행
18. TDD로 구현
19. `check` 실행
20. gap이 있으면 `iterate`
21. 다시 `check`
22. gap이 없으면 `sync-docs`
23. 로컬 문서 최신화
24. `done` 처리

## 상태 머신

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

## 검증 모델

### Class A

- format
- lint
- typecheck

### Class B

- unit test
- component test
- hook/store test

### Class C

- integration test

### Class D

- E2E test

## 완료 규칙

코드가 단순히 실행된다고 해서 완료가 아닙니다.

아래 조건을 모두 만족할 때만 완료입니다.

- `plan.md`의 must-have 요구사항이 구현됨
- `design.md`의 핵심 변경 계획이 코드에 반영됨
- Class A 통과
- Class B 통과
- Class D 통과
- `check.md`에서 `open_gaps = 0`
- 필요한 로컬 문서가 모두 최신화됨

## MCP 검증 정책

### hook에서 확인할 것

- `.mcp.json` 존재 여부
- 필수 MCP(`atlassian`, `figma`) 선언 여부

### 단계별 probe에서 확인할 것

- `start-jira-ticket`, `clarify`, `plan`
  - Atlassian MCP로 Jira/Confluence 읽기 가능 여부
- `design`, `check`
  - Figma MCP로 참조 파일/노드 읽기 가능 여부

즉 hook은 선언과 기본 전제를 검증하고, 실제 단계 스킬은 기능 가능 여부를 probe로 검증합니다.

## Check와 Iterate 루프

구현 후에는 반드시 검증을 수행해야 합니다.

`check` 단계에서 확인할 항목:

- `plan.md`의 요구사항 충족 여부
- `design.md`와 실제 구현의 일치 여부
- 테스트 결과
- E2E 결과
- UI 상태 누락 또는 에러 처리 누락 여부

문제가 하나라도 남아 있으면:

- 완료 금지
- `check.md`에 gap 기록
- 워크플로우를 `iterating`으로 전환
- 구현 수정
- 다시 검증

이 루프는 gap이 없어질 때까지 반복합니다.

## 로컬 문서 동기화

`done`이 되려면 로컬 문서가 최신 상태여야 합니다.

반드시 업데이트해야 하는 문서:

- `docs/specs/<ticket-key>/intake.md`
- `docs/specs/<ticket-key>/clarify.md`
- `docs/specs/<ticket-key>/plan.md`
- `docs/specs/<ticket-key>/design.md`
- `docs/specs/<ticket-key>/tasks.json`
- `docs/specs/<ticket-key>/check.md`
- `docs/specs/<ticket-key>/wrapup.md`

또한 영향을 받는 기존 로컬 `docs/` 문서도 함께 업데이트해야 합니다.

규칙:

- 동작이 바뀌면 관련 문서도 갱신
- 컴포넌트 API가 바뀌면 관련 문서도 갱신
- 사용법이나 플로우가 바뀌면 README 또는 가이드도 갱신
- 문서가 바뀌어야 하는데 갱신이 없으면 `done` 금지

## 로컬 상태 관리

상태는 파일 기반으로 관리하며, 로컬 실행 정보는 아래 3개 디렉터리로 분리합니다.

- `.state`: 현재 제어 상태
- `.cache`: 외부 시스템 조회 결과 캐시
- `.log`: 단계 전이, 검증, iterate 이력

권장 구조:

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
    FE-456/
      orchestration.log
```

### `.state`

플러그인의 실제 제어판 역할을 합니다.

포함 정보:

- 현재 활성 티켓
- 열려 있는 티켓 목록
- 현재 phase와 status
- approvals
- artifact 경로
- worktree와 branch
- verification 결과
- iteration 횟수

### `.cache`

Jira, Confluence, Figma에서 읽어온 데이터를 저장합니다.

용도:

- 외부 조회 비용 절감
- 재실행 시 빠른 초기화
- 링크/메타데이터 재사용

주의:

- `.cache`는 SSOT가 아님
- 필요 시 refresh 가능해야 함

### `.log`

포렌식과 디버깅을 위한 실행 이력을 저장합니다.

포함 정보:

- orchestration 단계 전이 로그
- `check` 결과 기록
- `iterate` 이력
- 실패 원인 추적용 로그

### 운영 규칙

- `.state`, `.cache`, `.log`는 기본적으로 Git ignore
- `docs/specs/...` 산출물만 Git tracked
- 전역 상태는 `.state/index.json`에 최소 정보만 저장
- 티켓별 상세 정보는 `.state/tickets/<JIRA-KEY>.json`에 저장

## 멀티 티켓 지원

MVP는 여러 Jira 티켓을 동시에 지원합니다.

원칙:

- 상태는 티켓별로 격리
- worktree와 branch도 티켓별로 격리
- 문서도 `docs/specs/<ticket-key>/` 아래 티켓별로 격리
- router는 현재 활성 티켓과 전체 티켓 목록을 별도로 관리

## Atomic Task 분해

구현 작업은 작은 단위로 쪼개야 합니다.

각 작업은 아래 정보를 포함합니다.

- `task_id`
- `owner_area`
- `depends_on`
- `parallel_safe`

### 병렬 실행 정책

허용:

- 미해결 의존성이 없는 작업만
- `parallel_safe = true`인 작업만

병렬 실행을 피해야 하는 대상:

- 공유 상태 관리
- 전역 라우팅
- 빌드 설정
- 디자인 시스템 핵심 컴포넌트
- 같은 파일을 여러 작업이 동시에 수정하는 경우

MVP에 포함:

- atomic task 분해
- 제한적 병렬 실행

MVP에서 제외:

- 고급 wave scheduler
- 대규모 배치용 full orchestration 엔진

## MVP 포함 범위

- Jira-first 진입
- Confluence/Figma/Codebase 기반 맥락 보강
- 5-agent 구조
- 로컬 파일 기반 상태 관리
- worktree와 branch 생성
- TDD 기반 구현
- E2E 검증
- `check -> iterate` 루프
- 로컬 docs 동기화
- atomic task 분해
- 제한적 병렬 실행
- 승인 게이트

## MVP 제외 범위

- Jira 상태 자동 전이
- PR 자동 생성/머지
- Slack 자동 보고 전체
- 멀티모델 오케스트레이션
- 고급 pause/resume 기능
- full wave execution 엔진
- 외부 문서 자동 동기화

## 최종 정의

이 플러그인은 Jira를 시작점으로 삼고, Confluence, Figma, Codebase를 보조 컨텍스트로 활용하며, 계획과 설계를 강제한 뒤 TDD로 구현하고, E2E를 포함해 검증하고, plan/design gap이 사라질 때까지 iterate하며, 최종적으로 로컬 docs 동기화가 끝나야 완료 처리하는 사내 프론트엔드 워크플로우 오케스트레이터입니다.
