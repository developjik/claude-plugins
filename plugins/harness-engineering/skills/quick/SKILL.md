---
name: quick
description: 5분 안에 첫 기능 완성 경험 (빠른 PDCA 진입)
version: 1.0.0
user-invocable: true
---

# Quick Start - Fast Path to First Feature

빠른 PDCA 워크플로우 진입점. 초보자가 5분 안에 첫 기능을 완성 경험을## 🎯 목적

1. **진입 장베 lowered**: `/quick` 커맨드로 초보자가 5분 안에 첫 기능 완성 경험
2. **TDD 시작**: `/implement` 단계에서 자동으로 TDD 사이클로 진입
3. **복구 가능**: 실패 시 자동 감지 및 적절한 복구 메커니즘 제공

## 📥 사용법

```bash
# 빠른 기능 완성 (clarify → plan → design 압축)
/quick "<기능 설명> [--auto-continue]

# 옵션: 전체 PDCA 사이클로 진입
/quick "<기능 설명> --full
```

## 🔄 실행 흐름

```
┌──> Clarify (요청 구체화)
    ↓
┌──> Plan (요구사항 정의)
    ↓
┌──> Design (기술 설계)
    ↓
    │─ [자동 분기점]
    │   ├── [빠른 경로: clarify → plan → design → implement
    │   └── [전체 경로: clarify → plan → design → implement → check → wrapup
    ↓
└──> Implement (TDD 구현)
    ↓
    │─ [실패 시 복구 메커니즘 작동]
    ↓
└──> 사용자에게 결과 반환
```

## 📋 전제 조건

- `jq` 명령어 필요
- Git 저장소여 함

## 📝 프롬프트 템플릿릿

```json
{
  "name": "quick",
  "description": "5분 안에 첫 기능 완성 - 빠른 PDCA 진입",
  "version": "1.0.0",
  "trigger": {
    "type": "slash_command",
    "command": "/quick"
  },
  "requires": [],
  "phases": ["clarify", "plan", "design"]
}
```

## 🎯 Step 1: Clarify (요청 구체화)

소크라테스식 질문으로 사용자의 요청을 구체화합니다.

**질문 예시:**
1. 이 기능의 핵심 목적은 무엇인가요?
2. 누가 사용하나나 이 기능을 사용하는가?
3. 어떤 문제를 해결하고 싶은가요?
4. 성공한다면 어떻게 보일 것인가?
5. 기술적 제약사항이 있나요?

**출력:**
- `docs/specs/<feature-slug>/clarify.md` 파일 생성

## 📐 Step 2: Plan (요구사항 정의)
clarify.md를 기반으로 구체적인 요구사항을 정의합니다.

**출력:**
- `docs/specs/<feature-slug>/plan.md` 파일 생성

## 🏗️ Step 3: Design (기술 설계)
plan.md를 기반으로 기술 설계를 작성합니다.

**출력:**
- `docs/specs/<feature-slug>/design.md` 파일 생성

## 🚦 Step 4: 자동 분기점
사용자가 `--auto-continue` 또는 `--full` 플래그를 사용한 경우:
- `/implement`로 자동 진입
- 이후 `/check` → `/wrapup`까지 자동 진행

## 🔧 Step 5: 실패 시 복구
실패 시 자동으로 `/recover` 커맨드를 제안합니다.

---

## 📚 관련 스킬

- `/clarify` - 요청 구체화
- `/plan` - 요구사항 정의
- `/design` - 기술 설계
- `/implement` - TDD 구현
- `/check` - 검증
- `/wrapup` - 문서화
- `/recover` - 복구

---

## 💡 예시

```
/quick 로그인 기능 추가
/quick 대시보드드 기능 --full
```

---

## ⚠️ 주의

- `/quick`은 **초보자용 위한 기능**에만 사용하세요
- 복잡한 기능은 `/fullrun`을 사용하세요
- 자동 진행은 `--auto-continue` 또는 `--full` 플래그 필요
