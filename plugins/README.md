# Plugins

각 하위 디렉터리는 Claude Code가 직접 설치하는 독립 플러그인입니다.

- `harness-engineering/`: 현재 배포 중인 PDCA 개발 자동화 플러그인
- `colo-fe-flow/`: Colo 사내 프론트엔드 표준화용 Jira-first workflow 플러그인

새 플러그인을 추가할 때는 `plugins/<plugin-name>/.claude-plugin/plugin.json`부터 만들고, 루트 marketplace 카탈로그에 등록하면 됩니다.
