# Harness Engineering Documentation

## Quick Links

| Document | Description |
|----------|-------------|
| [Quickstart](guides/quickstart.md) | 5분 내 설정 완료 가이드 |
| [Usage](guides/usage.md) | 상세 사용법 및 명령어 |
| [Architecture](reference/architecture.md) | 시스템 아키텍처 개요 |

---

## Guides

사용자 가이드 및 작성 가이드

- [quickstart.md](guides/quickstart.md) - 빠른 시작
- [usage.md](guides/usage.md) - 상세 사용법
- [hook-writing.md](guides/hook-writing.md) - Hook 작성 가이드
- [skill-writing.md](guides/skill-writing.md) - Skill 작성 가이드
- [agent-writing.md](guides/agent-writing.md) - Agent 작성 가이드
- [browser-controller.md](guides/browser-controller.md) - 브라우저 컨트롤러
- [multi-feature-management.md](guides/multi-feature-management.md) - 다중 기능 관리

## Reference

기술 레퍼런스 문서

- [architecture.md](reference/architecture.md) - 아키텍처 개요
- [artifact-convention.md](reference/artifact-convention.md) - 산출물 규약
- [hybrid-task-format.md](reference/hybrid-task-format.md) - 하이브리드 태스크 포맷
- [lsp-integration.md](reference/lsp-integration.md) - LSP 통합
- [wave-system.md](reference/wave-system.md) - Wave 시스템

## Analysis

분석 보고서 및 연구 문서

- [analysis-report.md](analysis/analysis-report.md) - 종합 분석 보고서
- [benchmark-analysis.md](analysis/benchmark-analysis.md) - 벤치마크 분석
- [project-analysis.md](analysis/project-analysis.md) - 프로젝트 분석
- [features.md](analysis/features.md) - 기능 레지스트리
- [agent-harness-ecosystem-analysis.md](analysis/agent-harness-ecosystem-analysis.md) - 에이전트 하네스 생태계 분석

## Specs

기능별 기획/설계 문서 (PDCA 사이클)

| Feature | Plan | Design | Wrap-up |
|---------|------|--------|---------|
| automation-levels | [plan](specs/automation-levels/plan.md) | [design](specs/automation-levels/design.md) | [wrapup](specs/automation-levels/wrapup.md) |
| fresh-context | [plan](specs/fresh-context/plan.md) | [design](specs/fresh-context/design.md) | [wrapup](specs/fresh-context/wrapup.md) |
| p0-foundation | [plan](specs/p0-foundation/plan.md) | - | - |
| p1-enhancement | [plan](specs/p1-enhancement/plan.md) | - | - |

## Decisions

Architecture Decision Records (ADR)

- [001-modular-hook-architecture.md](decisions/001-modular-hook-architecture.md)
- [002-security-hardening.md](decisions/002-security-hardening.md)
- [003-automation-levels.md](decisions/003-automation-levels.md)

## Templates

재사용 가능한 템플릿

- [plan.md](templates/plan.md) - 기획 템플릿
- [design.md](templates/design.md) - 설계 템플릿
- [wrapup.md](templates/wrapup.md) - 마무리 템플릿
- [clarify.md](templates/clarify.md) - 명확화 템플릿
- [automation-config.md](templates/automation-config.md) - 자동화 설정 템플릿
- [context/](templates/context/) - 컨텍스트 템플릿

## Schemas

- [task.xsd](schemas/task.xsd) - Task XML 스키마
