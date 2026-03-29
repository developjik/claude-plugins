# Automation Levels (L0-L4) 요구사항 (Plan)

## 1. 초기 질문 및 답변 (Initial Questions & Answers)

### Q1: L0-L4 자동화 레벨의 기본값은?
**A:** L2 Semi-Auto (권장)
- 일반 작업은 자동 진행
- 중요 결정(PDCA 단계 전환)만 사용자 승인 필요

### Q2: 신뢰 점수(Trust Score) 시스템도 함께 구현할까요?
**A:** 네, 함께 구현
- 성과에 따라 자동화 레벨 자동 조정 기능 포함

### Q3: 사용자가 자동화 레벨을 변경하는 방법은?
**A:** 설정 파일 편집
- `.harness/config.yaml` 파일로 관리
- 명령어 방식은 v2에서 고려

### Q4: 어떤 작업에 자동화 레벨을 적용할까요?
**A:** PDCA 단계 전환
- Plan → Design → Implement → Check → Wrapup 전환 시
- 각 전환에서 승인/자동 여부를 레벨에 따라 결정

---

## 2. 코드베이스 분석 요약 (Codebase Analysis Summary)

### 현재 아키텍처
- **3계층 구조**: 프롬프트 계층(skills/agents) → 운영 자동화 계층(hooks) → 산출물/상태 계층(docs/specs, .harness/)
- **훅 시스템**: 6개 이벤트 (SessionStart, PreToolUse, PostToolUse, SubagentStart, SubagentStop, SessionEnd)
- **상태 관리**: `.harness/state/`에 현재 PDCA 단계, 에이전트 상태 저장

### 기존 통합 지점
- `hooks/common.sh`: 공통 헬퍼 함수 (json_query, harness_project_root, harness_runtime_dir 등)
- `hooks/on-agent-start.sh`: 에이전트 전환 시 PDCA 단계 추적
- `.harness/state/`: 현재 상태 저장 위치

### bkit 참고 구현
- `automation.defaultLevel`: 기본 자동화 레벨 (2)
- `automation.trustScoreEnabled`: 신뢰 점수 활성화
- `automation.autoEscalation/autoDowngrade`: 자동 레벨 조정
- `pdca.automationLevel`: "semi-auto" 등 문자열 기반

---

## 3. 목표 (Goal)

사용자가 자신의 워크스타일과 프로젝트 특성에 맞게 PDCA 워크플로우의 자동화 정도를 5단계(L0~L4)로 조절할 수 있는 시스템을 구현한다. 신뢰 점수를 기반으로 자동화 레벨을 동적으로 조정하여, 숙련된 사용자는 더 빠른 작업이 가능하고 초보자는 안전하게 학습할 수 있다.

---

## 4. 요구사항 (Requirements)

### 기능 요구사항 (FR)

#### FR-1: 자동화 레벨 정의 및 저장
- [ ] FR-1.1: 5단계 자동화 레벨 정의 (L0 Manual ~ L4 Full-Auto)
- [ ] FR-1.2: `.harness/config.yaml` 파일에 레벨 저장
- [ ] FR-1.3: 기본값 L2 Semi-Auto로 설정

#### FR-2: PDCA 단계 전환 제어
- [ ] FR-2.1: 각 PDCA 단계 전환 시 현재 레벨 확인
- [ ] FR-2.2: 레벨에 따른 승인/자동 진행 로직 구현
- [ ] FR-2.3: L0~L4별 구체적 동작 정의

| 레벨 | Plan→Design | Design→Implement | Implement→Check | Check→Wrapup |
|------|:-----------:|:----------------:|:---------------:|:------------:|
| L0   | 승인 필수 | 승인 필수 | 승인 필수 | 승인 필수 |
| L1   | 승인 필수 | 승인 필수 | 승인 필수 | 자동 |
| L2   | 불확실시 승인 | 자동 | 자동 | 자동 |
| L3   | 자동 | 자동 | 자동(게이트) | 자동 |
| L4   | 자동 | 자동 | 자동 | 자동 |

