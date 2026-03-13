# 아키텍처

## 확장 PDCA 워크플로우

```mermaid
graph LR
    P["1. Plan<br/>계획 수립"] --> DS["2. Design<br/>코드 변경 설계"]
    DS --> DO["3. Do<br/>TDD 구현"]
    DO --> C["4. Check<br/>리뷰+검증+반복"]
    C -->|"불일치 → Iterate<br/>최대 10회"| DO
    C -->|"일치"| W["5. Wrap-up<br/>정리+문서화"]
```

## 에이전트-스킬 관계

```mermaid
graph TB
    subgraph "에이전트 (인지 모드)"
        ST[strategist<br/>CEO/PM]
        AR[architect<br/>기술 리드]
        EN[engineer<br/>구현]
        GU[guardian<br/>감사]
        LI[librarian<br/>문서화]
        DB[debugger<br/>디버깅]
    end
    subgraph "스킬 (실행 작업)"
        PL[/plan]
        DE[/design]
        IM[/implement]
        CH[/check]
        WR[/wrapup]
        DG[/debug]
    end
    ST -.-> PL
    AR -.-> DE
    EN -.-> IM
    GU -.-> CH
    LI -.-> WR
    DB -.-> DG
```

## 훅 라이프사이클

```mermaid
sequenceDiagram
    participant U as User
    participant CC as Claude Code
    participant H as Hooks

    U->>CC: 세션 시작
    CC->>H: SessionStart → session-start.sh
    Note over H: 디렉토리 초기화, Git 감지

    U->>CC: 도구 사용 요청
    CC->>H: PreToolUse → pre-tool.sh
    Note over H: Bash 명령 차단 / 파일 백업
    CC->>CC: 도구 실행
    CC->>H: PostToolUse → post-tool.sh
    Note over H: 변경 추적 / 로깅

    U->>CC: 에이전트 전환
    CC->>H: SubagentStart → on-agent-start.sh
    Note over H: PDCA 단계 자동 추적
    CC->>H: SubagentStop → on-agent-stop.sh

    U->>CC: 세션 종료
    CC->>H: SessionEnd → session-end.sh
```

## 런타임 산출물

| 경로 | 내용 |
|:-----|:-----|
| `~/.harness-engineering/logs/session.log` | 세션 로그 |
| `~/.harness-engineering/logs/security.log` | 차단된 명령 로그 |
| `~/.harness-engineering/state/pdca-phase.txt` | 현재 PDCA 단계 |
| `~/.harness-engineering/state/current-agent.txt` | 현재 에이전트 |
| `~/.harness-engineering/state/changes.txt` | 파일 변경 이력 |
| `~/.harness-engineering/backups/` | 편집 전 백업 |
