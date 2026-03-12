# PDCA 기반 AI 소프트웨어 개발 자동화 워크플로우

## 1. 전체 PDCA 사이클

```mermaid
graph TD
    Start([사용자 입력]) --> Plan["<b>PLAN</b><br/>Architect Agent<br/>설계 및 요구사항 분석"]
    Plan --> |설계 문서| Do["<b>DO</b><br/>Engineer Agent<br/>TDD 기반 구현"]
    Do --> |구현 코드| Check["<b>CHECK</b><br/>Guardian Agent<br/>코드 리뷰 및 검증"]
    Check --> |리뷰 결과| Act["<b>ACT</b><br/>Librarian Agent<br/>문서화"]
    Act --> End([완료])
    
    style Plan fill:#e1f5ff
    style Do fill:#f3e5f5
    style Check fill:#fff3e0
    style Act fill:#e8f5e9
```

---

## 2. PLAN 단계 상세 (Architect)

```mermaid
graph TD
    A1["🎯 사용자 요구사항 입력"] --> A2["📋 요구사항 정제"]
    A2 --> A3["💡 설계 옵션 도출<br/>Option 1 / Option 2 / Option 3"]
    A3 --> A4["⚖️ 옵션 평가<br/>복잡도 / 개발시간 / 유지보수성"]
    A4 --> A5["✅ 최적 설계 선택"]
    A5 --> A6["📄 설계 문서 작성<br/>아키텍처 / 기술스택 / 데이터모델"]
    A6 --> A7["✨ 설계 완료"]
    
    style A1 fill:#e1f5ff
    style A7 fill:#b3e5fc
```

---

## 3. DO 단계 상세 (Engineer)

```mermaid
graph TD
    B1["📄 설계 문서 분석"] --> B2["🔴 RED: 실패하는 테스트 작성"]
    B2 --> B3["🟢 GREEN: 최소 코드로 통과"]
    B3 --> B4["🔵 REFACTOR: 코드 개선"]
    B4 --> B5{모든 기능<br/>완성?}
    B5 --> |No| B2
    B5 --> |Yes| B6["✅ 구현 완료"]
    B6 --> B7["📊 진행률 보고<br/>테스트 커버리지 확인"]
    
    style B2 fill:#ffcdd2
    style B3 fill:#c8e6c9
    style B4 fill:#bbdefb
    style B6 fill:#f3e5f5
```

---

## 4. CHECK 단계 상세 (Guardian)

```mermaid
graph TD
    C1["📝 구현 코드 분석"] --> C2["✅ 기능 정확성 검증"]
    C2 --> C3["📊 코드 품질 평가<br/>SOLID 원칙 / DRY / 복잡도"]
    C3 --> C4["🔒 보안 검사<br/>SQL Injection / XSS / 인증"]
    C4 --> C5["⚡ 성능 분석<br/>알고리즘 복잡도 / DB 쿼리"]
    C5 --> C6["🧪 테스트 검증<br/>커버리지 80% 이상"]
    C6 --> C7{승인?}
    C7 --> |✅ 승인| C8["✨ 리뷰 완료"]
    C7 --> |⚠️ 조건부| C9["🔧 개선 필요"]
    C7 --> |❌ 반려| C10["🔴 주요 문제"]
    C9 --> B2
    C10 --> B2
    
    style C8 fill:#fff3e0
    style C9 fill:#ffe0b2
    style C10 fill:#ffccbc
```

---

## 5. ACT 단계 상세 (Librarian)

```mermaid
graph TD
    D1["📝 코드 분석"] --> D2["📖 README.md 작성"]
    D2 --> D3["🔌 API 문서 작성"]
    D3 --> D4["🏗️ 아키텍처 문서 작성"]
    D4 --> D5["🚀 설치 가이드 작성"]
    D5 --> D6["❓ FAQ 작성"]
    D6 --> D7["✅ 문서화 완료"]
    
    style D7 fill:#e8f5e9
```

---

## 6. Hook 기반 자동화 흐름

```mermaid
graph TD
    H1["🚀 SessionStart"] --> H2["⚙️ 초기화 및 상태 확인"]
    H2 --> H3["👤 사용자 입력"]
    H3 --> H4["✔️ UserPromptSubmit<br/>입력 검증"]
    H4 --> H5["🔨 도구 실행<br/>Read/Write/Edit"]
    H5 --> H6["📝 PostToolUse<br/>파일 변경 로깅"]
    H6 --> H7["🤖 SubagentStart<br/>에이전트 활성화"]
    H7 --> H8["⚙️ 에이전트 작업 수행"]
    H8 --> H9["🛑 SubagentStop<br/>에이전트 종료"]
    H9 --> H10{다음 단계?}
    H10 --> |Yes| H7
    H10 --> |No| H11["🏁 SessionEnd<br/>정리 및 로깅"]
    H11 --> H12["✨ 완료"]
    
    style H1 fill:#c8e6c9
    style H11 fill:#ffccbc
    style H12 fill:#a5d6a7
```

