# Harness Engineering

확장 PDCA(Plan→Design→Do→Check→Wrap-up) 기반 AI 소프트웨어 개발 자동화 Claude Code 플러그인.

6개 전문 에이전트(인지 모드)와 13개 실행 스킬로 체계적인 개발 워크플로우를 제공합니다.

## 🎯 누구를 위한 것인가?

| 타겟 | 설명 |
|:-----|:-----|
| **Primary** | **1인 창업자 / 인디 개발자** — 혼자서도 20인 팀처럼 체계적으로 개발하고 싶은 분 |
| **Secondary** | **AI 코딩 도구 입문자** — Claude Code를 더 효과적으로 활용하고 싶은 분 |
| **Tertiary** | **체계적 워크플로우를 원하는 팀** — AI와 함께 일관된 개발 프로세스를 구축하려는 팀 |

### 이런 경험 있으신가요?

> 😤 "AI가 작성한 코드가 요구사항과 다르다"

AI가 멋대로 해석해서 엉뚱한 코드를 만드는 경험, 있으시죠?

> 😵 "긴 세션에서 AI가 앞서 논의한 내용을 잊는다"

처음에 합의한 내용을 나중에는 기억 못 하는 '컨텍스트 로트' 현상.

> 😰 "테스트 없이 코드만 생성된다"

작동은 하는데 테스트가 없어서 나중에 수정할 때 불안한 코드.

> 🤔 "어떤 단계까지 진행했는지 모르겠다"

지금 설계 단계인지 구현 단계인지, 뭘 해야 하는지 헷갈릴 때.

### Harness Engineering은 이렇게 해결합니다

| 문제 | 해결책 |
|:-----|:-------|
| 🔀 **요구사항 이탈** | Plan/Design 문서가 SSOT로 작동 → AI가 스펙을 벗어나지 않음 |
| 🧠 **컨텍스트 로트** | Context Rot 감지 시 서브에이전트 권장 → 긴 세션에서도 품질 유지 |
| 🧪 **테스트 부재** | TDD 내장 → 테스트 없는 코드는 거부됨 |
| 📍 **진행 상황 불투명** | 상태 머신으로 추적 → 언제든 현재 위치 확인 가능 |

## 한눈에 보기

- **6개 에이전트**: `strategist`, `architect`, `engineer`, `guardian`, `librarian`, `debugger`
- **13개 스킬**: `clarify`, `plan`, `design`, `implement`, `check`, `wrapup`, `harness`, `debug`, `fullrun`, `quick`, `grill-me`, `delegate`, `recover`
- **훅 자동화**: 위험 명령 차단, 파일 백업, 변경 추적, PDCA 단계 자동 추적
- **P0 Foundation**: 다중 프레임워크 테스트 실행, 서브에이전트 스포닝, 상태 머신 엔진
- **P1 Enhancement**: 2단계 리뷰, 스킬 평가, 크래시 복구, 브라우저 테스트
- **P2 Advanced**: 해시 앵커 에디트(충돌 방지), 웨이브 실행(병렬 처리)
- **런타임 저장소**: 실행 프로젝트의 `.harness/` 사용, Git 저장소라면 `.git/info/exclude`에 자동 등록
- **PDCA 5단계**: Check에서 불일치 시 자동 Iterate (최대 10회)

## 설치

```bash
# Claude Code 마켓플레이스에서 설치
/plugin install harness-engineering

# 또는 로컬에서 테스트
claude --plugin-dir ./harness-engineering
```

## 사용법

### 확장 PDCA 워크플로우

```
/clarify <기능 설명>        # 0. 요청 구체화 + docs/specs/<slug>/clarify.md 생성
/plan <feature-slug>          # 1. clarify.md 기반 요구사항 정의 + plan.md 생성
/design <feature-slug>        # 2. plan.md 기반 기술 설계
/implement <feature-slug>     # 3. design.md 기반 TDD 구현
/check <feature-slug>         # 4. 2단계 리뷰 + 테스트 실행 + 자동 반복
/wrapup <feature-slug>        # 5. wrapup.md 생성 + 문서화
```

### 통합 커맨드

