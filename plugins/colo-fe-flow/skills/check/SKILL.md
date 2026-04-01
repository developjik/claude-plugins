---
name: check
description: Use when implementation must be verified against plan and design, including tests, E2E, and gap reporting.
user-invocable: true
argument-hint: <JIRA-KEY>
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
---

# check

구현 결과를 검증하고 `check.md`를 작성합니다.

- 결과는 `check.md`, `verification.*`, `phase=checking` 입니다.
- 실패 또는 `open_gaps > 0`이면 다음 단계는 `iterate` 입니다.

## 구현 기준

- `hooks/lib/execution.sh`
- `check-agent`

Primary agent: `check-agent`
Support agent: `context-agent`
