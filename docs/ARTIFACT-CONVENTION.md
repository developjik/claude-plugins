# 산출물 작성 규약 (Artifact Convention)

본 문서는 확장 PDCA 워크플로우(plan → design → implement → check → wrapup)에서 각 스킬 간 정보를 주고받기 위한 **단일 소스 오브 트루스(SSOT)** 산출물 규약을 정의합니다.

## 기본 원칙

1. **고정 경로 읽기/쓰기**: 각 스킬은 이전 단계 스킬이 생성한 문서를 "검색"하지 않고, **사전 정의된 고정 경로**에서 직접 읽습니다.
2. **템플릿 기반 생성**: 산출물은 `docs/templates/` 폴더의 마크다운 템플릿을 기반으로 생성됩니다.
3. **핵심 문서 4종**: 필수 산출물은 `clarify.md`, `plan.md`, `design.md`, `wrapup.md` 4가지로 제한하여 과도한 문서화를 방지합니다 (`check` 단계는 별도 문서를 생성하지 않고 결과만 출력 후 `wrapup`으로 인계).

---

## 디렉토리 구조 및 Slug 규칙

모든 기능 산출물은 `docs/specs/<feature-slug>/` 경로에 저장됩니다.

- **`<feature-slug>` 규칙**: `kebab-case` 영문 소문자 (예: `user-auth`, `payment-gateway`)
- **결정 주체**: 최초 시작점인 `/plan` 스킬 (또는 `/harness plan` / `/fullrun`) 실행 시 확정하며, 이후 프로세스 내내 동일한 slug를 사용합니다.

```
docs/
├── templates/                   ← 산출물 템플릿 (SSOT)
│   ├── clarify.md
│   ├── plan.md
│   ├── design.md
│   └── wrapup.md
└── specs/                       ← 실제 산출물 저장소
    └── user-auth/               ← 예: <feature-slug>
        ├── clarify.md           ← /clarify 가 생성
        ├── plan.md              ← /plan 이 생성
        ├── design.md            ← /design 이 생성
        └── wrapup.md            ← /wrapup 이 생성
```

---

## 스킬별 디렉토리/파일 책임

각 스킬은 엄격하게 자신이 담당하는 파일만 생성/수정하며, 이전 단계의 파일은 읽기 전용으로 참조합니다.

| 스킬 | 읽는 곳 (Read) | 쓰는 곳 (Write) | 다음 단계 (Next) |
|:-----|:--------------|:---------------|:---------------|
| `clarify` | `docs/templates/clarify.md` | `docs/specs/<slug>/clarify.md` | `/plan <slug>` |
| `plan` | `docs/specs/<slug>/clarify.md`<br>`docs/templates/plan.md` | `docs/specs/<slug>/plan.md` | `/design <slug>` |
| `design` | `docs/specs/<slug>/plan.md`<br>`docs/templates/design.md` | `docs/specs/<slug>/design.md` | `/implement <slug>` |
| `implement` | `docs/specs/<slug>/design.md` | (실제 코드 파일들) | `/check <slug>` |
| `check` | `docs/specs/<slug>/plan.md`<br>`docs/specs/<slug>/design.md` | (파일 생성 안 함 - 자동 Iterate 수행) | `/wrapup <slug>` |
| `wrapup` | `docs/specs/<slug>/*`<br>`docs/templates/wrapup.md` | `docs/specs/<slug>/wrapup.md`<br>(그 외 README/CHANGELOG 등) | (완료) |

---

## 파일 템플릿

자세한 문서 구조는 `docs/templates/` 디렉토리 내 파일을 따릅니다.

### 1. `plan.md` (기획/요구사항)
- **목적**: 시스템에 구현할 "무엇(What)"을 정의
- **핵심 항목**: 목표, 기능 요구사항(FR), 비기능 요구사항(NFR), 제약 조건, 스코프, 성공 기준

### 2. `design.md` (설계/작업목록)
- **목적**: 앞선 plan을 바탕으로 코드 레벨에서 "어떻게(How)" 변경할지를 정의
- **핵심 항목**: 아키텍처 개요, 파일 변경 계획(생성/수정/삭제), 기술 결정, 테스트 전략

### 3. `wrapup.md` (구현 결과 마감)
- **목적**: 구현 및 검증(check)이 끝난 후 최종 변경 사항과 테스트 결과를 기록
- **핵심 항목**: 최종 파일 변경 목록, 테스트 결과, 연관 문서 업데이트 내역
