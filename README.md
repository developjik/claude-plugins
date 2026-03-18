# Harness Engineering

확장 PDCA(Plan→Design→Do→Check→Wrap-up) 기반 AI 소프트웨어 개발 자동화 Claude Code 플러그인.

6개 전문 에이전트(인지 모드)와 8개 실행 스킬로 체계적인 개발 워크플로우를 제공합니다.

## 한눈에 보기

- **6개 에이전트**: `strategist`, `architect`, `engineer`, `guardian`, `librarian`, `debugger`
- **9개 스킬**: `plan`, `design`, `implement`, `check`, `wrapup`, `harness`, `debug`, `fullrun`, `grill-me`
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
/plan <기능 설명>             # 1. feature-slug 확정 + docs/specs/<slug>/plan.md 생성
/design <feature-slug>        # 2. docs/specs/<slug>/plan.md 기반 설계
/implement <feature-slug>     # 3. docs/specs/<slug>/design.md 기반 TDD 구현
/check <feature-slug>         # 4. 계획 대비 리뷰 + 검증 + 자동 반복
/wrapup <feature-slug>        # 5. docs/specs/<slug>/wrapup.md 생성 + 문서화
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
/fullrun <기능 설명>     # Plan→Design→Do→Check→Wrap-up 한번에
```

### 유틸리티

```
/debug <버그 설명>       # 체계적 4단계 디버깅
```

### Feature Slug 규칙

- `/plan` 또는 `/fullrun` 이 최초 실행 시 `kebab-case` slug를 확정합니다. 예: `user-auth`
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
├── skills/                         # 스킬 (8개)
│   ├── plan/SKILL.md
│   ├── design/SKILL.md
│   ├── implement/SKILL.md
│   ├── check/SKILL.md
│   ├── wrapup/SKILL.md
│   ├── harness/SKILL.md
│   ├── debug/SKILL.md
│   ├── fullrun/SKILL.md
│   └── grill-me/SKILL.md
├── hooks/                          # 훅 스크립트 (6개)
├── hooks.json                      # 훅 설정
├── scripts/                        # 검증 스크립트
│   └── validate.sh
├── docs/                           # 문서
│   ├── ARCHITECTURE.md
│   ├── ARTIFACT-CONVENTION.md
│   ├── SKILL-WRITING-GUIDE.md
│   ├── AGENT-WRITING-GUIDE.md
│   ├── HOOK-WRITING-GUIDE.md
│   ├── templates/
│   │   ├── plan.md
│   │   ├── design.md
│   │   └── wrapup.md
│   └── specs/                      # 실행 시 생성되는 feature 산출물 저장소
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
cat hooks.json | jq .
```

## 문서

- [아키텍처](docs/ARCHITECTURE.md) — PDCA 흐름, 에이전트-스킬 관계, 훅 라이프사이클
- [산출물 규약](docs/ARTIFACT-CONVENTION.md) — `docs/specs/<feature-slug>/` 기반 SSOT 규칙
- [스킬 작성 가이드](docs/SKILL-WRITING-GUIDE.md) — 커스텀 스킬 만들기
- [에이전트 작성 가이드](docs/AGENT-WRITING-GUIDE.md) — 커스텀 에이전트 만들기
- [훅 작성 가이드](docs/HOOK-WRITING-GUIDE.md) — 커스텀 훅 만들기

## 참고

- [superpowers](https://github.com/obra/superpowers) — 자동 스킬 트리거, TDD 중심
- [bkit-claude-code](https://github.com/popup-studio-ai/bkit-claude-code) — PDCA, Context Engineering
- [gstack](https://github.com/garrytan/gstack) — 역할 기반 모드 전환
- [get-shit-done](https://github.com/gsd-build/get-shit-done) — spec-driven 상태 파일 시스템

## 라이선스

MIT License
