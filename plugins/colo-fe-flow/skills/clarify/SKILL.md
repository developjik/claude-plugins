---
name: clarify
description: Use when a started ticket needs requirement clarification from Jira, Confluence, Figma, and codebase context before planning.
user-invocable: true
argument-hint: <JIRA-KEY>
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
---

# clarify

티켓 요구사항을 구체화하고 `clarify.md`를 작성합니다.

- 입력 기준은 `intake.md` 입니다.
- 결과는 `clarify.md` draft 생성과 `approvals.clarify=false`, `phase=clarify-draft` 입니다.
- 승인 이후에만 `plan` 단계로 넘어갑니다.

## 구현 기준

- `hooks/lib/planning.sh`
- `planning-agent`

Primary agent: `planning-agent`
Support agent: `context-agent`
