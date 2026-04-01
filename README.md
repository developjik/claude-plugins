# developjik-plugins

Claude Code 플러그인을 여러 개 담아 배포하기 위한 marketplace 저장소입니다.

현재 포함된 플러그인:

- `harness-engineering`: 확장 PDCA 기반 AI 소프트웨어 개발 자동화 플러그인
- `colo-fe-flow`: Jira-first 프론트엔드 워크플로우 오케스트레이터 플러그인

## 구조

```text
developjik-plugins/
├── .claude-plugin/marketplace.json
├── plugins/
│   ├── harness-engineering/
│   │   ├── .claude-plugin/plugin.json
│   │   ├── agents/
│   │   ├── skills/
│   │   ├── hooks/
│   │   ├── docs/
│   │   ├── scripts/
│   │   └── README.md
│   └── colo-fe-flow/
│       ├── .claude-plugin/plugin.json
│       ├── agents/
│       ├── skills/
│       ├── hooks/
│       ├── docs/
│       ├── scripts/
│       └── README.md
└── scripts/
    ├── lint-shell.sh
    └── validate.sh
```

## 로컬 테스트

```bash
# marketplace 추가
/plugin marketplace add .

# marketplace에서 플러그인 설치
/plugin install harness-engineering@developjik-plugins

# 특정 플러그인만 직접 테스트
claude --plugin-dir ./plugins/harness-engineering
claude --plugin-dir ./plugins/colo-fe-flow
```

## 검증

```bash
# marketplace + 모든 플러그인 검증
bash scripts/validate.sh --full

# marketplace에 포함된 플러그인들의 shell lint 실행
bash scripts/lint-shell.sh --check
```

## 새 플러그인 추가

1. `plugins/<plugin-name>/` 디렉터리를 만듭니다.
2. `plugins/<plugin-name>/.claude-plugin/plugin.json`을 추가합니다.
3. 필요한 `skills/`, `agents/`, `hooks/` 등을 채웁니다.
4. 루트 `.claude-plugin/marketplace.json`의 `plugins[]`에 항목을 추가합니다.
5. `bash scripts/validate.sh --full`로 전체 검증을 돌립니다.
