---
name: fullrun
description: |
  Execute complete PDCA cycle automatically: Clarify→Plan→Design→Do→Check→Wrap-up in one command.
  Triggers on: 'fullrun', 'all at once', 'complete cycle', 'end to end', 'automate all',
  '전체 실행', '한번에', '자동화', '처음부터 끝까지',
  Error: 'run everything', 'do it all', 'complete feature', 'full pipeline'
user-invocable: true
argument-hint: <기능 또는 프로젝트 설명>
allowed-tools: Read, Write, Edit, Bash, Grep, Glob, AskUserQuestion
---

# Fullrun Skill — 전체 PDCA 자동 실행

Clarify부터 Wrap-up까지 **전체 PDCA 사이클**을 순차적으로 자동 실행합니다.

## 실행 순서

$ARGUMENTS 를 기반으로 아래 6단계를 순차 실행합니다:
각 단계 시작 전 `.harness/engine/state.json`과 `.harness/state/current-feature.txt`의 feature context가 동일한지 확인합니다.

### 0. Clarify (NEW!)
- 사용자 요청 분석 및 구체화
- 소크라테스식 질문으로 모호성 해소
- 대안 탐색 및 Gray Areas 식별
- `docs/specs/<feature-slug>/clarify.md` 생성

### 1. Plan
- clarify.md 기반 요구사항 분석
- 목표·제약·스코프 정의
- `docs/specs/<feature-slug>/plan.md` 생성

### 2. Design
- Plan 기반 코드 변경 계획 수립
- 파일 단위 생성/수정/삭제 목록 작성
- `docs/specs/<feature-slug>/design.md` 생성

### 3. Do (Implement)
- Design 문서 리딩 및 TDD 기반 구현
- RED-GREEN-REFACTOR 사이클
- 기능별 atomic commit

### 4. Check + Iterate
- 코드 리뷰 + 계획 일치 검증
- 불일치 시 자동 반복 수정 (최대 10회)
- 90% 이상 일치 시 통과

### 5. Wrap-up
- 변경 로그 작성 및 문서 업데이트
- `docs/specs/<feature-slug>/wrapup.md` 생성

## 실행 조건

- 각 단계가 성공해야 다음 단계로 진행합니다
- Clarify 단계에서 모호성이 높으면(7점 이상) 사용자 확인 후 진행
- 단계 실패 시 사용자에게 보고하고 중단합니다
- Check에서 10회 Iterate 후에도 미충족이면 중단합니다

## 출력

```
🚀 Fullrun 완료

📊 PDCA 실행 결과:
✅ 0. Clarify — 요청 구체화 완료 (모호성: X→Y)
✅ 1. Plan — 요구사항 정의 완료
✅ 2. Design — 변경 계획 수립 완료
✅ 3. Do — TDD 구현 완료 (X개 커밋)
✅ 4. Check — 일치도 Y% (Iterate N회)
✅ 5. Wrap-up — 문서화 완료

📋 요약:
- 파일 변경: +A -B ~C
- 테스트: 전체 통과
- 문서: 업데이트됨

📄 산출물:
- docs/specs/<feature-slug>/clarify.md
- docs/specs/<feature-slug>/plan.md
- docs/specs/<feature-slug>/design.md
- docs/specs/<feature-slug>/wrapup.md
```

## 주의사항

- 대규모 프로젝트보다는 **단일 기능 구현**에 적합합니다
- 중간에 사용자 의사결정이 필요한 경우 멈추고 질문합니다
- Clarify 단계에서 깊은 구체화가 필요하면 개별 `/clarify` 실행 권장
- 단계별 세밀한 제어가 필요하면 개별 스킬을 사용하세요
