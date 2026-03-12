# Claude Code 플러그인 개선 설계안: Harness Engineering

**작성일**: 2026년 3월 12일
**작성자**: Manus AI

## 1. 개요

본 문서는 `developjik/harness-engineering` Claude Code 플러그인을 `superpowers`, `bkit-claude-code` 레포지토리 및 Claude Code 공식 문서의 최신 가이드를 기반으로 개선하기 위한 설계안을 제시합니다. 주요 개선 목표는 플러그인의 구조적 견고성, 에이전트의 효율적인 협업, 스킬의 재사용성 및 확장성, 그리고 훅 시스템을 통한 자동화 강화입니다.

## 2. 플러그인 구조 개선

현재 `harness-engineering` 레포지토리는 Claude Code 플러그인 구조를 따르고 있으나, 공식 문서의 최신 권장 사항을 반영하여 더욱 명확하고 확장 가능한 구조로 개선합니다.

### 2.1. `plugin.json` 매니페스트

`plugin.json` 파일은 플러그인의 메타데이터를 정의하며, `name`, `description`, `version`, `author` 외에 `homepage`, `repository`, `license` 필드를 추가하여 정보의 완전성을 높입니다. 또한, `skills`, `agents` 및 `hooks`의 `path` 정의가 현재 구조와 일치하는지 확인하고 필요시 업데이트합니다.

### 2.2. 디렉토리 구조 정렬

Claude Code 공식 문서에 따르면 `commands/`, `agents/`, `skills/`, `hooks/` 디렉토리는 플러그인 루트 레벨에 위치해야 합니다. 현재 `harness-engineering`는 이 구조를 잘 따르고 있으므로 큰 변경은 필요 없으나, 향후 `settings.json`이나 `MCP` 서버 관련 파일이 추가될 경우 루트에 배치하도록 가이드라인을 명확히 합니다.

## 3. 스킬 시스템 고도화

스킬은 에이전트의 핵심 역량이므로, `superpowers`의 상세한 워크플로우 스킬과 Claude Code 공식 문서의 `SKILL.md` 작성 가이드를 참고하여 개선합니다.

### 3.1. `SKILL.md` 작성 표준화

모든 `SKILL.md` 파일은 다음 요소를 포함하도록 표준화합니다.

*   **프런트매터**: `name`, `description`, `disable-model-invocation`, `user-invocable`, `allowed-tools` 등의 메타데이터를 명확히 정의합니다. 특히 `description`은 Claude가 스킬을 언제 호출해야 하는지 판단하는 중요한 기준이 되므로, 구체적이고 명확하게 작성합니다.
*   **목표 및 프로세스**: 스킬의 명확한 목표와 단계별 실행 프로세스를 상세히 기술합니다. `superpowers`의 `test-driven-development` 스킬처럼 RED-GREEN-REFACTOR 사이클, 코드 품질 기준 등을 구체적인 예시와 함께 제시합니다.
*   **입력 및 출력**: `$ARGUMENTS`를 활용한 동적 입력 처리 방법을 명시하고, 스킬 실행 후 예상되는 산출물 형식을 정의합니다.
*   **주의사항 및 체크리스트**: 스킬 사용 시 주의할 점과 완료 후 검증할 체크리스트를 포함하여 품질을 확보합니다.

### 3.2. `superpowers` 스킬 통합 아이디어

`harness-engineering`의 기존 스킬(`brainstorm`, `implement`, `review`, `document`)을 `superpowers`의 다음 스킬들을 참고하여 강화합니다.

| `superpowers` 스킬 | `harness-engineering` 적용 방안 |
| :----------------- | :------------------------------ |
| `writing-plans` | `architect` 에이전트의 `brainstorm` 스킬에 통합하여 설계 문서 작성 프로세스 강화. |
| `test-driven-development` | `engineer` 에이전트의 `implement` 스킬을 더욱 구체화. 테스트 작성 가이드, 커밋 메시지 규칙 등을 상세화. |
| `using-git-worktrees` | `engineer` 에이전트가 독립적인 작업 환경에서 작업할 수 있도록 훅 또는 스킬로 통합 검토. |
| `requesting-code-review` / `receiving-code-review` | `guardian` 에이전트의 `review` 스킬에 통합하여 코드 리뷰 요청 및 피드백 반영 프로세스 체계화. |
| `finishing-a-development-branch` | `librarian` 에이전트의 `document` 스킬 또는 별도 훅으로 통합하여 개발 브랜치 종료 및 병합 전 최종 검증 자동화. |

## 4. 에이전트 시스템 최적화

서브 에이전트의 역할 분리와 효율적인 위임은 `harness-engineering`의 핵심이므로, Claude Code 공식 문서의 가이드와 `superpowers`의 서브 에이전트 패턴을 참고하여 최적화합니다.

### 4.1. 에이전트 정의 파일 (`agents/*.md`)

각 에이전트의 Markdown 파일은 다음을 포함하도록 개선합니다.