---

## 7. 에이전트 상태 전이도

```mermaid
stateDiagram-v2
    [*] --> Architect: 프로젝트 시작
    
    Architect --> Engineer: 설계 완료
    
    Engineer --> Guardian: 구현 완료
    
    Guardian --> Engineer: 개선 필요
    Guardian --> Librarian: 검증 통과
    
    Librarian --> [*]: 문서화 완료
    
    note right of Architect
        PLAN 단계
        요구사항 분석
        설계 문서 작성
    end note
    
    note right of Engineer
        DO 단계
        RED-GREEN-REFACTOR
        테스트 작성
    end note
    
    note right of Guardian
        CHECK 단계
        코드 리뷰
        품질 검증
    end note
    
    note right of Librarian
        ACT 단계
        기술 문서화
        지식 관리
    end note
```

---

## 8. Skill 호출 흐름

```mermaid
graph TD
    S1["Claude Code 사용자"] --> S2{어떤 작업?}
    
    S2 --> |새 프로젝트| S3["/brainstorm<br/>Brainstorm Skill"]
    S2 --> |구현 시작| S4["/implement<br/>Implement Skill"]
    S2 --> |코드 검증| S5["/review<br/>Review Skill"]
    S2 --> |문서화| S6["/document<br/>Document Skill"]
    
    S3 --> S7["Architect 에이전트<br/>활성화"]
    S4 --> S8["Engineer 에이전트<br/>활성화"]
    S5 --> S9["Guardian 에이전트<br/>활성화"]
    S6 --> S10["Librarian 에이전트<br/>활성화"]
    
    S7 --> S11["설계 문서 생성"]
    S8 --> S12["구현 코드 생성"]
    S9 --> S13["리뷰 결과 생성"]
    S10 --> S14["기술 문서 생성"]
    
    style S3 fill:#e1f5ff
    style S4 fill:#f3e5f5
    style S5 fill:#fff3e0
    style S6 fill:#e8f5e9
```

---

## 9. 데이터 흐름

```mermaid
graph LR
    Input["📝 사용자 입력<br/>프로젝트 설명"] 
    
    Input --> Design["📄 설계 문서<br/>아키텍처<br/>기술스택<br/>데이터모델"]
    
    Design --> Code["💻 구현 코드<br/>테스트 코드<br/>소스 코드"]
    
    Code --> Review["📋 리뷰 결과<br/>품질 평가<br/>개선사항"]
    
    Review --> Docs["📚 기술 문서<br/>API 문서<br/>설치 가이드<br/>아키텍처 문서"]
    
    Docs --> Output["✨ 최종 산출물<br/>완성된 프로젝트"]
    
    style Input fill:#bbdefb
    style Design fill:#c8e6c9
    style Code fill:#ffe0b2
    style Review fill:#f8bbd0
    style Docs fill:#e1bee7
    style Output fill:#a5d6a7
```

---

## 10. 시간 기반 워크플로우

```mermaid
gantt
    title PDCA 기반 개발 프로세스 타임라인
    dateFormat YYYY-MM-DD
    
    section Architect
    요구사항 분석 :arch1, 2024-01-01, 1d
    설계 옵션 도출 :arch2, after arch1, 1d
    설계 문서 작성 :arch3, after arch2, 2d
    
    section Engineer
    테스트 작성 :eng1, after arch3, 2d
    코드 구현 :eng2, after eng1, 3d
    리팩토링 :eng3, after eng2, 1d
    
    section Guardian
    코드 리뷰 :guard1, after eng3, 1d
    품질 검증 :guard2, after guard1, 1d
    
    section Librarian
    문서 작성 :lib1, after guard2, 2d
    검수 :lib2, after lib1, 1d
```

---

## 11. 에러 처리 및 피드백 루프

```mermaid
graph TD
    Start["🚀 작업 시작"] --> Execute["⚙️ 에이전트 실행"]
    Execute --> Result{결과 OK?}
    
    Result --> |✅ 성공| NextPhase["➡️ 다음 단계로"]
    Result --> |⚠️ 경고| Review1["🔍 검토 필요"]
    Result --> |❌ 실패| Error["🔴 에러 처리"]
    
    Review1 --> Improve["🔧 개선"]
    Improve --> Execute
    
    Error --> Debug["🐛 디버깅"]
    Debug --> Execute
    
    NextPhase --> Complete{모든 단계<br/>완료?}
    Complete --> |No| Start
    Complete --> |Yes| End["✨ 완료"]
    
    style Start fill:#c8e6c9
    style End fill:#a5d6a7
    style Error fill:#ffccbc
    style Review1 fill:#ffe0b2
```

