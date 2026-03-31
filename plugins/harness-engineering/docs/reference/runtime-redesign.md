# 런타임 재설계 초안

2026-03-30 기준으로, Harness Engineering의 핵심 실행 로직은 여전히 Bash 중심입니다. 이 문서는 대형 Bash 모듈의 책임 경계를 재정의하고, 어디까지 Bash로 유지하고 어디부터 보조 런타임으로 분리할지에 대한 초안을 정리합니다.

현재 상태:

- Phase 1(Bash 내부 분해) 기준 `wave-executor.sh`는 `wave-graph.sh`, `wave-runner.sh`, `wave-executor.sh` facade 구조로 1차 분리됨
- Phase 2 기준 `scripts/runtime/wave_plan.py`, `hooks/__tests__/fixtures/wave-planner/` golden fixture 계약 테스트가 추가됨
- Phase 3 기준으로 planner rollout policy와 backend boundary guard가 고정됨: 기본은 `HARNESS_WAVE_PLANNER=auto`, `python`은 strict, `bash`는 legacy fallback이며, 새 direct backend caller는 validate에서 차단됨
- `review-engine.sh`는 `review-evidence.sh`, `scripts/runtime/review_normalize.py`, `scripts/runtime/review_score.py`로 Stage 1 evidence matcher와 Stage 2 정규화/가중 점수 계산을 분리했고, Bash facade/fallback을 유지함
- `skill-evaluation.sh`는 `skill-metrics.sh`, `skill-scoring.sh`, `skill-report.sh`로 1차 분리되어, facade는 공개 API와 helper 로드만 유지함
- `state-machine.sh`는 `state-store.sh`, `phase-cache.sh`, `snapshot-store.sh`로 1차 분리되어, facade는 락/가드/전환 orchestration에 집중함
- `subagent-spawner.sh`는 `subagent-request.sh`, `subagent-collect.sh`, `subagent-finalize.sh`로 1차 분리되어, facade는 공통 경로/유틸과 공개 함수명만 유지함
- `lsp-tools.sh`는 `lsp-diagnostics.sh`, `lsp-symbols.sh`로 1차 분리되어, facade는 공개 LSP API와 fallback 제어만 유지함
- `crash-recovery.sh`는 `crash-detection.sh`, `crash-report.sh`로 1차 분리되어, facade는 복구 실행/체크포인트 생성만 유지함
- `browser-controller.sh`는 `browser-state.sh`, `browser-session.sh`, `browser-actions.sh`로 1차 분리되어, facade는 CLI/debug와 helper 로드만 유지함
- `browser-testing.sh`는 `browser-test-runner.sh`, `browser-test-report.sh`로 1차 분리되어, facade는 전체 suite orchestration만 유지함
- `test-runner.sh`는 `test-detection.sh`, `test-results.sh`로 1차 분리되어, facade는 실행/재시도/커버리지만 유지함

## 1. 현재 구조와 우선순위

`hooks/lib/*.sh` 기준 상위 대형 모듈은 다음과 같습니다.

| 모듈 | LOC | 현재 책임 | 우선순위 | 방향 |
|------|-----|-----------|----------|------|
| `skill-evaluation.sh` | 38 | skill evaluation facade, helper 로드, 공개 API 유지 | 완료 | 1차 분해 완료 |
| `review-engine.sh` | 1053 | 리뷰 orchestration, 결과 저장, helper fallback 제어 | 중간 | facade 유지, 추가 분해보다 helper 안정화 우선 |
| `review-evidence.sh` | 691 | FR/파일/API/config evidence 매칭, Stage 1 점수 입력 생성 | 중간 | Bash helper 유지, 필요 시 문자열/구조 파싱만 후속 이전 |
| `state-machine.sh` | 1151 | phase/state 기록, 스냅샷, 롤백, 락, 캐시 동기화 | 높음 | 단기 분해 우선, 보조 런타임 이전은 후순위 |
| `subagent-spawner.sh` | 1071 | 태스크/컨텍스트 작성, 실행 계약, 결과 수집, 집계 | 중간 | 계약은 유지, 집계/정규화 보조 모듈화 가능 |
| `wave-executor.sh` | 966 | DAG 분석, wave 계획, 실행, 대기, 결과 집계 | 가장 높음 | 첫 분해 대상으로 선정 |
| `lsp-tools.sh` | 925 | LSP 진단 수집, 포맷 변환, 파일 캐시 | 중간 | 출력 파서만 별도 분리 가능 |

