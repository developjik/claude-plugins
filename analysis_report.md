# developjik/harness-engineering 레포지토리 상세 분석 보고서

**작성일**: 2026년 3월 12일
**작성자**: Manus AI

## 1. 개요

`developjik/harness-engineering` 레포지토리는 PDCA(Plan-Do-Check-Act) 워크플로우를 기반으로 AI 소프트웨어 개발을 자동화하기 위한 Claude Code 플러그인 리소스 모음입니다. 이 프로젝트는 `bkit-claude-code`, `oh-my-openagent`, `superpowers`와 같은 기존 AI 에이전트 프로젝트들의 아이디어를 통합하여, AI 기반 개발 프로세스의 효율성과 품질을 향상시키는 것을 목표로 합니다. 특히, Claude와 대화하면서 동작하는 시스템 형태를 선호하는 사용자에게 적합하도록 설계되었습니다.

### 1.1. 핵심 개념

이 프로젝트의 핵심 개념은 다음과 같습니다.

*   **PDCA 워크플로우**: 계획(Plan), 수행(Do), 점검(Check), 조치(Act)의 반복적인 흐름을 통해 소프트웨어 개발 생명주기를 관리합니다.
*   **에이전트 분업**: Architect, Engineer, Guardian, Librarian과 같은 전문화된 AI 에이전트들이 각자의 역할을 수행하며 협업합니다.
*   **스킬 재사용**: 요구사항 정리, 구현, 리뷰, 문서화 등의 작업을 스킬 단위로 모듈화하여 재사용성을 높입니다.
*   **훅 자동화**: 세션 시작, 사용자 입력 제출, 서브 에이전트 시작/종료, 파일 편집 후 처리 등 다양한 이벤트에 대한 자동화된 처리를 제공합니다.

### 1.2. 참조 프로젝트

이 프로젝트는 다음 세 가지 주요 오픈소스 AI 에이전트 프로젝트의 아이디어를 참고했습니다.

| 프로젝트 이름 | 핵심 특징 | 도입 요소 |
| :------------ | :-------- | :-------- |
| `bkit-claude-code` | PDCA 방법론, 컨텍스트 엔지니어링 | PDCA 워크플로우, 상태 관리, 훅 시스템 |
| `oh-my-openagent` | 멀티 에이전트 오케스트레이션, `ultrawork` | 병렬 에이전트 실행, 통합 실행 명령어 |
| `superpowers` | TDD 강조, 서브 에이전트 기반 개발 | Red-Green-Refactor 사이클, 설계 우선 접근 |

## 2. 시스템 아키텍처

`harness-engineering`의 시스템 아키텍처는 PDCA 워크플로우를 중심으로 에이전트, 스킬, 훅 시스템이 유기적으로 결합된 형태입니다.

### 2.1. 디렉토리 구조

레포지토리의 주요 디렉토리 구조는 다음과 같습니다.

```
harness-engineering/
├── .claude-plugin/          # Claude Code 플러그인 메타데이터
│   └── plugin.json
├── agents/                  # 전문 에이전트 정의 (Markdown 형식)
│   ├── architect.md
│   ├── engineer.md
│   ├── guardian.md
│   └── librarian.md
├── skills/                  # 재사용 가능한 스킬 정의 (SKILL.md)
│   ├── brainstorm/
│   ├── document/
│   ├── implement/
│   └── review/
├── hooks/                   # 생명주기별 자동화 스크립트 (Bash)
│   ├── cleanup.sh
│   ├── on-architect-start.sh
│   ├── ...
│   └── validate-input.sh
├── hooks.json               # 훅 설정 파일
├── docs/                    # 추가 문서
│   ├── IMPLEMENTATION_GUIDE.md
│   ├── PDCA_WORKFLOW_DIAGRAM.md
│   └── REFERENCES.md
├── CLAUDE_CODE_PLUGIN_GUIDE.md # Claude Code 플러그인 사용 가이드
├── DESIGN.md                # 시스템 설계 배경 및 아키텍처 개요
├── IMPLEMENTATION_REPORT.md # 구현 완료 보고서
└── README.md                # 프로젝트 개요 및 빠른 시작 가이드
```

### 2.2. PDCA 워크플로우

이 시스템은 PDCA 사이클을 통해 소프트웨어 개발 과정을 체계적으로 관리합니다.