```
/harness plan <설명>            # feature-slug 추출 + Plan 산출물 생성
/harness design <feature-slug>
/harness do <feature-slug>
/harness check <feature-slug>
/harness wrapup <feature-slug>
/harness status                 # 현재 PDCA 상태
```

### 전체 자동 실행

```
/fullrun <기능 설명>     # Clarify→Plan→Design→Do→Check→Wrap-up 한번에
```

### 유틸리티

```
/debug <버그 설명>       # 체계적 4단계 디버깅
/delegate <태스크>       # 서브에이전트로 작업 위임
/recover [--rollback]    # 크래시 복구 및 포렌식 분석
```

### Feature Slug 규칙

- `/clarify`, `/plan` 또는 `/fullrun` 이 최초 실행 시 `kebab-case` slug를 확정합니다. 예: `user-auth`
- 이후 모든 단계는 같은 slug를 사용합니다. 예: `/design user-auth`
- 단계 산출물은 `docs/specs/<feature-slug>/` 아래에 저장됩니다.

## 핵심 기능

### P0 Foundation

#### 다중 프레임워크 테스트 실행 (P0-1)

자동으로 프로젝트의 테스트 프레임워크를 감지하고 실행합니다:

| 언어 | 지원 프레임워크 |
|------|-----------------|
| JavaScript/TypeScript | Jest, Vitest, Mocha |
| Python | pytest, unittest |
| Go | go test |
| Rust | cargo test |
| Java | Maven, Gradle |

```bash
# 자동 감지 및 실행
run_tests "$PROJECT_ROOT"

# 특정 필터로 실행
run_tests "$PROJECT_ROOT" "auth"
```

#### 검증 클래스 시스템

| 클래스 | 내용 | 시간 | 실행 조건 |
|--------|------|------|----------|
| **A** | 정적 분석 (린트, 타입체크) | <30초 | 항상 |
| **B** | 유닛 테스트 | <1분 | 항상 |
| **C** | 통합 테스트 | <5분 | `--thorough` |
| **D** | E2E 테스트 | <15분 | `--thorough` |

```bash
# Class A+B 실행 (기본)
run_verification "$PROJECT_ROOT" "ab"

# 전체 검증
run_verification "$PROJECT_ROOT" "abcd" "--thorough"
```

#### 서브에이전트 스포닝 (P0-2)

독립적인 서브에이전트를 스폰하여 작업을 병렬 처리합니다:

```bash
# 서브에이전트 스폰
spawn_subagent "$task_file" "$project_root" "sonnet" "code_review"

# 웨이브 실행 (병렬)
execute_wave "$project_root" "$tasks_json"
```

#### 상태 머신 엔진 (P0-3)

PDCA 워크플로우의 상태를 관리하고 추적합니다:

```bash
# 상태 초기화
init_state_machine "$PROJECT_ROOT" "$FEATURE_SLUG"

# 상태 전환
transition_state "$PROJECT_ROOT" "plan" "design_complete"

# 스냅샷 생성
create_snapshot "$PROJECT_ROOT" "implement"

# 롤백
rollback_to_snapshot "$PROJECT_ROOT" "$SNAPSHOT_ID"
```

### P1 Enhancement

#### 2단계 리뷰 시스템 (P1-1)

superpowers의 "two-stage review" 패턴을 구현합니다:

- **Stage 1**: 스펙 준수 검증 (파일, API, 요구사항)
- **Stage 2**: 코드 품질 리뷰 (독립 서브에이전트)

```bash
# 2단계 리뷰 실행
run_two_stage_review "$PROJECT_ROOT" "$FEATURE_SLUG"

# 결과: 스펙 60% + 품질 40% = 종합 점수
# 90% 이상 시 PASS
```

#### 스킬 평가 프레임워크 (P1-2)

각 스킬의 실행 품질을 추적하고 분석합니다:

```bash
# 스킬 실행 기록
record_skill_execution "$PROJECT_ROOT" "clarify" "success" "1500"

# 통계 조회
get_skill_statistics "$PROJECT_ROOT" "implement"

# 대시보드 생성
generate_skill_dashboard "$PROJECT_ROOT"
```

#### 크래시 복구 & 포렌식 (P1-3)

Stuck 상태를 감지하고 복구 옵션을 제공합니다:

