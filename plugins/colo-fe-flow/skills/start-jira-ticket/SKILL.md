---
name: start-jira-ticket
description: Selects a Jira issue to start work from and sets or updates the active ticket context. Use when starting Jira ticket work, choosing a work ticket, or changing the current ticket context.
user-invocable: true
allowed-tools: Read, Write, Bash, AskUserQuestion, mcp__atlassian__*
---

# start-jira-ticket

시작할 Jira 티켓을 선택하고, 그 티켓을 이후 워크플로우의 기준 ticket key로 설정하거나 현재 active ticket 문맥을 변경합니다.

## 입력

- 인자 없음
- Jira key는 스킬 내부에서 조회 또는 사용자 선택으로 결정합니다.

## 전제 조건

- 현재 디렉토리가 Git 저장소여야 합니다.
- Atlassian MCP 서버가 연결되어 있어야 합니다.

## 절차

### 1. 현재 active ticket 확인

`.colo-fe-flow/.state/index.json`을 읽어 `active_ticket`이 존재하는지 확인합니다.

- 파일이 존재하고 `active_ticket` 값이 있으면 현재 세션의 active ticket으로 설정합니다.
- 파일이 없거나 값이 없으면 active ticket이 없는 상태로 진행합니다.

이후 단계에서 "같은 티켓 재선택" 또는 "active ticket 변경 확인" 판단에 사용합니다.

### 2. Atlassian Cloud ID 확인

Jira API 호출에 필요한 cloud ID를 먼저 확인합니다.

```
1. .colo-fe-flow/.cache/atlassian-cloud-id.json 파일 확인
2. 파일이 존재하면 저장된 cloudId 사용 (API 호출 생략)
3. 파일이 없으면 mcp__atlassian__* 로 accessible-resources 조회 → cloudId 획득 후 파일에 저장
```

### 3. 현재 사용자 캐시 확인

assignee 조회에 필요한 현재 Jira 사용자 정보를 먼저 로컬에서 확인합니다.

```
1. .colo-fe-flow/.cache/atlassian-current-user.json 파일 확인
2. 파일이 존재하고 저장된 cloudId가 현재 cloud ID와 같으면 저장된 accountId 사용
3. 파일이 없거나 cloudId가 다르면 mcp__atlassian__* 로 현재 사용자 조회
4. 조회한 값을 cloudId와 함께 파일에 저장
```

현재 사용자 캐시는 cloud ID와 함께 관리합니다. account 정보가 없으면 즉시 중단합니다.

### 4. 현재 사용자에게 할당된 미완료 Jira 티켓 조회

현재 사용자에게 assignee 된 Jira 티켓 중 완료되지 않은 항목만 조회합니다.

- JQL: `assignee = "{accountId}" AND statusCategory != Done ORDER BY updated DESC`
- **주의**: `resolution = Unresolved` 대신 `statusCategory != Done`을 사용합니다. Jira에서 "완료" 상태로 전환되어도 resolution 필드가 설정되지 않는 경우가 있어, `resolution = Unresolved`는 완료된 티켓을 누락 없이 필터링하지 못합니다.
- 기본 정렬: 최근 업데이트 순
- 각 티켓은 아래 필드를 포함해야 합니다.

| 컬럼 | 설명 |
|------|------|
| Key | Jira issue key |
| Summary | 이슈 제목 |
| Status | 현재 상태 |
| Priority | 우선순위 |
| Updated | 마지막 업데이트 날짜 |

### 5. 표 출력

조회 결과를 터미널 표로 보여줍니다.

- 표 컬럼은 `Key | Summary | Status | Priority | Updated`
- `Summary`는 한 줄로 읽기 좋게 잘라서 표시합니다.
- `Updated`는 절대 날짜 형식으로 표시합니다. 예: `2026-04-01`

### 6. 티켓 선택 규칙

#### 6-1. 티켓이 2개 이상인 경우

`AskUserQuestion` **하나**로 다음 중 하나를 받습니다. 여러 개의 질문으로 나누지 않습니다.

- `AskUserQuestion`은 최대 4개 선택지를 가질 수 있습니다.
- 티켓이 3개 이하면: 모든 티켓 + 마지막 선택지 `직접 입력`
- 티켓이 4개 이상이면: 최근 업데이트 순 상위 3개 + 마지막 선택지 `직접 입력`
- 사용자가 `직접 입력`을 선택하면 Jira key를 입력받습니다.

#### 6-2. 티켓이 1개인 경우

유일한 티켓을 자동 선택합니다. 단, 자동 선택 사실을 사용자에게 명시적으로 알려야 합니다.

#### 6-3. 티켓이 0개인 경우

사용자에게 할당된 미완료 Jira 티켓이 없다고 알리고 즉시 종료합니다. 이 경우 직접 입력 단계로 넘어가지 않습니다.

### 7. 직접 입력 검증

사용자가 직접 Jira key를 입력한 경우 먼저 `PROJECT-123` 형식인지 검증한 뒤, Jira에서 해당 이슈가 존재하고 현재 사용자가 접근 가능한지 확인합니다. 형식이 잘못되었거나 이슈를 찾을 수 없으면 즉시 중단하고 사용자에게 알립니다.