| 단계 | 담당 에이전트 | 주요 활동 |
| :--- | :------------ | :-------- |
| **Plan** | Architect | 요구사항 분석, 기술 평가, 설계 문서 작성 |
| **Do** | Engineer | 설계 기반 코드 구현, TDD 수행, 리팩토링 |
| **Check** | Guardian | 코드 리뷰, 품질/보안/성능 검증, 테스트 커버리지 확인 |
| **Act** | Librarian | 문서화, 지식 관리, 개선 사항 반영 |

### 2.3. 에이전트 시스템

총 4개의 전문 에이전트가 정의되어 있으며, 각 에이전트는 특정 개발 단계와 역할에 특화되어 있습니다.

| 에이전트 | 역할 | 설명 |
| :------- | :--- | :--- |
| `architect` | 요구사항 분석, 설계 옵션 제안, 설계 문서 작성 | 프로젝트의 청사진을 그립니다. |
| `engineer` | TDD 기반 구현, 리팩터링, 진행 보고 | 실제 코드를 작성하고 테스트합니다. |
| `guardian` | 기능/품질/보안/성능 리뷰 | 코드의 품질과 안정성을 검증합니다. |
| `librarian` | README, 가이드, API 문서 등 문서화 | 개발 과정을 기록하고 지식을 공유합니다. |

각 에이전트는 `agents/` 디렉토리 내의 Markdown 파일로 정의되며, YAML 프런트 매터(front matter)를 통해 이름, 설명, 사용 가능한 도구, 모델 등의 메타데이터를 포함합니다.

### 2.4. 스킬 시스템

스킬은 에이전트가 특정 작업을 수행하는 데 필요한 지침과 절차를 캡슐화한 재사용 가능한 모듈입니다. `skills/` 디렉토리 내에 `SKILL.md` 파일 형태로 존재합니다.

| 스킬 이름 | 목적 | 주요 내용 |
| :-------- | :--- | :-------- |
| `brainstorm` | 요구사항 정리 및 설계 초안 도출 | 요구사항 정제 질문, 아이디어 도출, 평가 및 선택 |
| `implement` | RED-GREEN-REFACTOR 기반 구현 | TDD 사이클, 코드 품질 기준 (SOLID, DRY, YAGNI, KISS), 테스트 작성 가이드, 커밋 메시지 규칙 |
| `review` | 코드 품질 및 보안 검토 | (내용 확인 필요) |
| `document` | 사용자/개발자 문서 작성 | (내용 확인 필요) |

`implement` 스킬의 경우, TDD의 RED-GREEN-REFACTOR 사이클, SOLID 원칙, DRY, YAGNI, KISS 원칙 등 구체적인 코드 품질 기준과 테스트 작성 가이드, 커밋 메시지 규칙까지 상세하게 명시되어 있어 고품질 코드 작성을 유도합니다.

### 2.5. 훅 시스템

훅 시스템은 특정 이벤트 발생 시 자동으로 스크립트를 실행하여 워크플로우를 자동화합니다. `hooks.json` 파일에 정의되어 있으며, `hooks/` 디렉토리 내의 Bash 스크립트들을 호출합니다.

| 훅 이벤트 | 목적 | 관련 스크립트 |
| :-------- | :--- | :------------ |
| `SessionStart` | 세션 시작 시 초기화 | `hooks/setup.sh` |
| `UserPromptSubmit` | 사용자 입력 제출 시 유효성 검사 | `hooks/validate-input.sh` |
| `PostToolUse` | 도구 사용 후 (특히 파일 편집) | `hooks/post-edit.sh` |
| `SubagentStart` | 서브 에이전트 시작 시 | `hooks/on-architect-start.sh`, `on-engineer-start.sh` 등 |
| `SubagentStop` | 서브 에이전트 종료 시 | `hooks/on-architect-stop.sh`, `on-engineer-stop.sh` 등 |
| `SessionEnd` | 세션 종료 시 정리 | `hooks/cleanup.sh` |

`setup.sh` 스크립트는 세션 시작 시 로그 파일을 설정하고, 프로젝트 유형(Node.js, Git)을 감지하여 로그를 기록하는 역할을 합니다.

## 3. 구현 패턴 및 특징

### 3.1. 컨텍스트 엔지니어링

