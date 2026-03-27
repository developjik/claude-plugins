# Harness Engineering

확장 PDCA(Plan→Design→Do→Check→Wrap-up) 기반 AI 소프트웨어 개발 자동화 Claude Code 플러그인.

6개 전문 에이전트(인지 모드)와 10개 실행 스킬로 체계적인 개발 워크플로우를 제공합니다.

## 한눈에 보기

- **6개 에이전트**: `strategist`, `architect`, `engineer`, `guardian`, `librarian`, `debugger`
- **10개 스킬**: `clarify`, `plan`, `design`, `implement`, `check`, `wrapup`, `harness`, `debug`, `fullrun`, `grill-me`
- **훅 자동화**: 위험 명령 차단, 파일 백업, 변경 추적, PDCA 단계 자동 추적
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
/check <feature-slug>         # 4. 계획 대비 리뷰 + 검증 + 자동 반복
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
```

### Feature Slug 규칙

- `/clarify`, `/plan` 또는 `/fullrun` 이 최초 실행 시 `kebab-case` slug를 확정합니다. 예: `user-auth`
- 이후 모든 단계는 같은 slug를 사용합니다. 예: `/design user-auth`
- 단계 산출물은 `docs/specs/<feature-slug>/` 아래에 저장됩니다.

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
│   ├── strategist.md
│   ├── architect.md
│   ├── engineer.md
│   ├── guardian.md
│   ├── librarian.md
│   └── debugger.md
├── skills/                         # 스킬 (10개)
│   ├── clarify/SKILL.md
│   ├── plan/SKILL.md
│   ├── design/SKILL.md
│   ├── implement/SKILL.md
│   ├── check/SKILL.md
│   ├── wrapup/SKILL.md
│   ├── harness/SKILL.md
│   ├── debug/SKILL.md
│   ├── fullrun/SKILL.md
│   └── grill-me/SKILL.md
├── hooks/                          # 훅 시스템
│   ├── hooks.json                  # 훅 설정 (이벤트 라우팅)
│   ├── common.sh                   # 공통 함수
│   ├── session-start.sh            # 세션 시작
│   ├── session-end.sh              # 세션 종료
│   ├── pre-tool.sh                 # 도구 실행 전
│   ├── post-tool.sh                # 도구 실행 후
│   ├── on-agent-start.sh           # 에이전트 시작
│   ├── on-agent-stop.sh            # 에이전트 종료
│   ├── lib/                        # 라이브러리 모듈
│   └── __tests__/                  # 훅 테스트
├── scripts/                        # 검증 스크립트
│   └── validate.sh
├── docs/                           # 문서
│   ├── ARCHITECTURE.md
│   ├── ARTIFACT-CONVENTION.md
│   ├── SKILL-WRITING-GUIDE.md
│   ├── AGENT-WRITING-GUIDE.md
│   ├── HOOK-WRITING-GUIDE.md
│   ├── templates/
│   │   ├── clarify.md
│   │   ├── plan.md
│   │   ├── design.md
│   │   ├── wrapup.md
│   │   ├── automation-config.md
│   │   └── context/                # 컨텍스트 템플릿
│   ├── specs/                      # 실행 시 생성되는 feature 산출물 저장소
│   ├── QUICKSTART.md               # 빠른 시작 가이드
│   └── WAVE-SYSTEM.md              # Wave 실행 시스템
├── tasks/                          # 태스크 관리
├── .harness/                       # 런타임 상태 (실행 프로젝트에 생성)
│   ├── logs/                       # 세션/보안 로그
│   ├── state/                      # PDCA 단계, 에이전트 상태
│   └── backups/                    # 파일 편집 전 백업
└── README.md
```

## 검증

```bash
# 전체 검증
bash scripts/validate.sh

# 개별 검증
claude plugin validate .
bash -n hooks/*.sh

# 훅 동작 샘플 테스트
echo '{"cwd":"'"$(pwd)"'","tool_name":"Bash","tool_input":{"command":"ls"}}' | bash hooks/pre-tool.sh
cat hooks/hooks.json | jq .
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

세부 설정은 [자동화 설정 가이드](docs/templates/automation-config.md)를 참조하세요.

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

### 컨텍스트 템플릿

서브에이전트 호출 시 전달할 컨텍스트 템플릿:
- `docs/templates/context/PROJECT.md` — 프로젝트 개요
- `docs/templates/context/STATE.md` — 현재 작업 상태

상세 내용은 [Context Rot 가이드](docs/templates/context/README.md)를 참조하세요.

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

- [superpowers](https://github.com/obra/superpowers) — 자동 스킬 트리거, TDD 중심 개발 워크플로우
- [bkit-claude-code](https://github.com/popup-studio-ai/bkit-claude-code) — PDCA 사이클, Context Engineering 패턴
- [gstack](https://github.com/garrytan/gstack) — 역할 기반 모드 전환, 멀티 에이전트 구조
- [get-shit-done](https://github.com/gsd-build/get-shit-done) — spec-driven 상태 파일 시스템
- [gsd-2](https://github.com/gsd-build/gsd-2) — 차세대 GSD 아키텍처
- [oh-my-openagent](https://github.com/code-yeongyu/oh-my-openagent) — 오픈 에이전트 프레임워크

## 라이선스

MIT License
