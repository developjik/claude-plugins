# Fresh Context (Context Rot 방지) 요구사항 (Plan)

## 1. 초기 질문 및 답변 (Initial Questions & Answers)

### Q1: Context Rot을 언제 감지할까요?
**A:** 복합 지표
- 토큰 사용량 + 작업 수 + 시간을 종합적으로 고려
- 단일 지표보다 정확한 감지 가능

### Q2: 서브에이전트에 위임할 작업 유형은?
**A:** 모든 작업
- 코드 작성, 검증 작업, 문서 작성 모두 위임 가능
- 독립적으로 실행 가능한 작업은 신선한 컨텍스트에서 처리

### Q3: Context Rot 감지 시 사용자 알림 방식은?
**A:** 조용히 자동 처리
- 상태 파일에만 기록
- 사용자 경험 방해 최소화
- 로그에서 확인 가능

---

## 2. 코드베이스 분석 요약 (Codebase Analysis Summary)

### 현재 아키텍처
- **Agent 시스템**: 6개 전문 에이전트 (strategist, architect, engineer, guardian, librarian, debugger)
- **Skill 시스템**: 13개 실행 스킬 (clarify, plan, design, implement, check, wrapup, harness, debug, fullrun, quick, grill-me, delegate, recover)
- **Hook 시스템**: 6개 이벤트 훅 (SessionStart, PreToolUse, PostToolUse, SubagentStart, SubagentStop, SessionEnd)
- **상태 관리**: `.harness/state/`에 현재 상태 저장

### 기존 서브에이전트 활용
- `skills/*/SKILL.md`에서 이미 Agent 도구 사용 권장
- `harness` 스킬에서 서브에이전트 호출 패턴 존재
- `fullrun` 스킬에서 전체 PDCA 자동 실행

### GSD 참고 구현
- **Wave 기반 실행**: 독립 태스크 병렬 실행
- **컨텍스트 보존 파일**: PROJECT.md, STATE.md 등
- **신선한 컨텍스트**: 각 태스크에 200k 토큰 할당

---

## 3. 목표 (Goal)

긴 세션에서 발생하는 Context Rot(컨텍스트 품질 저하)을 감지하고, 서브에이전트에 신선한 컨텍스트를 할당하여 일관된 작업 품질을 유지한다.

---

## 4. 요구사항 (Requirements)

### 기능 요구사항 (FR)

#### FR-1: Context Rot 감지
- [ ] FR-1.1: 복합 지표 기반 Context Rot 감지 시스템 구현
  - 토큰 사용량 (가중치 0.4)
  - 작업 누적 수 (가중치 0.3)
  - 세션 지속 시간 (가중치 0.3)
- [ ] FR-1.2: Context Rot 점수 계산 (0.0 ~ 1.0)
- [ ] FR-1.3: 임계값 설정 가능 (기본값: 0.7)

#### FR-2: 서브에이전트 컨텍스트 관리
- [ ] FR-2.1: 서브에이전트 호출 시 현재 상태 요약 전달
- [ ] FR-2.2: 작업별 독립 컨텍스트 할당
- [ ] FR-2.3: 서브에이전트 결과 통합 메커니즘

#### FR-3: 작업 위임 시스템
- [ ] FR-3.1: 모든 작업 유형 위임 지원 (코드, 검증, 문서)
- [ ] FR-3.2: 작업 의존성 분석 및 순차 실행
- [ ] FR-3.3: 독립 작업 병렬 실행

#### FR-4: 상태 지속성
- [ ] FR-4.1: 컨텍스트 보존 파일 관리 (PROJECT.md, STATE.md)
- [ ] FR-4.2: 세션 간 상태 전달
- [ ] FR-4.3: 작업 히스토리 유지

#### FR-5: 훅 시스템 통합
- [ ] FR-5.1: `hooks/common.sh`에 Context Rot 감지 함수 추가
- [ ] FR-5.2: `hooks/on-agent-start.sh`에서 서브에이전트 컨텍스트 최적화
- [ ] FR-5.3: 자동 Context Rot 로깅

### 비기능 요구사항 (NFR)

- NFR-1: **성능**: Context Rot 감지 < 5ms
- NFR-2: **투명성**: 사용자 경험 방해 없음
- NFR-3: **호환성**: 기존 Agent 시스템과 통합
- NFR-4: **확장성**: 새로운 감지 지표 추가 가능

---

## 5. 제약 조건 (Constraints)

- **기술 스택**: Bash (hooks), Markdown (상태 파일)
- **Claude Code 제약**: 직접 토큰 수 조회 불가 → 추정 필요
- **호환성**: 기존 자동화 레벨 시스템과 통합
- **기존 시스템**: `.harness/` 디렉토리 구조 유지

---

## 6. 스코프 (Scope)

### 포함 (In-Scope)
- 복합 지표 기반 Context Rot 감지
- 서브에이전트 컨텍스트 최적화 가이드
- 상태 파일 기반 컨텍스트 보존
- 자동 로깅 및 상태 추적

### 제외 (Out-of-Scope)
- 실제 토큰 사용량 API 연동
- LLM-as-Judge 품질 평가
- 멀티 모델 합의 시스템
- GUI 대시보드

---

## 7. 성공 기준 (Success Criteria)

1. **기능 검증**
   - [ ] Context Rot 점수가 정확히 계산됨
   - [ ] 임계값 초과 시 자동으로 로그 기록
   - [ ] 서브에이전트 호출 시 상태 요약이 전달됨

2. **사용자 경험**
   - [ ] 사용자 개입 없이 자동 동작
   - [ ] 기존 워크플로우와 동일한 경험
   - [ ] 로그에서 Context Rot 상태 확인 가능

3. **품질 유지**
   - [ ] 긴 세션에서도 작업 품질 일관성
   - [ ] 서브에이전트 결과 품질 향상

---

## 8. 의존성 (Dependencies)

### 선행 기능 (Prerequisite Features)
- [x] `automation-levels`: L0-L4 자동화 레벨 시스템 (완료)

### 외부 의존성 (External Dependencies)
- **Claude Code**: Agent 도구, Hook 시스템
- **jq**: JSON 파싱 (기존 사용 중)

---

## 9. Context Rot 점수 계산

```
context_rot_score = (token_usage × 0.4)
                  + (task_count × 0.3)
                  + (session_duration × 0.3)

where:
  token_usage = estimated_tokens / 200000  (0.0 ~ 1.0)
  task_count = min(tool_calls / 50, 1.0)   (0.0 ~ 1.0)
  session_duration = min(minutes / 60, 1.0) (0.0 ~ 1.0)

임계값:
  < 0.5: 건강함
  0.5 ~ 0.7: 주의
  >= 0.7: Context Rot 감지 → 서브에이전트 권장
```

---

## 10. 파일 구조 예시

```
.harness/
├── state/
│   ├── context-rot-score    # 현재 점수
│   ├── tool-call-count      # 도구 호출 횟수
│   ├── session-start-time   # 세션 시작 시간
│   └── task-history.jsonl   # 작업 이력
├── logs/
│   └── context-rot.jsonl    # Context Rot 이벤트 로그
└── context/
    ├── PROJECT.md           # 프로젝트 컨텍스트
    └── STATE.md             # 현재 상태 요약
```

---

## 11. 다음 단계

➡️ **Design 단계**: `/design fresh-context` 로 구체적 구현 계획을 수립하세요.