#### FR-3: 신뢰 점수 시스템
- [ ] FR-3.1: 6개 가중치 구성 요소 정의
  - track_record (0.25): 과거 성공률
  - quality_metrics (0.20): 코드 품질 점수
  - velocity (0.15): 작업 속도
  - user_ratings (0.20): 사용자 평가
  - decision_accuracy (0.10): 결정 정확도
  - safety (0.10): 안전 위반 없음
- [ ] FR-3.2: `.harness/trust.json`에 점수 저장
- [ ] FR-3.3: 신뢰 점수 기반 자동 레벨 조정 (autoEscalation/autoDowngrade)

#### FR-4: 훅 시스템 통합
- [ ] FR-4.1: `hooks/common.sh`에 레벨 조회 함수 추가
- [ ] FR-4.2: `hooks/on-agent-start.sh`에 승인 로직 추가
- [ ] FR-4.3: 승인 요청 시 사용자 프롬프트 표시

### 비기능 요구사항 (NFR)

- NFR-1: **성능**: 레벨 확인은 10ms 이내 수행
- NFR-2: **호환성**: 기존 훅 시스템과 충돌 없이 동작
- NFR-3: **확장성**: 향후 명령어 기반 변경 지원 가능한 구조
- NFR-4: **안전성**: L4에서도 긴급 정지(Emergency Stop) 가능

---

## 5. 제약 조건 (Constraints)

- **기술 스택**: Bash (hooks), YAML (config), JSON (trust score)
- **의존성**: `yq` (YAML 파싱) - 선택적, 없으면 기본값 사용
- **호환성**: Claude Code hooks 시스템 준수
- **기존 시스템**: `.harness/` 디렉토리 구조 유지

---

## 6. 스코프 (Scope)

### 포함 (In-Scope)
- L0-L4 자동화 레벨 정의 및 구현
- `.harness/config.yaml` 설정 파일
- 신뢰 점수 시스템 (6개 지표)
- PDCA 단계 전환 시 승인 로직
- 훅 시스템 통합

### 제외 (Out-of-Scope)
- 명령어 기반 레벨 변경 (`/harness level L3`)
- LLM-as-Judge 품질 평가
- 멀티 모델 합의 시스템
- Wave 기반 병렬 실행
- GUI 설정 인터페이스

---

## 7. 성공 기준 (Success Criteria)

1. **기능 검증**
   - [ ] 각 레벨에서 PDCA 단계 전환이 명세대로 동작
   - [ ] 신뢰 점수가 정확히 계산되어 저장됨
   - [ ] 설정 파일 변경이 즉시 반영됨

2. **사용자 경험**
   - [ ] L2 기본값으로 기존 워크플로우와 동일한 경험
   - [ ] 승인 요청 메시지가 명확하게 표시됨
   - [ ] 레벨 변경이 직관적으로 가능

3. **안정성**
   - [ ] 기존 기능에 영향 없음
   - [ ] 설정 파일 손상 시 기본값으로 폴백
   - [ ] 모든 훅 스크립트가 정상 종료

---

## 8. 의존성 (Dependencies)

### 선행 기능 (Prerequisite Features)
- [ ] 없음 (현재 harness-engineering 기본 기능 활용)

### 외부 의존성 (External Dependencies)
- **yq**: YAML 파싱 (선택적, 없으면 기본값 사용)
- **jq**: JSON 파싱 (기존 사용 중)
- **Claude Code**: hooks 시스템 지원

---

## 9. 파일 구조 예시

```
.harness/
├── config.yaml          # 자동화 설정 (신규)
├── trust.json           # 신뢰 점수 (신규)
├── logs/
│   └── decisions.jsonl  # 결정 로그 (신규)
├── state/
│   ├── pdca-phase.txt   # 현재 PDCA 단계 캐시
│   ├── current-agent.txt # 현재 에이전트 캐시
│   └── current-level.txt # 현재 적용 레벨 (신규)
├── engine/
│   └── state.json       # 현재 상태 (SSOT)
└── backups/
```

---

## 10. 다음 단계

➡️ **Design 단계**: `/design automation-levels` 로 구체적 구현 계획을 수립하세요.
