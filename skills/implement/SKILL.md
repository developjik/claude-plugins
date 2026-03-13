---
name: implement
description: Design 문서를 기반으로 RED-GREEN-REFACTOR TDD 사이클로 코드를 구현합니다.
user-invocable: true
argument-hint: <기능명 또는 Design 문서 경로>
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Implement Skill — PDCA 3단계 (Do)

Design 문서를 기반으로 **TDD 사이클**로 코드를 구현합니다.

## 프로세스

### 1. Design 문서 로드
$ARGUMENTS 에서 대상 기능의 Design 문서를 찾아 구현 순서를 확인합니다.

### 2. 기능별 RED-GREEN-REFACTOR 반복

**각 기능마다:**

#### RED — 실패하는 테스트 작성
- 기대 동작을 테스트로 명세
- 테스트 이름: `should [동작] when [조건]`
- AAA 패턴: Arrange → Act → Assert

#### GREEN — 최소 코드로 통과
- 테스트를 통과시키는 최소한의 코드 작성
- 완벽함보다 동작이 목표

#### REFACTOR — 개선
- 중복 제거, 책임 분리
- 테스트 여전히 통과 확인

### 3. 커밋
각 기능 완료 시 atomic commit:
```
<type>(<scope>): <subject>
```

## 코드 품질 기준
- 함수 20줄 이하
- 순환 복잡도 10 이하
- 모든 에러 경로 처리
- 명확한 네이밍

## 출력

```
📊 구현 진행률: [X/Y] (Z%)

✅ 완료: [작업 목록]
🔄 현재: [진행 중]
⏭️ 다음: [예정]

➡️ 다음 단계: /check 로 코드 검증을 시작하세요.
```