우선순위 기준은 다음 네 가지입니다.

- 순수 데이터 처리 비중이 높은가
- 훅/프로세스 제어와의 결합도가 낮은가
- JSON 입출력 계약으로 고립시키기 쉬운가
- 기존 테스트로 회귀를 빠르게 검출할 수 있는가

현재 남은 공식 실행 항목은 없습니다. 이후는 선택적 후속 backlog이며, ROI가 큰 후보는 `review-evidence.sh`, `task-format.sh`, `verification-classes.sh`입니다.

## 2. 경계 원칙

장기 구조는 `Bash control plane + helper runtime` 형태로 가져갑니다.

### Bash에 남길 책임

- Claude Code 훅 진입점 (`hooks/*.sh`)
- 환경 변수, 경로, 파일 배치, `.harness/` 디렉터리 관리
- 외부 프로세스 실행과 종료 코드 전파
- 간단한 안전 장치와 fallback

### 보조 런타임으로 옮길 책임

- DAG 분석, 위상 정렬, 파동(wave) 계산
- JSON 정규화, 점수 계산, 대량 문자열/구조 파싱
- golden input/output으로 검증 가능한 순수 함수형 로직

### 권장 보조 런타임

1차 권장은 `Python 3`입니다.

- 추가 패키지 매니저 없이 macOS/Linux/CI에서 다루기 쉽습니다.
- JSON, 파일, 그래프 처리 코드가 Bash보다 훨씬 읽기 쉽습니다.
- TypeScript보다 bootstrap 비용이 낮고, 현재 저장소의 Bash 훅 구조와 연결하기 쉽습니다.

TypeScript는 이후 외부 API 연동이나 richer tooling이 필요할 때 선택지로 남깁니다. 현재 단계에서는 `Node/npm` 의존을 새로 강제하는 이점이 크지 않습니다.

## 3. 1차 분해 대상: `wave-executor.sh`

### 선정 이유

- 입력과 출력이 이미 JSON/YAML 중심입니다.
- 최근 `topological_sort`, `group_tasks_into_waves`, `execute_wave` 회귀 테스트가 보강되어 있습니다.
- 훅 라이프사이클보다는 순수 계획 수립 로직 비중이 큽니다.
- 실패 시에도 Bash fallback을 남기기 쉽습니다.

### 현재 구조

```text
hooks/lib/wave-executor.sh      # 공개 진입점, task loading, facade
hooks/lib/wave-graph.sh         # Bash graph helpers
hooks/lib/wave-runner.sh        # subagent spawn/wait/aggregate
scripts/runtime/wave_plan.py    # 기본 planner (Python)
hooks/__tests__/wave-execution-p2.test.sh
hooks/__tests__/wave-plan-contract.test.sh
```

### 단계별 계획

#### Phase 1. Bash 내부 분해

상태: 완료

- `resolve_task_dependency_layers`, `topological_sort`, `group_tasks_into_waves`, `detect_circular_dependencies`를 `wave-graph.sh`로 이동
- `execute_wave`, `finalize_wave`, `execute_all_waves`를 `wave-runner.sh`로 이동
- 기존 `wave-executor.sh`는 하위 모듈 로드와 facade 역할만 유지

완료 조건:

- 기존 공개 함수 이름은 유지
- `hooks/__tests__/wave-execution-p2.test.sh`가 수정 없이 통과

#### Phase 2. Python planner 추가

상태: 완료

- `scripts/runtime/wave_plan.py`에 다음 기능 구현
  - 입력 검증
  - 중복 ID / 누락 의존성 검출
  - 위상 정렬
  - wave 계산
  - 순환 의존성 리포트