---

## 12. 플러그인 아키텍처

```mermaid
graph TB
    User["👤 Claude Code 사용자"]
    
    User --> CLI["🖥️ Claude Code CLI"]
    
    CLI --> Plugin["🔌 Harness Engineering Plugin"]
    
    Plugin --> Agents["🤖 Sub-Agents"]
    Plugin --> Skills["💡 Skills"]
    Plugin --> Hooks["🔗 Hooks"]
    
    Agents --> Arch["Architect"]
    Agents --> Eng["Engineer"]
    Agents --> Guard["Guardian"]
    Agents --> Lib["Librarian"]
    
    Skills --> Brain["Brainstorm"]
    Skills --> Impl["Implement"]
    Skills --> Rev["Review"]
    Skills --> Doc["Document"]
    
    Hooks --> Session["SessionStart/End"]
    Hooks --> SubAgent["SubagentStart/Stop"]
    Hooks --> Tool["PostToolUse"]
    
    Arch --> Output1["설계 문서"]
    Eng --> Output2["구현 코드"]
    Guard --> Output3["리뷰 결과"]
    Lib --> Output4["기술 문서"]
    
    Output1 --> Final["✨ 완성된 프로젝트"]
    Output2 --> Final
    Output3 --> Final
    Output4 --> Final
    
    style Plugin fill:#bbdefb
    style Agents fill:#c8e6c9
    style Skills fill:#ffe0b2
    style Hooks fill:#f8bbd0
    style Final fill:#a5d6a7
```

---

## 13. 의사결정 트리

```mermaid
graph TD
    Start["프로젝트 시작"] --> Q1{새로운<br/>프로젝트?}
    
    Q1 --> |Yes| Arch["Architect 활성화"]
    Q1 --> |No| Q2{어떤 작업?}
    
    Arch --> Design["설계 문서 생성"]
    Design --> Q3{설계<br/>승인?}
    
    Q3 --> |No| Arch
    Q3 --> |Yes| Eng["Engineer 활성화"]
    
    Q2 --> |구현| Eng
    Q2 --> |리뷰| Guard["Guardian 활성화"]
    Q2 --> |문서화| Lib["Librarian 활성화"]
    
    Eng --> Code["구현 코드 생성"]
    Code --> Guard
    
    Guard --> Review["코드 리뷰"]
    Review --> Q4{승인?}
    
    Q4 --> |No| Eng
    Q4 --> |Yes| Lib
    
    Lib --> Docs["기술 문서 생성"]
    Docs --> End["✨ 완료"]
    
    style Start fill:#bbdefb
    style End fill:#a5d6a7
```

---

## 14. 실시간 로깅 및 모니터링

```mermaid
graph TD
    Session["🚀 세션 시작"]
    
    Session --> Log1["[SessionStart]<br/>초기화"]
    Log1 --> Log2["[UserPromptSubmit]<br/>입력 검증"]
    Log2 --> Log3["[SubagentStart: architect]<br/>Architect 시작"]
    Log3 --> Log4["[PostToolUse]<br/>파일 수정 로깅"]
    Log4 --> Log5["[SubagentStop: architect]<br/>Architect 종료"]
    Log5 --> Log6["[SubagentStart: engineer]<br/>Engineer 시작"]
    Log6 --> Log7["[PostToolUse]<br/>파일 수정 로깅"]
    Log7 --> Log8["[SubagentStop: engineer]<br/>Engineer 종료"]
    Log8 --> Log9["[SubagentStart: guardian]<br/>Guardian 시작"]
    Log9 --> Log10["[SubagentStop: guardian]<br/>Guardian 종료"]
    Log10 --> Log11["[SubagentStart: librarian]<br/>Librarian 시작"]
    Log11 --> Log12["[SubagentStop: librarian]<br/>Librarian 종료"]
    Log12 --> Log13["[SessionEnd]<br/>정리"]
    
    Log13 --> File["📝 .claude/logs/session.log<br/>완전한 세션 기록"]
    
    style Session fill:#c8e6c9
    style File fill:#a5d6a7
```

---

## 요약

이 플러그인은 **PDCA 사이클**을 기반으로 다음과 같이 작동합니다:

1. **PLAN (계획)**: Architect가 요구사항을 분석하고 설계 문서를 작성
2. **DO (수행)**: Engineer가 TDD 기반으로 코드를 구현
3. **CHECK (점검)**: Guardian이 코드 품질을 검증하고 리뷰
4. **ACT (조치)**: Librarian이 기술 문서를 작성

각 단계는 **Hooks를 통해 자동으로 연결**되며, **Skills를 통해 개별 작업도 수행** 가능합니다.

모든 활동은 **세션 로그에 기록**되어 완전한 감시와 추적이 가능합니다.