```bash
# Stuck 감지
detect_stuck_state "$PROJECT_ROOT"

# 크래시 분석
analyze_crash "$PROJECT_ROOT"

# 포렌식 리포트 생성
generate_forensics_report "$PROJECT_ROOT"

# 복구 실행
recover_state "$PROJECT_ROOT" "rollback" "$SNAPSHOT_ID"
```

#### 브라우저 테스트 통합 (P1-4)

Playwright/Cypress 기반 E2E 테스트를 자동화합니다:

```bash
# Playwright 설정
setup_playwright "$PROJECT_ROOT"

# 브라우저 테스트 실행
run_browser_tests "$PROJECT_ROOT" --browser=chromium

# HTML 리포트 생성
generate_html_report "$PROJECT_ROOT"
```

### P2 Advanced

#### 해시 앵커 에디트 (P2-1)

파일 수정 시 해시 기반 충돌 방지를 제공합니다:

```bash
# 파일 등록
register_file_hash "$PROJECT_ROOT" "src/app.js"

# 무결성 검증
verify_file_integrity "$PROJECT_ROOT" "src/app.js"

# 편집 준비 (충돌 감지)
prepare_edit "$PROJECT_ROOT" "src/app.js" "Add feature X"

# 편집 완료
finalize_edit "$PROJECT_ROOT" "$TXN_ID" "src/app.js"
```

#### 웨이브 실행 (P2-2)

의존성 기반 병렬 태스크 실행을 지원합니다:

```bash
# 태스크 정렬 (위상 정렬)
topological_sort '[{"id":"A"},{"id":"B","dependencies":["A"]}]'
# → ["A", "B"]

# 웨이브 그룹화
group_tasks_into_waves '[...]'
# → [["A","B"], ["C"], ["D"]]

# 순환 의존성 감지
detect_circular_dependencies '[...]'
# → {"has_cycle": false}
```

## 에이전트 (인지 모드)

| 에이전트 | 역할 | 도구 |
|:---------|:-----|:-----|
| `strategist` | CEO/PM. 제품 방향성, 사용자 가치 | 읽기 전용 |
| `architect` | 기술 리드. 아키텍처, 다이어그램 | 읽기 전용 |
| `engineer` | TDD 구현 전문가 | 전체 |
| `guardian` | 보안/품질 감사관 | 읽기 전용 |
| `librarian` | 문서화 전문가 | 읽기+쓰기 |
| `debugger` | 디버깅 전문가 | 전체 |

## 저장소 구조

```
harness-engineering/
├── .claude-plugin/plugin.json     # 플러그인 매니페스트
├── agents/                         # 에이전트 (6개)
├── skills/                         # 스킬 (13개)
│   ├── clarify/SKILL.md
│   ├── plan/SKILL.md
│   ├── design/SKILL.md
│   ├── implement/SKILL.md
│   ├── check/SKILL.md
│   ├── wrapup/SKILL.md
│   ├── harness/SKILL.md
│   ├── debug/SKILL.md
│   ├── fullrun/SKILL.md
│   ├── quick/SKILL.md
│   ├── grill-me/SKILL.md
│   ├── delegate/SKILL.md          # NEW: 태스크 위임
│   └── recover/SKILL.md           # NEW: 상태 복구
├── hooks/                          # 훅 시스템
│   ├── hooks.json                  # 훅 설정
│   ├── common.sh                   # 공통 함수
│   ├── lib/                        # 라이브러리 모듈
│   │   ├── json-utils.sh
│   │   ├── logging.sh
│   │   ├── validation.sh
│   │   ├── test-runner.sh          # P0-1: 테스트 실행
│   │   ├── verification-classes.sh # P0-1: 검증 클래스
│   │   ├── subagent-spawner.sh     # P0-2: 서브에이전트
│   │   ├── state-machine.sh        # P0-3: 상태 머신
│   │   ├── review-engine.sh        # P1-1: 2단계 리뷰
│   │   ├── skill-evaluation.sh     # P1-2: 스킬 평가
│   │   ├── crash-recovery.sh       # P1-3: 크래시 복구
│   │   ├── browser-testing.sh      # P1-4: 브라우저 테스트
│   │   ├── hash-anchored-edit.sh   # P2-1: 해시 앵커 에디트
│   │   └── wave-executor.sh        # P2-2: 웨이브 실행
│   └── __tests__/                  # 훅 테스트 (190+ tests)
├── scripts/                        # 검증 스크립트
├── docs/                           # 문서
│   ├── ARCHITECTURE.md
│   ├── QUICKSTART.md
│   ├── templates/
│   └── specs/                      # feature 산출물
└── README.md
```

