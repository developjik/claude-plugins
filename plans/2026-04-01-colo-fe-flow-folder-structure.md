# colo-fe-flow 폴더 구조

## 목적

이 문서는 `colo-fe-flow` 플러그인의 권장 폴더 구조를 정의합니다.

구조는 아래 두 범주로 나뉩니다.

- 플러그인 소스 구조
- 런타임 생성 구조

## 1. 플러그인 소스 구조

```text
plugins/
  colo-fe-flow/
    .claude-plugin/
      plugin.json
    .mcp.json

    README.md
    CHANGELOG.md

    skills/
      route-workflow/
        SKILL.md
      start-jira-ticket/
        SKILL.md
      clarify/
        SKILL.md
      plan/
        SKILL.md
      design/
        SKILL.md
      implement/
        SKILL.md
      check/
        SKILL.md
      sync-docs/
        SKILL.md
      show-ticket-status/
        SKILL.md
      list-tickets/
        SKILL.md
      switch-ticket/
        SKILL.md

    agents/
      intake-agent.md
      context-agent.md
      planning-agent.md
      implementation-agent.md
      check-agent.md

    hooks/
      hooks.json
      session-start.sh
      pre-tool.sh
      post-tool.sh
      on-agent-start.sh
      on-agent-stop.sh
      lib/
        common.sh
        state.sh
        cache.sh
        log.sh
        dependency-check.sh
        jira.sh
        confluence.sh
        figma.sh
        codebase.sh
        worktree.sh
        routing.sh
        approval.sh
        task-decomposer.sh
        parallel-runner.sh
        verification.sh
        sync-docs.sh

    templates/
      intake.md
      clarify.md
      plan.md
      design.md
      tasks.json
      check.md
      wrapup.md

    docs/
      architecture.md
      workflow.md
      state-schema.md
      task-format.md
      verification.md

    scripts/
      validate.sh
      lint-shell.sh
```

## 2. 디렉터리 역할

### `.claude-plugin/`

- 플러그인 메타데이터
- 엔트리 설정

### `.mcp.json`

- 플러그인 필수 MCP 선언
- MVP 기준 필수 서버:
  - `atlassian`
  - `figma`

### `skills/`

- 사용자가 직접 호출하거나
- `route-workflow`가 라우팅하는 단계별 스킬 정의

### `agents/`

- 5개 에이전트 역할 정의
- 권한과 책임 범위 명시

### `hooks/`

- 세션 시작/종료
- 도구 실행 전후
- 에이전트 시작/종료 시점 자동화

### `hooks/lib/`

- 실제 공통 로직 보관
- 스킬은 얇게 두고, 공통 로직은 여기로 모음
- MCP 선언 검증과 단계별 probe 보조 로직 포함

### `templates/`

- `intake.md`, `plan.md`, `design.md`, `check.md`, `wrapup.md` 템플릿
- `tasks.json` 실행용 task 포맷 템플릿

### `docs/`

- 플러그인 자체 문서
- 아키텍처, 상태 스키마, 검증 정책, 작업 포맷 정의

### `scripts/`

- 검증 스크립트
- 쉘 린트

## 3. 런타임 생성 구조

아래 구조는 플러그인 소스 내부가 아니라, 실제 작업 대상 프로젝트 루트에 생성되는 로컬 런타임 구조입니다.

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

## 4. 런타임 디렉터리 역할

### `.state/`

- 플러그인의 현재 제어 상태
- 현재 phase
- approvals
- artifacts
- verification
- active ticket

### `.cache/`

- Jira, Confluence, Figma에서 읽어온 데이터 캐시
- 재조회 비용 절감
- 라우팅 보조 데이터

### `.log/`

- 단계 전이 이력
- `check` 결과
- `iterate` 이력
- 포렌식/디버깅용 로그

## 5. 문서 산출물 위치

실제 작업 산출물은 프로젝트의 `docs/` 아래에 저장합니다.

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

## 6. 운영 원칙

- 플러그인 소스와 런타임 상태를 절대 섞지 않음
- `plugins/colo-fe-flow/`는 배포 가능한 플러그인 코드
- `.colo-fe-flow/`는 실행 중 생기는 로컬 상태
- `.state`, `.cache`, `.log`는 기본적으로 Git ignore
- `docs/specs/...` 산출물만 Git tracked
- 외부 시스템 접근은 MCP-first로 통일
- hook은 MCP 선언과 기본 전제 검증
- 실제 읽기 가능 여부는 단계 스킬에서 probe로 검증

## 7. 권장 사항

- 스킬은 얇게 유지하고 실제 로직은 `hooks/lib/`로 모음
- 상태와 캐시와 로그의 역할을 섞지 않음
- 에이전트 역할 정의는 `agents/`에서 명확히 문서화
- 템플릿을 먼저 고정하고 스킬은 템플릿 기반으로 동작하게 설계
