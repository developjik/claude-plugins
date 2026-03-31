---
name: debug
description: |
  Systematic 4-step debugging: reproduce, isolate, root cause, fix. Evidence-based, no guessing.
  Triggers on: 'debug', 'bug', 'error', 'fix', 'broken', 'not working', 'crash', 'exception',
  '디버그', '버그', '에러', '수정', '고치기', '안됨', '오류', '문제',
  Error: 'TypeError', 'ReferenceError', 'SyntaxError', 'undefined', 'null pointer', 'failed'
user-invocable: true
argument-hint: <버그 설명 또는 에러 메시지>
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Debug Skill

체계적 프로세스로 버그를 추적하고 해결합니다. **추측이 아닌 증거 기반** 디버깅입니다.

## 프로세스

### 1단계: 재현 (Reproduce)

$ARGUMENTS 에서 버그 정보를 파악하고 재현합니다:

- 에러 메시지 분석
- 관련 코드 탐색
- 최소 재현 조건 찾기
- 재현 테스트 케이스 작성

### 2단계: 고립 (Isolate)

- 이분법(bisect)으로 문제 범위 축소
- 로그/디버그 출력으로 실행 경로 추적
- 관련 없는 코드 배제

### 3단계: 근본 원인 (Root Cause)

- "5 Whys" 기법: 왜? → 왜? → 왜? → 왜? → 왜?
- 증상과 원인 구분
- 같은 원인이 다른 곳에도 있는지 확인

### 4단계: 수정 (Fix)

- 최소한의 변경으로 수정
- **회귀 테스트 필수** — 이 버그가 다시 발생하면 잡혀야 함
- 방어적 코딩 추가

## 출력

```
🐛 디버그 보고서

증상: [관찰된 문제]
재현: [재현 조건]
근본 원인: [원인]
수정: [적용한 변경]
회귀 테스트: [추가한 테스트]
예방: [향후 방지책]
```
