---
name: fullrun
description: Plan→Design→Do→Check→Wrap-up 전체 PDCA 사이클을 한 번에 자동 실행합니다.
user-invocable: true
argument-hint: <기능 또는 프로젝트 설명>
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Fullrun Skill — 전체 PDCA 자동 실행

Plan부터 Wrap-up까지 **전체 PDCA 사이클**을 순차적으로 자동 실행합니다.

## 실행 순서

$ARGUMENTS 를 기반으로 아래 5단계를 순차 실행합니다:

### 1. Plan
- 요구사항 분석, 목표·제약 정의
- 사용자에게 핵심 질문 후 요구사항 문서 생성

### 2. Design
- Plan 기반 코드 변경 계획 수립
- 파일 단위 생성/수정/삭제 목록 작성
- 아키텍처 다이어그램 생성

### 3. Do (Implement)
- Design 기반 TDD 구현
- RED-GREEN-REFACTOR 사이클
- 기능별 atomic commit

### 4. Check + Iterate
- 코드 리뷰 + 계획 일치 검증
- 불일치 시 자동 반복 수정 (최대 10회)
- 90% 이상 일치 시 통과

### 5. Wrap-up
- 변경 로그 작성
- 문서 업데이트
- 코드 정리

## 실행 조건

- 각 단계가 성공해야 다음 단계로 진행합니다
- 단계 실패 시 사용자에게 보고하고 중단합니다
- Check에서 10회 Iterate 후에도 미충족이면 중단합니다

## 출력

```
🚀 Fullrun 완료

📊 PDCA 실행 결과:
✅ 1. Plan — 요구사항 정의 완료
✅ 2. Design — 변경 계획 수립 완료
✅ 3. Do — TDD 구현 완료 (X개 커밋)
✅ 4. Check — 일치도 Y% (Iterate N회)
✅ 5. Wrap-up — 문서화 완료

📋 요약:
- 파일 변경: +A -B ~C
- 테스트: 전체 통과
- 문서: 업데이트됨
```

## 주의사항

- 대규모 프로젝트보다는 **단일 기능 구현**에 적합합니다
- 중간에 사용자 의사결정이 필요한 경우 멈추고 질문합니다
- 단계별 세밀한 제어가 필요하면 개별 스킬을 사용하세요