*   **프런트매터**: `name`, `description`, `tools`, `model` 등의 메타데이터를 명확히 정의합니다. 특히 `description`은 에이전트의 핵심 역할과 사용 시점을 명확히 설명하여 Claude가 적절한 에이전트를 선택하도록 유도합니다.
*   **시스템 프롬프트**: 에이전트의 행동을 안내하는 시스템 프롬프트를 구체적이고 명확하게 작성합니다. `superpowers`의 `subagent-driven-development` 스킬처럼, 복잡한 작업을 서브 에이전트에게 위임하는 패턴을 프롬프트에 반영할 수 있습니다.
*   **책임 및 프로세스**: 에이전트의 주요 책임과 수행해야 할 단계별 프로세스를 상세히 기술합니다. 예를 들어, `architect` 에이전트는 요구사항 정제, 기술 평가, 설계 문서 작성 등의 단계를 명확히 따르도록 지시합니다.

### 4.2. 에이전트 간 협업 강화

PDCA 워크플로우에 따라 에이전트 간의 전환 및 협업을 더욱 강화합니다. 예를 들어, `architect`가 설계 문서를 완성하면 `engineer`에게 작업을 위임하고, `engineer`는 구현 완료 후 `guardian`에게 코드 리뷰를 요청하는 식의 명시적인 흐름을 구축합니다. 이는 훅 시스템과 연동하여 자동화될 수 있습니다.

## 5. 훅 시스템 강화

`bkit-claude-code`의 훅 중심 구조와 Claude Code 공식 문서의 훅 레퍼런스를 참고하여 `harness-engineering`의 훅 시스템을 확장하고 강화합니다.

### 5.1. `hooks.json` 및 스크립트 개선

*   **훅 이벤트 확장**: 현재 `harness-engineering`의 `hooks.json`은 `SessionStart`, `UserPromptSubmit`, `PostToolUse`, `SubagentStart`, `SubagentStop`, `SessionEnd`를 사용하고 있습니다. 여기에 `bkit-claude-code`에서 영감을 받아 `PreToolUse`, `PhaseTransition` 등의 훅을 추가하여 워크플로우의 각 단계에서 더 세밀한 제어와 자동화를 가능하게 합니다.
*   **`matcher` 활용**: `hooks.json`의 `matcher` 필드를 적극적으로 활용하여 특정 도구 사용(`Bash`, `Edit|Write` 등)이나 특정 에이전트(`architect`, `engineer` 등)에 대해서만 훅이 실행되도록 정교하게 설정합니다.
*   **스크립트 기능 강화**: 각 훅에 연결된 Bash 스크립트(`hooks/*.sh`)의 기능을 강화합니다. 예를 들어:
    *   `PreToolUse` 훅에서 특정 위험한 명령어(`rm -rf` 등) 실행을 차단하거나 사용자 확인을 요청하는 로직 추가.
    *   `PostToolUse` 훅에서 파일 변경 후 자동 린트 검사, 테스트 실행, 또는 변경 사항 커밋 제안.
    *   `PhaseTransition` 훅에서 PDCA 단계 전환 시 필요한 환경 설정 또는 상태 업데이트 자동화.

### 5.2. 상태 관리와의 연동

`bkit-claude-code`의 상태 관리 시스템을 참고하여, 훅이 PDCA 워크플로우의 현재 상태를 읽고 업데이트할 수 있도록 연동을 강화합니다. 예를 들어, `SubagentStart` 훅에서 현재 활성화된 에이전트 정보를 `state/current-agent.txt`에 기록하는 것을 넘어, PDCA 단계(`Plan`, `Do`, `Check`, `Act`) 정보도 함께 관리하도록 개선합니다.

## 6. 결론

이 설계안은 `harness-engineering` 플러그인을 Claude Code 생태계의 모범 사례를 따르면서도, `superpowers`와 `bkit-claude-code`의 강점을 흡수하여 더욱 강력하고 유연한 AI 기반 소프트웨어 개발 자동화 도구로 발전시키기 위한 청사진을 제시합니다. 다음 단계에서는 이 설계안을 바탕으로 실제 코드 수정 및 구현을 진행할 예정입니다.

## 7. 참고 문헌

[1] Claude Code Docs - Create plugins. Available at: https://code.claude.com/docs/en/plugins
[2] Claude Code Docs - Extend Claude with skills. Available at: https://code.claude.com/docs/en/skills
[3] Claude Code Docs - Create custom subagents. Available at: https://code.claude.com/docs/en/sub-agents
[4] Claude Code Docs - Hooks reference. Available at: https://code.claude.com/docs/en/hooks
[5] obra/superpowers GitHub Repository. Available at: https://github.com/obra/superpowers
[6] popup-studio-ai/bkit-claude-code GitHub Repository. Available at: https://github.com/popup-studio-ai/bkit-claude-code
[7] developjik/harness-engineering GitHub Repository. Available at: https://github.com/developjik/harness-engineering
