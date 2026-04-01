---
name: show-ticket-status
description: Shows a concise summary of the current or requested ticket state from local runtime state.
user-invocable: true
argument-hint: <JIRA-KEY>
allowed-tools: Read, Grep, Glob, Bash
---

# show-ticket-status

현재 active ticket 또는 지정한 ticket의 핵심 상태를 빠르게 요약합니다.

- `index.json`과 `tickets/<JIRA-KEY>.json`만 읽습니다.
- state mutation은 하지 않습니다.

## 구현 기준

- `hooks/lib/utility.sh`
- `cff_utility_show_ticket_status_json`
