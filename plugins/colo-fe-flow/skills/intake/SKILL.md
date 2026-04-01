---
name: intake
description: Bootstraps the selected Jira ticket into the local workflow by creating ticket state, normalizing initial context, and generating intake.md.
user-invocable: true
allowed-tools: Read, Write, Grep, Glob, Bash, Agent, mcp__atlassian__*, mcp__figma__*
---

# intake

선택된 Jira ticket을 실제 `colo-fe-flow` 워크플로우에 올리는 bootstrap 단계입니다.

## 역할

- active ticket을 기준으로 ticket bootstrap 시작
- ticket state가 없으면 생성
- workspace/worktree 기본 경로를 준비
- Jira 기반 기본 context를 state에 기록
- `docs/specs/<JIRA-KEY>/intake.md` 생성

## 입력

- 기본적으로 `.colo-fe-flow/.state/index.json`의 `active_ticket`
- 필요하면 명시적 Jira key
- Jira summary, url, issue id 같은 최소 메타데이터

## 읽는 것

- `.state/index.json`
- 기존 `.state/tickets/<JIRA-KEY>.json`
- Jira ticket 기본 정보
- `templates/intake.md`

## 쓰는 것

- `.state/tickets/<JIRA-KEY>.json`
- `artifacts.intake.*`
- `sources.jira.*`
- `workspace.*`
- `phase=branch-ready`
- `docs/specs/<JIRA-KEY>/intake.md`

## 구현 기준

runtime helper는 아래를 기준으로 합니다.

- `hooks/lib/bootstrap.sh`
- `hooks/lib/state.sh`
- `hooks/lib/worktree.sh`

Primary agent: `intake-agent`
Support agent: `context-agent`

핵심 helper:

- `cff_bootstrap_seed_ticket_state`
- `cff_bootstrap_write_intake`
- `cff_bootstrap_ticket`

## 완료 조건

- active ticket이 결정됨
- ticket state가 존재함
- `sources.jira.*`가 채워짐
- `workspace.worktree_path`, `workspace.branch_name`이 채워짐
- `docs/specs/<JIRA-KEY>/intake.md`가 생성됨
- `artifacts.intake.exists=true`
- 다음 라우팅 결과가 `clarify|missing_clarify`로 이동 가능함
