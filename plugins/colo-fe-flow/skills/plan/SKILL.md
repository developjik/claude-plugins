---
name: plan
description: Use when clarified ticket context must be turned into a concrete implementation plan with execution order and verification scope.
user-invocable: true
argument-hint: <JIRA-KEY>
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
---

# plan

구체화된 요구사항을 기반으로 `plan.md`를 작성합니다.

- 입력 기준은 승인된 `clarify.md` 입니다.
- 결과는 `plan.md` draft 생성과 `approvals.plan=false`, `phase=plan-draft` 입니다.
- 승인 이후에만 `design` 단계로 넘어갑니다.

## 구현 기준

- `hooks/lib/planning.sh`
- `planning-agent`

Primary agent: `planning-agent`
Support agent: `context-agent`