- Bash는 planner 호출 후 JSON만 사용
- `HARNESS_WAVE_PLANNER=python|bash` feature flag 추가
- `wave-plan-contract.test.sh`와 `hooks/__tests__/fixtures/wave-planner/`로 Bash/Python parity 및 Python CLI contract 검증 추가

완료 조건:

- 동일 입력에서 Bash planner와 Python planner가 같은 JSON shape를 반환
- CI에서 planner parity 테스트 통과

#### Phase 3. Bash planner 축소

상태: 완료

- 기본 모드는 `HARNESS_WAVE_PLANNER=auto`
  - Python planner를 우선 사용
  - `python3` 미설치, planner script 누락, 비정상 종료, 비계약(JSON shape 외) 오류 시 Bash planner로 fallback
- `HARNESS_WAVE_PLANNER=python`
  - strict mode
  - Python planner 오류를 그대로 surface하여 rollout/debug에 사용
- `HARNESS_WAVE_PLANNER=bash`
  - legacy forced mode
  - 운영 중 emergency fallback 또는 비교 실험에 사용
- 문서와 테스트는 Python contract 중심으로 유지하되, Bash fallback 회귀 테스트를 계속 보존
- `scripts/validate.sh`에서 planner backend direct-call boundary를 검사
  - 허용 파일은 `hooks/lib/wave-graph.sh`, `hooks/__tests__/wave-plan-contract.test.sh`, `scripts/validate.sh`
  - 운영 코드에서 새 direct backend caller가 추가되면 validate가 실패

완료 조건:

- 기본 `auto` 모드가 CI와 로컬 validate에서 안정적으로 통과
- strict `python` 모드에서 planner infra 오류가 즉시 드러남
- Bash planner는 fallback 경로로만 남고 직접 호출 지점이 더 이상 늘지 않음

다음 우선순위:

- `skill-evaluation.sh`의 점수 계산과 추천/경고 생성을 별도 helper 경계로 분리

### 권장 JSON 계약

입력:

```json
{
  "tasks": [
    {"id": "task-a", "file": "docs/specs/foo/task-a.md", "dependencies": []}
  ]
}
```

출력 성공:

```json
{
  "ok": true,
  "order": ["task-a"],
  "waves": [["task-a"]],
  "validation": {
    "valid": true,
    "duplicate_ids": [],
    "missing_dependencies": []
  },
  "unresolved": []
}
```

출력 실패:

```json
{
  "ok": false,
  "error": "circular_dependency",
  "order": ["task-a"],
  "waves": [["task-a"]],
  "unresolved": [
    {"id": "task-b", "dependencies": ["task-c"]}
  ]
}
```

## 4. 후속 분해 대상

### `review-engine.sh`

권장 분해:

- Bash 유지:
  - 문서 경로 탐색
  - 서브에이전트 spawn/collect orchestration
  - `.harness/review/` 저장 경로 관리
- 분리 대상:
  - FR evidence matcher
  - quality result normalizer
  - score calculator

권장 구조:

```text
hooks/lib/review-engine.sh           # facade + orchestration
hooks/lib/review-evidence.sh         # Bash evidence collection
scripts/runtime/review_normalize.py  # score/issue normalization
scripts/runtime/review_score.py      # weighted scoring
```

비고:

- Stage 1 evidence matcher는 `review-evidence.sh`, Stage 2 결과 정규화/가중 점수 계산은 Python helper로 분리했습니다.
- `review-engine.sh`는 전체 리뷰 orchestration과 파일 계약, fallback 제어를 유지합니다.
- 다음 단계는 matcher가 더 복잡해질 때 문자열/구조 파싱 일부만 helper runtime으로 옮기는 것입니다.

### `skill-evaluation.sh`

권장 분해:

- 단기:
  - `skill-metrics.sh`: 메트릭 기록, 통계 조회, export/cleanup
  - `skill-scoring.sh`: 점수 계산, 랭킹, 이상 탐지
  - `skill-report.sh`: dashboard, weekly report, recommendations
- 중기:
  - 점수/추천 정책이 더 복잡해지면 순수 계산 로직 일부를 Python helper로 이동

비고:

