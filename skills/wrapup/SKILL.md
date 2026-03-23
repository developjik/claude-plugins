---
name: wrapup
description: 구현 내용을 정리하고, 변경 로그와 문서를 작성합니다. PDCA 사이클의 마지막 단계입니다.
user-invocable: true
argument-hint: <기능명>
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

# Wrap-up Skill — PDCA 5단계

구현이 검증된 후, **정리·문서화·변경 로그 작성**을 수행합니다.

## 프로세스

### 1. 변경 사항 수집
$ARGUMENTS 에서 `<feature-slug>`를 식별하고, `docs/specs/<feature-slug>/` 하위의 산출물(`plan.md`, `design.md` 등) 및 관련된 모든 변경 사항을 수집합니다:
- 생성/수정/삭제된 파일 목록
- 커밋 히스토리
- 테스트 결과

### 2. Automated Documentation Sync (문서 자동 동기화)
구현 과정에서 변경된 실제 코드(함수 시그니처, API 경로 등)를 감지하여 `docs/` 내의 설계 문서나 `README.md`에 자동으로 반영하는 기능을 추가합니다. 이는 `git diff`나 `grep`을 활용하여 코드 변경 사항을 분석하고, 관련 문서 파일을 `Edit` 도구를 사용하여 업데이트하는 방식으로 진행됩니다.

#### 2.1. README.md 업데이트
- `git diff`를 통해 변경된 파일 목록과 내용을 확인하고, `README.md`에 영향을 줄 수 있는 변경 사항(새로운 기능, 설치/설정 변경 등)을 식별합니다.
- 식별된 변경 사항을 바탕으로 `README.md` 파일을 `Edit` 도구를 사용하여 업데이트합니다.

#### 2.2. CHANGELOG.md 업데이트
- `git log`를 통해 해당 기능과 관련된 커밋 메시지를 추출합니다.
- 추출된 커밋 메시지를 기반으로 `CHANGELOG.md` 파일에 `Added`, `Changed`, `Fixed` 섹션을 업데이트합니다.

#### 2.3. API 문서 업데이트 (해당 시)
- `grep` 등을 활용하여 코드 내에 정의된 새로운 API 엔드포인트나 변경된 API 시그니처를 탐지합니다.
- 탐지된 내용을 바탕으로 관련 API 문서 파일을 `Edit` 도구를 사용하여 업데이트합니다.

### 3. 코드 정리
- 디버그 코드 제거
- TODO 주석 정리
- 불필요한 import 제거

### 4. Post-Mortem & Knowledge Base (사후 분석 및 지식 자산화)
프로젝트 완료 후 `docs/templates/post-mortem.md` 템플릿을 기반으로 사후 분석 보고서를 자동 생성하고, 발생했던 이슈와 해결 방안을 `docs/knowledge-base/<feature-slug>-post-mortem.md` 경로에 저장하여 다음 프로젝트의 Plan 단계에서 참고하도록 합니다.

### 5. 최종 요약 문서 작성

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
