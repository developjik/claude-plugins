# Context Rot 방지 가이드

## 개요

Context Rot은 긴 세션에서 Claude의 응답 품질이 저하되는 현상입니다. 이 가이드는 Context Rot을 감지하고 관리하는 방법을 설명합니다.

## Context Rot 점수

```
score = (토큰비율 × 0.4) + (작업비율 × 0.3) + (시간비율 × 0.3)
```

### 구성 요소

| 지표 | 가중치 | 계산 방식 |
|:-----|:------:|:----------|
| 토큰 사용량 | 40% | `도구호출 × 500 / 200000` |
| 작업 누적 | 30% | `도구호출 / 50` |
| 세션 시간 | 30% | `경과분 / 60` |

### 등급

| 점수 | 등급 | 상태 | 권장 행동 |
|:----:|:----:|:-----|:----------|
| < 0.5 | 🟢 healthy | 건강함 | 계속 진행 |
| 0.5-0.7 | 🟡 caution | 주의 | 모니터링 |
| >= 0.7 | 🔴 rot | 품질 저하 | 서브에이전트 사용 |

## 서브에이전트 사용

Context Rot 점수가 0.7 이상이면 서브에이전트 사용을 권장합니다:

```bash
# Context Rot 상태 확인
cat .harness/state/context-rot-score

# 서브에이전트 사용 권장 여부
should_use_subagent "/path/to/project"
```

## 컨텍스트 전달

서브에이전트 호출 시 다음 파일들이 컨텍스트로 전달됩니다:

1. **PROJECT.md**: 프로젝트 개요
2. **STATE.md**: 현재 작업 상태

### 템플릿 위치

```
docs/templates/context/
├── PROJECT.md    # 프로젝트 컨텍스트 템플릿
└── STATE.md      # 현재 상태 템플릿
```

### 설정 방법

```bash
# 프로젝트 루트에 컨텍스트 디렉토리 생성
mkdir -p .harness/context

# 템플릿 복사 및 수정
cp docs/templates/context/PROJECT.md .harness/context/
cp docs/templates/context/STATE.md .harness/context/

# 프로젝트에 맞게 수정
# PROJECT.md: 기술 스택, 컨벤션 등
# STATE.md: 현재 작업 상태
```

## 로그 확인

```bash
# Context Rot 이벤트 로그
cat .harness/logs/context-rot.jsonl

# 세션 로그에서 Context Rot 확인
grep "CONTEXT_ROT" .harness/logs/session.log
```

## 모범 사례

1. **정기적 상태 업데이트**: STATE.md를 주기적으로 갱신
2. **서브에이전트 적극 활용**: 큰 작업은 서브에이전트에 위임
3. **컨텍스트 파일 유지**: PROJECT.md를 최신 상태로 유지
4. **로그 모니터링**: caution 단계에서 주의 깊게 관찰