이 프로젝트는 단순한 프롬프트 지시를 넘어, 에이전트의 역할 정의(`agents/*.md`), 스킬(`skills/*/SKILL.md`), 그리고 훅(`hooks.json`, `hooks/*.sh`)을 통해 LLM에게 최적의 컨텍스트를 제공하는 컨텍스트 엔지니어링 접근 방식을 사용합니다. 이는 LLM이 더 정확하고 일관된 작업을 수행하도록 돕습니다.

### 3.2. 멀티 에이전트 오케스트레이션

PDCA 워크플로우에 따라 Architect, Engineer, Guardian, Librarian 에이전트가 순차적으로 또는 필요에 따라 협업하도록 설계되었습니다. 각 에이전트는 자신의 전문 분야에 집중하여 복잡한 개발 작업을 분해하고 효율적으로 처리합니다. `IMPLEMENTATION_GUIDE.md` 문서에 따르면 `ultrawork` 명령어를 통해 모든 에이전트를 자동으로 순차 실행하는 기능도 포함되어 있습니다.

### 3.3. 테스트 주도 개발 (TDD) 강조

`implement` 스킬에서 TDD의 RED-GREEN-REFACTOR 사이클을 명확히 강조하고 있습니다. 이는 코드 구현 시 테스트를 먼저 작성하고, 최소한의 코드로 테스트를 통과시킨 후 리팩토링하는 과정을 반복함으로써 코드 품질과 안정성을 높이는 데 기여합니다.

### 3.4. 모듈화 및 확장성

에이전트, 스킬, 훅이 각각 독립적인 파일로 정의되어 있어 시스템의 모듈성이 높습니다. 새로운 에이전트나 스킬을 추가하거나 기존 훅의 동작을 변경하기 용이하여 시스템의 확장성이 뛰어납니다.

## 4. 결론 및 시사점

`developjik/harness-engineering` 레포지토리는 AI 기반 소프트웨어 개발 프로세스를 체계화하고 자동화하기 위한 견고한 프레임워크를 제공합니다. PDCA 워크플로우, 전문 에이전트, 재사용 가능한 스킬, 그리고 자동화된 훅 시스템의 결합은 AI가 복잡한 개발 작업을 수행하는 데 필요한 구조와 지침을 효과적으로 제공합니다.

이 프로젝트는 다음과 같은 시사점을 가집니다.

*   **AI 개발 생산성 향상**: 반복적이고 정형화된 개발 작업을 AI 에이전트에게 위임함으로써 개발자의 생산성을 크게 향상시킬 수 있습니다.
*   **코드 품질 및 일관성 유지**: TDD, 코드 품질 기준, 리뷰 프로세스 등을 에이전트 워크플로우에 통합하여 개발되는 소프트웨어의 품질과 일관성을 보장합니다.
*   **유연한 확장성**: 모듈화된 에이전트 및 스킬 시스템을 통해 특정 프로젝트나 요구사항에 맞춰 시스템을 쉽게 커스터마이징하고 확장할 수 있습니다.
*   **AI 에이전트 설계의 모범 사례**: 컨텍스트 엔지니어링, 멀티 에이전트 오케스트레이션 등 AI 에이전트 시스템 설계에 있어 모범적인 접근 방식을 보여줍니다.

궁극적으로 이 프로젝트는 AI가 단순한 코드 생성 도구를 넘어, 소프트웨어 개발 생명주기 전반에 걸쳐 능동적으로 참여하고 기여할 수 있는 가능성을 제시합니다. 특히 Claude Code 플러그인 형태로 제공되어, Claude와 같은 대규모 언어 모델을 활용한 개발 자동화에 관심 있는 사용자들에게 매우 유용한 리소스가 될 것입니다.

## 5. 참고 문헌

[1] developjik/harness-engineering GitHub Repository. Available at: https://github.com/developjik/harness-engineering
[2] `README.md` file from developjik/harness-engineering. Available in the cloned repository.
[3] `DESIGN.md` file from developjik/harness-engineering. Available in the cloned repository.
[4] `IMPLEMENTATION_GUIDE.md` file from developjik/harness-engineering. Available in the cloned repository.
[5] `hooks.json` file from developjik/harness-engineering. Available in the cloned repository.
[6] `agents/architect.md` file from developjik/harness-engineering. Available in the cloned repository.
[7] `skills/implement/SKILL.md` file from developjik/harness-engineering. Available in the cloned repository.
[8] `.claude-plugin/plugin.json` file from developjik/harness-engineering. Available in the cloned repository.
