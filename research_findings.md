# Claude Code 플러그인 개선을 위한 연구 분석 결과

## 1. Claude Code 공식 문서 주요 포인트
- **플러그인 구조**: `.claude-plugin/plugin.json` 매니페스트 필수. `skills/`, `agents/`, `hooks/` 디렉토리는 루트에 위치해야 함.
- **스킬 (Skills)**: `SKILL.md` 형식 준수. 프런트매터에 `name`, `description` 포함. `$ARGUMENTS`를 통한 동적 입력 처리 가능.
- **서브 에이전트 (Sub-agents)**: Markdown 파일로 정의. `description`이 에이전트 선택의 핵심 기준. `tools`, `model`, `prompt` 설정 가능.
- **훅 (Hooks)**: `hooks.json`에서 정의. `SessionStart`, `PreToolUse`, `PostToolUse`, `SubagentStart` 등 다양한 이벤트 지원. `matcher`를 통한 정교한 필터링 가능.

## 2. superpowers (obra) 분석
- **워크플로우**: `git worktree`를 활용한 독립적인 작업 환경 구성. TDD(`test-driven-development`)와 계획 수립(`writing-plans`)을 스킬로 명문화.
- **에이전트 협업**: `subagent-driven-development` 스킬을 통해 작업을 세분화하고 서브 에이전트에게 위임하는 패턴.
- **특징**: `finishing-a-development-branch`와 같은 실제 개발 프로세스 종결 단계까지 스킬로 관리.

## 3. bkit-claude-code (popup-studio-ai) 분석
- **PDCA 워크플로우**: `bkit-system` 내에서 세션 상태 관리 및 PDCA 사이클 추적.
- **훅 중심 구조**: `hooks/session-start.js` 등을 통해 세션 시작 시 환경 설정 및 로깅 자동화. `hooks.json`을 통한 체계적인 이벤트 핸들링.
- **컨텍스트 엔지니어링**: 에이전트와 스킬에 최적화된 프롬프트를 제공하여 AI의 일관성 유지.

## 4. 개선 방향 (harness-engineering)
- **구조 최적화**: 공식 가이드에 맞춰 디렉토리 및 매니페스트 구조 재정립.
- **PDCA 엔진 강화**: `bkit` 스타일의 상태 관리 및 세션 추적 로직 강화.
- **TDD & Worktree 도입**: `superpowers`의 `git worktree` 및 TDD 워크플로우를 스킬로 통합.
- **서브 에이전트 정교화**: 에이전트별 `description`과 `prompt`를 공식 규격에 맞춰 고도화하여 에이전트 자동 선택 성능 향상.
- **훅 자동화 확장**: 코드 편집 후 린트 체크, 테스트 자동 실행 등 실질적인 개발 보조 훅 추가.
