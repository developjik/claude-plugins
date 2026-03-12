# Claude Code 플러그인 개선 결과 보고서: Harness Engineering

**작성일**: 2026년 3월 12일
**작성자**: Manus AI

## 1. 개요

본 보고서는 `developjik/harness-engineering` Claude Code 플러그인을 `superpowers`, `bkit-claude-code` 레포지토리 및 Claude Code 공식 문서의 최신 가이드를 기반으로 개선한 결과를 요약합니다. 개선 목표는 플러그인의 구조적 견고성, 에이전트의 효율적인 협업, 스킬의 재사용성 및 확장성, 그리고 훅 시스템을 통한 자동화 강화였습니다.

## 2. 주요 개선 내용

### 2.1. 플러그인 구조 및 매니페스트 (`.claude-plugin/plugin.json`)

`plugin.json` 파일의 메타데이터를 업데이트하여 플러그인의 정보 완전성을 높였습니다. `version`을 `1.1.0`으로 변경하고, `description`에 `superpowers`와 `bkit-claude-code`의 모범 사례 통합 내용을 명시했습니다. 또한, `keywords` 필드에 `multi-agent`, `context-engineering`, `git-worktree` 등 개선된 기능을 반영하는 키워드를 추가했습니다.

각 `skills` 및 `agents` 정의에 `description` 필드를 추가하여 Claude가 스킬과 에이전트를 선택하는 데 필요한 컨텍스트를 더욱 명확하게 제공하도록 했습니다. 이는 에이전트의 의사결정 정확도를 높이는 데 기여할 것입니다.

### 2.2. 에이전트 프롬프트 고도화

`architect`, `engineer`, `guardian`, `librarian` 각 에이전트의 Markdown 정의 파일(`agents/*.md`)을 다음과 같이 개선했습니다.

*   **`architect.md`**: `description`을 
더욱 구체화하여 '요구사항 분석 및 기술 설계 전문가. 프로젝트의 청사진을 작성하고 구현 전략을 수립합니다.'로 변경하고, `color` 속성을 추가했습니다.
*   **`engineer.md`**: `description`을 'TDD 기반 소프트웨어 구현 전문가. 설계 문서를 기반으로 고품질 코드를 작성합니다. RED-GREEN-REFACTOR 사이클을 따르며 스킬 있는 구현을 수행합니다.'로 변경하고, `color` 속성을 추가했습니다. 또한, TDD 프로세스(RED-GREEN-REFACTOR), 코드 품질 기준(SOLID, DRY, YAGNI, KISS), 진행 상황 보고 형식, 커밋 메시지 규칙, 완료 체크리스트 등을 상세히 추가하여 에이전트의 행동을 더욱 명확하게 가이드하도록 했습니다.
*   **`guardian.md`**: `description`을 '코드 품질 및 보안 검증 전문가. 구현된 코드의 기능성, 품질, 보안, 성능을 검증합니다. 코드 리뷰 및 개선 사항을 제시합니다.'로 변경하고, `color` 속성을 추가했습니다. 리뷰 프로세스(설계 문서 검토, 코드 구조 분석, 코드 품질 검토, 보안 검증, 성능 검증, 테스트 검증), 리뷰 결과 보고 형식, 피드백 작성 가이드, 승인 기준 등을 상세히 추가하여 체계적인 코드 리뷰를 수행하도록 했습니다.
*   **`librarian.md`**: `description`을 '기술 문서화 및 지식 관리 전문가. 개발 과정을 기록하고 API 문서, 가이드, ADR을 작성합니다.'로 변경하고, `color` 속성을 추가했습니다. 문서화 프로세스(개발 과정 정리, README 작성, API 문서 작성, 아키텍처 결정 기록(ADR), 개발자 가이드 작성, 문제 해결 가이드 작성), 문서 작성 가이드, 문서화 결과 보고 형식, 문서 체크리스트 등을 상세히 추가하여 포괄적인 문서화를 지원하도록 했습니다.

### 2.3. 훅 시스템 확장 및 개선 (`hooks.json` 및 스크립트)

`hooks.json` 파일을 확장하여 `PreToolUse` 훅을 추가하고, 기존 훅들의 `description`을 명확히 했습니다. 이는 `bkit-claude-code`의 훅 중심 구조를 참고하여 워크플로우의 각 단계에서 더 세밀한 제어와 자동화를 가능하게 합니다.

*   **`hooks/pre-bash.sh`**: Bash 명령어 실행 전에 위험한 명령어를 감지하고 차단하는 스크립트를 추가했습니다. `rm -rf /`, `sudo` 등의 위험한 패턴을 검사하여 보안을 강화합니다.
*   **`hooks/pre-edit.sh`**: 파일 편집 전에 자동으로 백업을 생성하는 스크립트를 추가했습니다. 이는 예기치 않은 변경으로부터 파일을 보호하는 역할을 합니다.
*   **`hooks/post-edit.sh`**: 파일 편집 후에 린트 검사(JavaScript/TypeScript, Python, Markdown)를 수행하고 변경 사항을 추적하는 스크립트를 개선했습니다. `jq`를 사용하여 Claude Code의 훅 입력 JSON을 파싱하도록 변경하고, 파일 해시를 이용한 변경 추적 기능을 추가했습니다. 이를 통해 코드 품질을 유지하고 변경 이력을 관리할 수 있습니다.

## 3. 결론

`developjik/harness-engineering` 플러그인은 Claude Code 공식 문서의 최신 가이드와 `superpowers`, `bkit-claude-code`의 모범 사례를 통합하여 더욱 강력하고 유연한 AI 기반 소프트웨어 개발 자동화 도구로 발전했습니다. 특히, 에이전트의 역할과 책임이 명확해지고, 훅 시스템을 통해 개발 워크플로우의 자동화 및 품질 관리가 강화되었습니다. 이 개선을 통해 사용자는 더욱 효율적이고 안정적인 AI 기반 개발 환경을 경험할 수 있을 것입니다.

## 4. 참고 문헌

[1] Claude Code Docs - Create plugins. Available at: https://code.claude.com/docs/en/plugins
[2] Claude Code Docs - Extend Claude with skills. Available at: https://code.claude.com/docs/en/skills
[3] Claude Code Docs - Create custom subagents. Available at: https://code.claude.com/docs/en/sub-agents
[4] Claude Code Docs - Hooks reference. Available at: https://code.claude.com/docs/en/hooks
[5] obra/superpowers GitHub Repository. Available at: https://github.com/obra/superpowers
[6] popup-studio-ai/bkit-claude-code GitHub Repository. Available at: https://github.com/popup-studio-ai/bkit-claude-code
[7] developjik/harness-engineering GitHub Repository. Available at: https://github.com/developjik/harness-engineering
