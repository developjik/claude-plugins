---
name: complete-ticket
description: Marks a ticket as done after verification passed and docs were synced.
user-invocable: true
argument-hint: <JIRA-KEY>
allowed-tools: Read, Write, Bash, Grep, Glob
---

# complete-ticket

최종 완료 조건이 충족된 ticket을 `done` 상태로 전이합니다.

- 전제 조건은 passed verification, `wrapup.md` 존재, `doc_sync.completed=true` 입니다.
- 결과는 `status=done`, `phase=done` 입니다.

## 구현 기준

- `hooks/lib/execution.sh`