## 검증

```bash
# 전체 검증
bash scripts/validate.sh

# 개별 검증
claude plugin validate .
bash -n hooks/*.sh

# 라이브러리 테스트
./hooks/__tests__/test-runner.test.sh
./hooks/__tests__/subagent.test.sh
./hooks/__tests__/state-machine.test.sh
./hooks/__tests__/review-engine.test.sh
./hooks/__tests__/skill-evaluation.test.sh
./hooks/__tests__/crash-recovery.test.sh
./hooks/__tests__/browser-testing.test.sh
```

## 자동화 레벨 (L0-L4)

PDCA 워크플로우의 자동화 정도를 5단계로 조절할 수 있습니다.

| 레벨 | 이름 | 설명 | 추천 대상 |
|:----:|:-----|:-----|:----------|
| L0 | Manual | 모든 전환에 승인 필요 | 초보자, 중요 프로젝트 |
| L1 | Guided | 중요 전환만 승인 | 학습 단계 |
| L2 | Semi-Auto | 불확실할 때만 승인 (기본값) | 일반 사용자 |
| L3 | Auto | 품질 게이트만 통과하면 자동 | 숙련자 |
| L4 | Full-Auto | 완전 자동 | 매우 숙련된 사용자 |

### 설정 방법

```bash
# .harness/config.yaml 편집
automation:
  level: L2  # L0, L1, L2, L3, L4
```

## Context Rot 방지 (Fresh Context)

긴 세션에서 발생하는 컨텍스트 품질 저하(Context Rot)를 감지하고 관리합니다.

### 점수 계산

```
score = (토큰비율 × 0.4) + (작업비율 × 0.3) + (시간비율 × 0.3)

등급:
  < 0.5: healthy (건강)
  0.5-0.7: caution (주의)
  >= 0.7: rot (서브에이전트 권장)
```

### 상태 확인

```bash
# Context Rot 점수 조회
cat .harness/state/context-rot-score

# 이벤트 로그 확인
cat .harness/logs/context-rot.jsonl
```

## 문서

- [아키텍처](docs/ARCHITECTURE.md) — PDCA 흐름, 에이전트-스킬 관계, 훅 라이프사이클
- [프로젝트 분석](docs/PROJECT-ANALYSIS.md) — 시스템 구조 ASCII 다이어그램
- [빠른 시작](docs/QUICKSTART.md) — 5분 만에 시작하기
- [산출물 규약](docs/ARTIFACT-CONVENTION.md) — `docs/specs/<feature-slug>/` 기반 SSOT 규칙
- [스킬 작성 가이드](docs/SKILL-WRITING-GUIDE.md) — 커스텀 스킬 만들기
- [에이전트 작성 가이드](docs/AGENT-WRITING-GUIDE.md) — 커스텀 에이전트 만들기
- [훅 작성 가이드](docs/HOOK-WRITING-GUIDE.md) — 커스텀 훅 만들기

## 영감을 받은 프로젝트

이 프로젝트는 다음 오픈소스 프로젝트들을 분석하고 참조하여 개발되었습니다:

- [superpowers](https://github.com/obra/superpowers) — 자동 스킬 트리거, TDD 중심 개발 워크플로우, 2단계 리뷰
- [bkit-claude-code](https://github.com/popup-studio-ai/bkit-claude-code) — PDCA 사이클, Context Engineering 패턴
- [gstack](https://github.com/garrytan/gstack) — 역할 기반 모드 전환, 멀티 에이전트 구조
- [get-shit-done](https://github.com/gsd-build/get-shit-done) — spec-driven 상태 파일 시스템
- [gsd-2](https://github.com/gsd-build/gsd-2) — 차세대 GSD 아키텍처, 검증 클래스 시스템
- [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent) — 오픈 에이전트 프레임워크

## 라이선스

MIT License
