# Anthropic Skill Checklist

`SKILL.md`를 검토할 때 아래 항목을 빠르게 확인합니다.

## Frontmatter

- `name` 존재
- `description` 존재
- 유효한 YAML
- `name`은 kebab-case
- 폴더명과 크게 어긋나지 않음

## Description

- 언제 써야 하는지 분명함
- vague 표현이 아님
- 자동 발견에 필요한 키워드가 있음
- workflow 전체를 장황하게 요약하지 않음

## Body

- 장황하지 않음
- 단계가 실행 가능함
- 실패 처리나 중단 조건이 필요한 곳에 있음
- Claude가 이미 아는 상식을 길게 반복하지 않음

## Progressive Disclosure

- 핵심 지침만 `SKILL.md`에 있음
- 큰 참고 자료는 `references/`로 분리
- 필요한 파일만 읽도록 유도함

## Korean Authoring

- 한국어 본문 허용
- 한국어라는 이유로 영어 번역 강제 금지
- `name`은 kebab-case 유지
- `description`은 한국어, 영어, 이중언어 모두 가능하지만 트리거가 분명해야 함

## Auto-Fix Boundary

직접 수정:

- frontmatter의 명백한 문제
- description의 명백한 약점
- 중복 설명
- 저위험 wording 정리

finding으로 남기기:

- 큰 이름 변경
- 정책 변경
- 구조 재설계
- 외부 시스템 가정이 필요한 수정
