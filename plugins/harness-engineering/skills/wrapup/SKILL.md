---
name: wrapup
description: |
  Use after check passes. Document changes, write changelog, update README, finalize feature.
  Triggers on: 'wrapup', 'document', 'changelog', 'finalize', 'complete', 'done',
  '마무리', '문서화', '변경 로그', '완료', '정리', '최종',
  Error: 'document this', 'update changelog', 'what changed', 'feature complete'
user-invocable: true
argument-hint: <기능명>
allowed-tools: Read, Write, Edit, Grep, Glob
---

# Wrap-up Skill — PDCA 5단계

구현이 검증된 후, **정리·문서화·변경 로그 작성**을 수행합니다.

## 프로세스

### 1. 변경 사항 수집
$ARGUMENTS 에서 `<feature-slug>`를 식별하고, `docs/specs/<feature-slug>/` 하위의 산출물(`plan.md`, `design.md` 등) 및 관련된 모든 변경 사항을 수집합니다:
- 생성/수정/삭제된 파일 목록
- 커밋 히스토리
- 테스트 결과

### 2. 문서 업데이트

#### README.md
- 새 기능이 있으면 사용법 추가
- 설치/설정 변경이 있으면 반영

#### CHANGELOG.md
```markdown
## [날짜] - [기능명]
### Added
- [새 기능]
### Changed
- [변경 사항]
### Fixed
- [수정 사항]
```

#### API 문서 (해당 시)
- 새 엔드포인트 문서화
- 요청/응답 예제

### 3. 코드 정리
- 디버그 코드 제거
- TODO 주석 정리
- 불필요한 import 제거

### 4. 최종 요약 문서 작성

`docs/templates/wrapup.md` 템플릿을 읽고 내용을 채운 뒤, **`docs/specs/<feature-slug>/wrapup.md`** 경로에 저장합니다.
(별도 포맷을 지어내지 않고 템플릿의 항목을 모두 채워야 합니다)

## 출력

```
📚 Wrap-up 완료

📋 요약:
- 파일 변경: +X -Y ~Z
- 테스트: 전체 통과
- 문서: 업데이트됨
- 📄 산출물: docs/specs/<feature-slug>/wrapup.md

✅ PDCA 사이클 완료!
```
