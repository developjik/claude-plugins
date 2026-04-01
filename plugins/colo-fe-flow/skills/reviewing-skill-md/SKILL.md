---
name: reviewing-skill-md
description: Use when reviewing, validating, or improving a `SKILL.md`, especially for Anthropic skill guidance, frontmatter quality, trigger clarity, concise structure, progressive disclosure, or Korean-language skill authoring.
user-invocable: true
allowed-tools: Read, Write, Edit, Grep, Glob
---

# reviewing-skill-md

`SKILL.md`를 Anthropic 스타일 기준으로 검토하고, 위험이 낮고 명확한 문제는 직접 수정합니다. 애매한 변경은 수정하지 말고 finding으로 남깁니다.

`references/anthropic-skill-checklist.md`를 먼저 확인한 뒤 검토를 진행합니다.

## 입력

- 선택 인자: 검토할 `SKILL.md` 경로
- 인자가 없으면 현재 컨텍스트에서 가장 관련 있는 `SKILL.md`를 추정합니다.

대상 추정 순서:

1. 현재 활성 파일이 `SKILL.md`이면 그 파일
2. 현재 대화나 주변 문맥에서 직접 언급된 `SKILL.md`
3. 그래도 불명확하면 중단하고 경로를 사용자에게 묻기

## 검토 절차

1. 대상 `SKILL.md`를 읽습니다.
2. 필요하면 폴더명, 같은 스킬 디렉토리의 `references/`, `scripts/`, `assets/`만 최소 범위로 확인합니다.
3. 아래 항목을 검토합니다.

- frontmatter 유효성
- `name`의 kebab-case 및 역할 적합성
- `description`의 발견성, 트리거 명확성, 과설명 여부
- 본문의 간결성, 실행 가능성, 단계 구조
- progressive disclosure 준수 여부
- 한국어 스킬 본문 보존 여부

## 직접 수정 규칙

다음은 직접 수정합니다.

- 명백한 frontmatter 형식 오류
- 너무 약하거나 모호한 `description`
- 중복 설명이나 과한 장문 설명
- 섹션 이름, 번호, 표현의 명백한 불일치
- 의도가 분명한 저위험 wording 정리

다음은 직접 수정하지 않습니다.

- 호출 습관에 영향을 주는 큰 이름 변경
- 스킬 동작 자체를 바꾸는 정책 변경
- 외부 시스템 가정이 필요한 변경
- 여러 해석이 가능한 구조 개편

한국어 스킬 본문은 유지합니다. 한국어라는 이유만으로 영어로 번역하지 않습니다. 다만 `name`은 kebab-case를 유지하고, `description`은 한국어, 영어, 이중언어 모두 가능하지만 트리거 의도가 분명해야 합니다.

## 결과 출력

검토 후 반드시 아래를 알려줍니다.

1. 검토한 파일 경로
2. 직접 수정한 항목
3. 남겨둔 finding과 그 이유

문제가 없으면 문제 없다고 명시합니다.
