---
name: harness
description: 확장 PDCA 워크플로우 오케스트레이터. /harness plan, /harness design, /harness do, /harness check, /harness wrapup 으로 단계별 진행합니다.
user-invocable: true
argument-hint: <plan|design|do|check|wrapup|status> [기능명]
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
---

# Harness Skill — PDCA 오케스트레이터

확장 PDCA 워크플로우의 **통합 진입점**입니다.

## 사용법

```
/harness plan <기능 설명>      → Plan 단계 실행
/harness design <기능명>       → Design 단계 실행
/harness do <기능명>           → Implement(Do) 단계 실행
/harness check <기능명>        → Check + auto-Iterate 실행
/harness wrapup <기능명>       → Wrap-up 단계 실행
/harness status                → 현재 PDCA 상태 확인
```

## PDCA 흐름

```
Plan → Design → Do → Check(+Iterate) → Wrap-up
```

### $ARGUMENTS 파싱

첫 번째 인자를 액션으로 파싱합니다:

**plan**: `/plan` 스킬을 호출합니다.
- 요구사항 분석, 목표 정의
- 코드 작성 없음

**design**: `/design` 스킬을 호출합니다.
- Plan 기반 코드 변경 계획 수립
- 파일 단위 생성/수정/삭제 목록

**do**: `/implement` 스킬을 호출합니다.
- RED-GREEN-REFACTOR TDD 구현

**check**: `/check` 스킬을 호출합니다.
- 코드 리뷰 + 계획 일치 검증
- 불일치 시 자동 Iterate (최대 10회)

**wrapup**: `/wrapup` 스킬을 호출합니다.
- 정리, 문서화, 변경 로그

**status**: 현재 PDCA 진행 상태를 표시합니다.

## 주의사항

- 각 단계는 개별 스킬로도 직접 호출 가능합니다
  (`/plan`, `/design`, `/implement`, `/check`, `/wrapup`)
- 단계를 건너뛰지 마세요 — 각 단계의 출력이 다음 단계의 입력입니다
- 전체 자동 실행이 필요하면 `/fullrun` 을 사용하세요
