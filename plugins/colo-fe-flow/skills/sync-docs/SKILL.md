---
name: sync-docs
description: Use when verification has passed and local docs under docs/ must be updated before the ticket can be marked done.
user-invocable: true
argument-hint: <JIRA-KEY>
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, Agent
---

# sync-docs

로컬 `docs/`와 `wrapup.md`를 최신화합니다.

- 결과는 `wrapup.md`, `doc_sync.*`, `phase=syncing-docs` 입니다.
- 완료 후 `complete-ticket`로 넘어갈 수 있습니다.

## 구현 기준

- `hooks/lib/execution.sh`
- `planning-agent`

Primary agent: `planning-agent`
Support agent: 없음
