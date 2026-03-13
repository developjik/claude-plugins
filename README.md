# Harness Engineering

Claude Code에서 PDCA(Plan, Do, Check, Act) 흐름으로 작업하도록 돕는 플러그인 리소스 모음입니다. 이 저장소는 실행형 애플리케이션이 아니라 플러그인 매니페스트, 에이전트 프롬프트, 스킬 정의, Bash 훅 스크립트로 구성됩니다.

## 한눈에 보기

- 4개 에이전트: `architect`, `engineer`, `guardian`, `librarian`
- 4개 스킬: `brainstorm`, `implement`, `review`, `document`
- 훅 자동화: 세션 로깅, 에이전트 상태 추적, 편집 전 백업, 편집 후 변경 추적, 위험한 Bash 명령 차단
- 참고 아이디어: `bkit-claude-code`, `oh-my-openagent`, `superpowers`

## 현재 구현 범위

- 포함: Claude Code 플러그인 매니페스트, 에이전트/스킬 정의, 훅 스크립트, 보조 문서
- 미포함: `package.json`, npm 스크립트, API 서버, `ultrawork`, 자동 단계 전환 엔진, 세션 데이터베이스
- 실제 사용 방식: 사용자가 Claude Code 안에서 에이전트를 직접 전환하며 PDCA 흐름을 진행

즉, 이 저장소는 "개발 워크플로우를 안내하는 플러그인 번들"이지, 단독 실행형 도구는 아닙니다.

## 저장소 구조

```text
harness-engineering/
├── .claude-plugin/
│   └── plugin.json
├── .gitignore
├── agents/
│   ├── architect.md
│   ├── engineer.md
│   ├── guardian.md
│   └── librarian.md
├── skills/
│   ├── brainstorm/SKILL.md
│   ├── document/SKILL.md
│   ├── implement/SKILL.md
│   └── review/SKILL.md
├── hooks/
│   ├── setup.sh
│   ├── validate-input.sh
│   ├── pre-bash.sh
│   ├── pre-edit.sh
│   ├── post-bash.sh
│   ├── post-edit.sh
│   ├── on-*-start.sh
│   ├── on-*-stop.sh
│   └── cleanup.sh
├── docs/
│   ├── PDCA_WORKFLOW_DIAGRAM.md
│   └── REFERENCES.md
├── hooks.json
└── README.md
```

## 설치

Claude Code에서 플러그인을 설치하고 활성화합니다.

```bash
/plugin install https://github.com/developjik/harness-engineering
/plugin enable harness-engineering
```

## 권장 사용 흐름

1. `/architect`로 요구사항 정리와 설계를 진행합니다.
2. `/engineer`로 설계 문서를 바탕으로 구현과 테스트를 진행합니다.
3. `/guardian`으로 기능, 품질, 보안, 성능 관점 리뷰를 진행합니다.
4. `/librarian`으로 README, 가이드, ADR 등 문서를 정리합니다.

스킬은 플러그인 매니페스트에도 등록되어 있으며, Claude Code가 상황에 맞게 선택하거나 클라이언트가 지원하는 경우 직접 호출할 수 있습니다.

## 실제 훅 동작

| Hook | Matcher | 실제 동작 | 산출물 위치 |
| :--- | :--- | :--- | :--- |
| `SessionStart` | - | 세션 시작 로그 기록, Git 브랜치/프로젝트 여부 감지 | `logs/session.log` |
| `UserPromptSubmit` | - | 사용자 입력 길이 기록 | `logs/session.log` |
| `PreToolUse` | `Bash` | 위험한 명령과 `sudo` 사용 차단 | `~/.harness-engineering/logs/` |
| `PreToolUse` | `Write|Edit` | 편집 전 파일 백업 생성 | `~/.harness-engineering/backups/` |
| `PostToolUse` | `Bash` | Bash 훅 페이로드 로깅 | `~/.harness-engineering/logs/` |
| `PostToolUse` | `Write|Edit` | 파일 해시 추적, 선택적 린트 실행, 변경 이력 기록 | `~/.harness-engineering/logs/`, `~/.harness-engineering/state/changes.txt` |
| `SubagentStart` | `architect|engineer|guardian|librarian` | 현재 에이전트 상태 저장, PDCA 단계 로그 기록 | `state/current-agent.txt`, `logs/session.log` |
| `SubagentStop` | `architect|engineer|guardian|librarian` | 에이전트 종료 로그 기록 | `logs/session.log` |
| `SessionEnd` | - | 세션 종료 로그 기록 | `logs/session.log` |

중요한 점은 훅이 PDCA 단계를 자동으로 전환하지는 않는다는 것입니다. 현재 구현은 "기록, 백업, 가드, 변경 추적" 중심입니다.

훅 입력 계약은 `stdin`으로 전달되는 JSON 페이로드를 기본으로 사용합니다. `pre-bash.sh`, `pre-edit.sh`는 이전 환경과의 호환을 위해 각각 `BASH_COMMAND`, `EDITED_FILES` 환경 변수도 보조적으로 읽습니다.

## 요구 사항

다음 도구가 있으면 훅을 무리 없이 사용할 수 있습니다.

- 필수에 가까움: `bash`, `jq`
- 환경에 따라 사용: `git`
- 변경 추적 해시 계산: `md5sum` 또는 `md5`
- 선택 사항: `eslint`, `pylint`, `markdownlint`

## 런타임 산출물

저장소 루트와 사용자 홈 디렉터리 두 곳에 런타임 파일이 생깁니다.

- 워크스페이스 기준: `logs/session.log`, `state/current-agent.txt` (`.gitignore`로 제외)
- 사용자 홈 기준: `~/.harness-engineering/backups/`, `~/.harness-engineering/logs/`, `~/.harness-engineering/state/changes.txt`

## 문서

- [docs/PDCA_WORKFLOW_DIAGRAM.md](./docs/PDCA_WORKFLOW_DIAGRAM.md): PDCA 개념도
- [docs/REFERENCES.md](./docs/REFERENCES.md): 외부 참고 자료

## 라이선스

MIT License