### 8. 작업 Jira key 설정

최종 Jira key를 현재 작업 대상 ticket key로 설정합니다.

- active ticket은 `.colo-fe-flow/.state/index.json`의 `active_ticket` 필드에 저장되어 관리합니다.
- 현재 active ticket이 없으면 선택된 Jira key를 바로 active ticket으로 설정합니다.
- 현재 active ticket이 있고 선택된 Jira key가 다르면, active ticket을 변경한다는 확인을 `AskUserQuestion`으로 한 번 더 받습니다.
- 현재 active ticket과 같은 Jira key를 다시 선택한 경우, 같은 티켓을 선택했다는 피드백을 사용자에게 주고 그대로 진행합니다.
- 최종 Jira key가 확정되면 `.colo-fe-flow/.state/index.json`의 `active_ticket`을 해당 값으로 갱신합니다.
- active ticket 변경 확인을 사용자가 거절한 경우 `active_ticket`은 변경하지 않습니다.
- worktree 생성, intake 생성, 상태 초기화는 후속 연결 단계에서 수행합니다.

### 9. Jira 티켓 상태 업데이트

선택된 티켓의 현재 상태를 확인하고, 작업 시작을 나타내는 상태로 전환합니다.

- `getTransitionsForJiraIssue`로 해당 티켓의 전이 가능한 상태를 조회합니다.
- 현재 상태가 이미 "진행 중" 상태 카테고리(statusCategory id=4)에 속하면 상태 전환을 생략합니다.
- 현재 상태가 "해야 할 일" 상태 카테고리(statusCategory id=2)에 속하면 "진행 중" 상태로 전환합니다.
  - 전이 대상은 statusCategory가 "indeterminate"(id=4)인 상태 중 첫 번째를 사용합니다.
  - 일반적으로 "진행 중" 상태를 의미합니다.
- 에픽(issuetype hierarchyLevel=1)은 상태 전환을 생략합니다.
- 상태 전환 실패는 치명적 오류가 아니므로 경고만 표시하고 계속 진행합니다.

## 구현 범위

- 이 스킬은 시작할 Jira 티켓을 결정하는 것까지를 책임집니다.
- cloud ID는 캐시 우선으로 조회합니다.
- 현재 사용자 정보는 cloud ID 기준 캐시 우선으로 조회합니다.
- assignee 티켓은 Atlassian MCP로 조회합니다.
- 로컬 상태 초기화와 worktree/bootstrap 연결은 후속 단계에서 수행합니다.

## 산출물

| 파일 | 설명 |
|------|------|
| `.colo-fe-flow/.cache/atlassian-cloud-id.json` | Atlassian cloud ID 캐시 |
| `.colo-fe-flow/.cache/atlassian-current-user.json` | 현재 Jira 사용자 캐시 |
| `.colo-fe-flow/.state/index.json` | active ticket을 포함한 전역 로컬 상태 |
| 터미널 표 출력 | 조회된 assignee 티켓 목록 |
| 선택된 `<JIRA-KEY>` | 이후 단계의 기준 ticket key |

## 완료 기준

- [ ] 현재 `active_ticket`이 확인됩니다.
- [ ] Atlassian cloud ID가 확인되거나 캐시됩니다.
- [ ] 현재 Jira 사용자 정보가 확인되거나 캐시됩니다.
- [ ] assignee 기준 미완료 티켓 목록이 조회됩니다.
- [ ] 조회 결과가 표 형태로 사용자에게 보여집니다.
- [ ] 티켓 수에 따라 자동 선택, 사용자 선택, 또는 종료 규칙이 올바르게 적용됩니다.
- [ ] active ticket이 이미 있을 때 변경 확인 또는 same-ticket 피드백 규칙이 올바르게 적용됩니다.
- [ ] `.colo-fe-flow/.state/index.json`의 `active_ticket`이 최종 Jira key와 일치하도록 갱신됩니다.
- [ ] 최종 Jira key가 현재 작업 대상 ticket key로 설정됩니다.
- [ ] 티켓 상태가 "해야 할 일"이면 "진행 중"으로 전환됩니다 (에픽 제외, 이미 진행 중이면 생략).

## 실패 처리

| 조건 | 동작 |
|------|------|
| cloud ID 조회 실패 | 즉시 종료 |
| 현재 사용자 조회 또는 캐시 확인 실패 | 즉시 종료 |
| assignee 티켓 조회 실패 | 즉시 종료 |
| 조회 결과 0건 | 사용자에게 알리고 종료 |
| 직접 입력 Jira key 형식 오류 | 즉시 종료 |
| 직접 입력 Jira key 이슈 조회 실패 또는 접근 불가 | 즉시 종료 |
| active ticket 변경 확인 거절 | 종료 |
| Git 저장소 아님 | 즉시 종료 |

실패 시 cloud ID 캐시 또는 현재 사용자 캐시만 남을 수 있습니다.

## 다음 단계

작업 Jira key가 결정되면 다음 연결 단계에서 상태 초기화와 로컬 bootstrap을 이어붙입니다.
