---
name: implement
description: Use when design-approved work must be implemented with TDD and limited parallel execution for explicitly safe tasks.
user-invocable: true
argument-hint: <JIRA-KEY>
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
---

# implement

`design.md`를 기준으로 TDD 방식으로 구현합니다.

- 입력 기준은 승인된 `design.md`와 `tasks.json` 입니다.
- 결과는 `implementation.started/finished`, `phase=implementing` 갱신입니다.
- `tasks.json` 없이는 진입하지 않습니다.

## 구현 기준

- `hooks/lib/execution.sh`
- `implementation-agent`

Primary agent: `implementation-agent`
Support agent: 없음