- Phase 1은 완료되었습니다. 현재 `skill-evaluation.sh`는 facade만 유지하고, 기록/집계, 점수 계산, 리포트 생성은 하위 Bash 모듈로 분리했습니다.
- 다음 단계는 정책이 커질 때 `skill-scoring.sh`의 순수 계산 영역만 helper runtime으로 옮기는 것입니다.

### `state-machine.sh`

권장 분해:

- 단기:
  - `state-store.sh`: state.json 읽기/쓰기
  - `snapshot-store.sh`: 스냅샷/복원
  - `phase-cache.sh`: current-agent/current-feature/pdca-phase 캐시 동기화
- 중기:
  - snapshot diff나 forensic summary처럼 계산량이 있는 부분만 Python helper로 이동

비고:

- 이 모듈은 trap, lock, 훅 라이프사이클과 강하게 결합되어 있어 첫 번째 보조 런타임 이전 대상으로는 부적합합니다.
- Phase 1은 완료되었습니다. 현재 `state-machine.sh`는 lock, guard, transition orchestration만 유지하고, state/cache/snapshot 책임은 하위 Bash 모듈로 분리했습니다.
- 다음 단계는 snapshot diff나 forensic summary처럼 순수 계산량이 있는 영역만 별도 helper로 옮기는 것입니다.

### `subagent-spawner.sh`

권장 분해:

- 단기:
  - `subagent-request.sh`: task/context 준비, execution request 생성, 실행 시작
  - `subagent-collect.sh`: adapter result 정규화, 상태 조회, 집계, 대기
  - `subagent-finalize.sh`: terminal 상태 기록, result/failure artifact 작성, cleanup
- 중기:
  - 결과 정규화/집계 포맷이 더 복잡해지면 일부를 Python helper로 이동

비고:

- Phase 1은 완료되었습니다. 현재 `subagent-spawner.sh`는 공통 경로/유틸과 facade 역할만 유지하고, lifecycle 단계별 구현은 하위 Bash 모듈로 분리했습니다.
- 다음 단계는 aggregate/normalization이 더 복잡해질 때 JSON 중심 로직만 helper runtime으로 옮기는 것입니다.

### `lsp-tools.sh`

권장 분해:

- 단기:
  - `lsp-diagnostics.sh`: 언어별 진단 파서, 프로젝트 진단 요약, 리포트 렌더링
  - `lsp-symbols.sh`: 심볼 추출, location/workspace edit 포맷 변환
- 중기:
  - JSON 기반 parser가 더 복잡해지면 일부를 Python helper로 이동

비고:

- Phase 1은 완료되었습니다. 현재 `lsp-tools.sh`는 공개 LSP API와 fallback 제어만 유지하고, 출력 파싱/포맷 변환은 하위 Bash 모듈로 분리했습니다.
- 다음 단계는 `review-engine.sh`의 FR evidence matcher처럼 순수 구조 매칭 로직을 별도 helper로 분리하는 것입니다.

### `browser-testing.sh`

권장 분해:

- 단기:
  - `browser-test-runner.sh`: 프레임워크 감지, 테스트 실행, Playwright/Cypress 결과 파싱
  - `browser-test-report.sh`: HTML 리포트 생성, 테스트 히스토리 조회, 오래된 결과 정리
- 중기:
  - runner가 다루는 통계/출력 정규화가 더 복잡해지면 일부를 helper runtime으로 이동

비고:

- Phase 1은 완료되었습니다. 현재 `browser-testing.sh`는 전체 suite orchestration만 유지하고, 시나리오 실행과 리포트/히스토리 책임은 하위 Bash 모듈로 분리했습니다.
- 다음 단계는 `test-runner.sh`처럼 다중 프레임워크 감지와 명령 합성 로직이 큰 모듈을 같은 패턴으로 쪼개는 것입니다.

### `test-runner.sh`

권장 분해:

- 단기:
  - `test-detection.sh`: 프레임워크 감지, 패키지 매니저 판별, 실행 명령 합성
  - `test-results.sh`: 프레임워크별 결과 파싱, 성공률 계산, 요약 출력
