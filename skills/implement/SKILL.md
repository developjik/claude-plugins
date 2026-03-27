---
name: implement
description: |
  Use when design.md is ready. TDD implementation with RED-GREEN-REFACTOR cycle.
  Triggers on: 'implement', 'code', 'build', 'develop', 'write code', 'TDD', 'test-driven',
  '구현', '코딩', '개발', '코드 작성', '만들기', '빌드', '테스트 주도',
  Error: 'not implemented', 'feature missing', 'code needed', 'build this'
user-invocable: true
argument-hint: <기능명 또는 Design 문서 경로>
allowed-tools: Read, Write, Edit, Bash, Grep, Glob
requires: design
---

# Implement Skill — PDCA 3단계 (Do)

Design 문서를 기반으로 **TDD 사이클**로 코드를 구현합니다.

## 프로세스

### 1. Git Worktree 설정 및 Design 문서 로드
먼저, 현재 기능 개발을 위한 격리된 Git Worktree 환경을 설정합니다. 이는 메인 브랜치 오염을 방지하고 독립적인 개발 환경을 제공합니다.

```bash
FEATURE_SLUG=$(echo "$ARGUMENTS" | awk \'{print $1}\')

# Worktree 스크립트 경로는 플러그인 디렉토리에서 자동 탐색
PLUGIN_DIR="${PLUGIN_DIR:-$(dirname "$0")/..}"
WORKTREE_SCRIPT="${PLUGIN_DIR}/hooks/lib/worktree.sh"

if [[ -x "$WORKTREE_SCRIPT" ]]; then
  WORKTREE_OUTPUT=$("$WORKTREE_SCRIPT" setup "$FEATURE_SLUG")
  WORKTREE_PATH=$(echo "$WORKTREE_OUTPUT" | grep "Worktree created at:" | awk \'{print $NF}\')
  if [[ -n "$WORKTREE_PATH" ]]; then
    cd "$WORKTREE_PATH"
  fi
fi
```

**주의**: Worktree 내에서 모든 Git 명령(add, commit 등)을 수행해야 합니다.

이제 Worktree 내에서 `$ARGUMENTS`에서 `<feature-slug>`를 식별하고, **`docs/specs/<feature-slug>/design.md`** 파일을 읽어 구현 순서와 변경 내역을 확인합니다.

### 2. Atomic Task Planning 및 Wave Execution
`design.md`의 '구현 순서' 섹션을 기반으로, Engineer 에이전트가 2-5분 단위의 아주 작은 Atomic Task로 구현 작업을 분해합니다. 이 때, 의존성이 없는 태스크들은 그룹화하여 병렬로 실행될 수 있도록 'Wave'를 구성합니다.

#### 2.1. Atomic Task 분해 및 우선순위 지정
- `design.md`의 구현 순서를 참조하여 각 단계를 더 작은 Atomic Task로 나눕니다.
- 각 Atomic Task는 독립적으로 구현 및 테스트 가능해야 합니다.
- 태스크 간 의존성을 파악하고, 병렬 실행이 가능한 태스크들을 식별합니다.

#### 2.2. Wave Execution (병렬 실행)
- 의존성이 없는 Atomic Task들을 'Wave'로 묶어 동시에 Engineer 서브 에이전트에게 할당합니다.
- 각 Wave 내의 태스크는 독립적인 컨텍스트에서 실행됩니다.
- 모든 태스크는 RED-GREEN-REFACTOR 사이클을 따릅니다.

### 3. Wave별 RED-GREEN-REFACTOR 반복

**각 Wave 내의 Atomic Task마다:**

#### RED — 실패하는 테스트 작성
- 기대 동작을 테스트로 명세
- 테스트 이름: `should [동작] when [조건]`
- AAA 패턴: Arrange → Act → Assert

#### GREEN — 최소 코드로 통과
- 테스트를 통과시키는 최소한의 코드 작성
- 완벽함보다 동작이 목표

#### REFACTOR — 개선
- 중복 제거, 책임 분리
- 테스트 여전히 통과 확인

### 4. 커밋
각 기능 완료 시 atomic commit:
```
<type>(<scope>): <subject>
```

## 코드 품질 기준
- 함수 20줄 이하
- 순환 복잡도 10 이하
- 모든 에러 경로 처리
- 명확한 네이밍

## 출력

```
📊 구현 진행률: [X/Y] (Z%)

✅ 완료: [작업 목록]
🔄 현재: [진행 중]
⏭️ 다음: [예정]

➡️ 다음 단계: /check <feature-slug> 로 코드 검증을 시작하세요.
```