- 중기:
  - 통계 계산과 커버리지 집계가 더 복잡해지면 일부를 helper runtime으로 이동

비고:

- Phase 1은 완료되었습니다. 현재 `test-runner.sh`는 실행/재시도/커버리지만 유지하고, 감지/명령 합성과 결과 파싱/요약은 하위 Bash 모듈로 분리했습니다.
- 다음 단계는 `skill-evaluation.sh`처럼 점수 계산과 요약 출력이 큰 모듈을 같은 방식으로 쪼개는 것입니다.

### `crash-recovery.sh`

권장 분해:

- 단기:
  - `crash-detection.sh`: stuck/loop 판정, 이슈 진단, 복구 옵션 계산
  - `crash-report.sh`: 크래시 분석, 포렌식 리포트 생성, 복구 옵션 목록 출력
- 중기:
  - 로그/트랜지션 포렌식이 더 복잡해지면 일부 JSON 분석을 helper runtime으로 이동

비고:

- Phase 1은 완료되었습니다. 현재 `crash-recovery.sh`는 복구 실행/체크포인트 생성만 유지하고, 상태/로그 판정과 리포트 생성은 하위 Bash 모듈로 분리했습니다.
- 다음 단계는 `skill-evaluation.sh`처럼 점수/추천 계산이 큰 모듈을 같은 패턴으로 나누는 것입니다.

## 5. 테스트 전략

- 기존 회귀 테스트 유지: `state-machine.test.sh`, `review-engine.test.sh`, `wave-execution-p2.test.sh`
- 새 contract 테스트 추가:
  - golden JSON input/output
  - Bash planner와 Python planner parity 비교
  - failure shape 검증 (`invalid_dependency_graph`, `circular_dependency`)
- `scripts/validate.sh --quick`에는 contract smoke test 포함
- `scripts/validate.sh --full`에는 parity + 기존 회귀 테스트 모두 포함

## 6. 호환성 리스크와 완화책

| 리스크 | 설명 | 완화책 |
|--------|------|--------|
| Python 3 부재 | 일부 환경에서 `python3`가 없을 수 있음 | Bash fallback 유지, validate에서 명시적 경고 |
| JSON shape drift | Bash/Python 결과 형식이 달라질 수 있음 | golden fixture + parity test 고정 |
| 상태 파일 불일치 | planner/runner 분리 과정에서 `.harness/` 상태가 어긋날 수 있음 | facade는 유지, 상태 기록은 Bash만 담당 |
| 디버깅 복잡도 증가 | 런타임이 둘로 나뉘면 문제 지점이 늘어남 | helper는 pure function + stdin/stdout contract로 제한 |
| 리팩터링 범위 과대화 | 한 번에 여러 모듈을 옮기면 회귀 위험 증가 | `wave-executor` 선행 후 `review-engine`, 마지막으로 `state-machine` |

## 7. 권장 실행 순서

1. `wave-executor.sh`를 Bash 내부 모듈 둘로 분해하고 planner parity를 고정
2. `review-engine.sh`의 normalization/scoring 로직 분리
3. `state-machine.sh`를 store/cache/snapshot 단위로 Bash 내부 분해
4. `subagent-spawner.sh`를 request/collect/finalize 단위로 Bash 내부 분해
5. `lsp-tools.sh`의 출력 파서/포맷 변환을 순수 helper 경계로 분리
6. `review-engine.sh`의 FR evidence matcher를 `review-evidence.sh`로 분리
7. `browser-controller.sh`의 세션 상태 관리와 페이지 액션 브리지를 helper로 분리
8. `browser-testing.sh`의 시나리오 실행과 리포트/히스토리 관리를 helper로 분리
9. `test-runner.sh`의 프레임워크 감지/명령 합성과 결과 요약을 helper로 분리
10. `crash-recovery.sh`의 세션/로그 판정과 복구 가이드 생성을 helper로 분리
11. `skill-evaluation.sh`의 점수 계산과 추천/경고 생성을 helper 경계로 분리

현재 기준으로는 1~11단계가 완료되었고, 공식 리팩터링 로드맵은 완료되었습니다.
