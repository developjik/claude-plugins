# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [1.5.0] - 2026-03-29

### Added (P2 Advanced Features)
- **Hash-Anchored Edit (P2-1)**: 파일 해시 기반 충돌 방지 시스템
  - `hooks/lib/hash-anchored-edit.sh`: 파일 무결성 검증 및 충돌 감지
  - `register_file_hash()`: 파일 등록 및 해시 저장
  - `verify_file_integrity()`: 무결성 검증
  - `prepare_edit()`: 편집 준비 (충돌 감지)
  - `finalize_edit()`: 편집 완료 및 해시 갱신
- **Wave Execution (P2-2)**: 의존성 기반 병렬 태스크 실행
  - `hooks/lib/wave-executor.sh`: 웨이브 실행 라이브러리
  - `topological_sort()`: 위상 정렬로 의존성 해결
  - `group_tasks_into_waves()`: 병렬 실행 가능한 태스크 그룹화
  - `detect_circular_dependencies()`: 순환 의존성 감지
  - `execute_wave()`: 웨이브 단위 병렬 실행

### Fixed (POSIX Compatibility)
- **Bash 3.2 macOS 호환성**: 기본 쉘에서도 동작하도록 수정
  - bash 4.0+ associative arrays → POSIX-compatible alternatives
  - BSD/GNU sed 호환성 해결 (`sed -i ''` vs `sed -i`)
  - subshell 변수 scope 문제 해결
  - `grep -oP` → POSIX-compatible alternatives (`awk`, `sed`)
- **테스트 호환성**: 모든 테스트가 bash 3.2에서 통과하도록 수정

### Changed
- P0/P1/P2 기능들이 `docs/features.md` 레지스트리에 등록됨
  - `p0-foundation` (Completed)
  - `p1-enhancement` (Completed)
  - `p2-advanced` (Completed)

## [1.4.0] - 2026-03-27

### Added
- **Clarify Skill (PDCA 0단계)**: 사용자 요청 구체화 스킬
  - 소크라테스식 질문으로 모호성 해소
  - 요청 유형 분류 및 모호성 점수 산정
  - 대안 탐색 (2-3개 접근 방식 비교)
  - Gray Areas 식별 (Visual/API/Content)
  - 자동화 레벨(L0-L4)에 따른 질문 깊이 조절
  - `docs/specs/<feature-slug>/clarify.md` 산출물 생성
- **Clarify Template**: `docs/templates/clarify.md` 템플릿 추가
- **Wave Execution System**: 독립 태스크 병렬 실행 시스템
  - `docs/WAVE-SYSTEM.md`: Wave 실행 가이드
  - `hooks/lib/wave-executor.sh`: Wave 실행 라이브러리
  - `tasks/` 디렉토리: Atomic Task 저장소
  - waves.yaml 형식: Wave 정의 포맷
  - 의존성 그래프 기반 병렬 실행
  - 성능 향상: 최대 60% 시간 단축

### Changed
- `skills/plan/SKILL.md`: clarify.md 참조 로직 추가
  - clarify.md 존재 시 자동 로드하여 Plan 작성에 활용
  - clarify.md 없을 시 실행 여부 확인
- `skills/fullrun/SKILL.md`: Clarify 단계 추가 (5단계 → 6단계)
  - Clarify → Plan → Design → Do → Check → Wrap-up
- `skills/harness/SKILL.md`: clarify 명령어 추가
  - `/harness clarify <기능 설명>` 진입점 추가
  - PDCA 흐름에 Clarify 단계 추가
- `skills/implement/SKILL.md`: Wave 실행 옵션 추가
  - `--waves`: Wave 병렬 실행 모드
  - `--wave N`: 특정 Wave만 실행
  - `--dry-run`: 실행 계획만 확인

### Improved (Phase 1 Quick Wins)
- **common.sh 모듈화**: 700줄 파일을 5개 모듈로 분리
  - `hooks/lib/json-utils.sh`: JSON 파싱 유틸리티
  - `hooks/lib/context-rot.sh`: Context Rot 감지 및 관리
  - `hooks/lib/automation-level.sh`: 자동화 레벨 (L0-L4)
  - `hooks/lib/feature-registry.sh`: 기능 레지스트리 관리
  - `hooks/lib/logging.sh`: 구조화된 로깅 (JSONL)
- **보안 필터링 강화**: 화이트리스트 + 블랙리스트 이중 검증
  - 30개 위험 패턴 블랙리스트 추가
  - 15개 의심 패턴 로깅
  - 10개 안전 명령어 화이트리스트
- **구조화된 로깅**: JSONL 형식 + 트레이스 ID
  - `generate_trace_id()`: 세션 추적 ID 생성
  - `mask_sensitive_data()`: 민감 정보 마스킹
  - `log_event()`: JSONL 로그 기록
- **테스트 프레임워크**: BATS 스타일 단위 테스트 추가
  - `hooks/__tests__/common.test.sh`: 34개 테스트 케이스

### Improved (Phase 2 Quick Wins)
- **Quick Start 가이드**: `docs/QUICKSTART.md` 추가
  - 5분 안에 핵심 워크플로우 체험
  - `/fullrun` 예제
  - 자동화 레벨 설명
- **validate.sh 확장**: 8단계 검증
  - Plugin Manifest 검증
  - Hooks 문법 검사
  - Skills frontmatter 검증
  - Agents 검증
  - Templates 확인
  - 단위 테스트 실행
  - Claude Plugin 검증
  - 소크라테스식 질문으로 모호성 해소
  - 요청 유형 분류 및 모호성 점수 산정
  - 대안 탐색 (2-3개 접근 방식 비교)
  - Gray Areas 식별 (Visual/API/Content)
  - 자동화 레벨(L0-L4)에 따른 질문 깊이 조절
  - `docs/specs/<feature-slug>/clarify.md` 산출물 생성
- **Clarify Template**: `docs/templates/clarify.md` 템플릿 추가

### Changed
- `skills/plan/SKILL.md`: clarify.md 참조 로직 추가
  - clarify.md 존재 시 자동 로드하여 Plan 작성에 활용
  - clarify.md 없을 시 실행 여부 확인
- `skills/fullrun/SKILL.md`: Clarify 단계 추가 (5단계 → 6단계)
  - Clarify → Plan → Design → Do → Check → Wrap-up
- `skills/harness/SKILL.md`: clarify 명령어 추가
  - `/harness clarify <기능 설명>` 진입점 추가
  - PDCA 흐름에 Clarify 단계 추가

### Improved (Phase 1 Quick Wins)
- **common.sh 모듈화**: 700줄 파일을 5개 모듈로 분리
  - `hooks/lib/json-utils.sh`: JSON 파싱 유틸리티
  - `hooks/lib/context-rot.sh`: Context Rot 감지 및 관리
  - `hooks/lib/automation-level.sh`: 자동화 레벨 (L0-L4)
  - `hooks/lib/feature-registry.sh`: 기능 레지스트리 관리
  - `hooks/lib/logging.sh`: 구조화된 로깅 (JSONL)
- **보안 필터링 강화**: 화이트리스트 + 블랙리스트 이중 검증
  - 30개 위험 패턴 블랙리스트 추가
  - 15개 의심 패턴 로깅
  - 10개 안전 명령어 화이트리스트
- **구조화된 로깅**: JSONL 형식 + 트레이스 ID
  - `generate_trace_id()`: 세션 추적 ID 생성
  - `mask_sensitive_data()`: 민감 정보 마스킹
  - `log_event()`: JSONL 로그 기록
- **테스트 프레임워크**: BATS 스타일 단위 테스트 추가
  - `hooks/__tests__/common.test.sh`: 33개 테스트 케이스
  - 소크라테스식 질문으로 모호성 해소
  - 요청 유형 분류 및 모호성 점수 산정
  - 대안 탐색 (2-3개 접근 방식 비교)
  - Gray Areas 식별 (Visual/API/Content)
  - 자동화 레벨(L0-L4)에 따른 질문 깊이 조절
  - `docs/specs/<feature-slug>/clarify.md` 산출물 생성
- **Clarify Template**: `docs/templates/clarify.md` 템플릿 추가

### Changed
- `skills/plan/SKILL.md`: clarify.md 참조 로직 추가
  - clarify.md 존재 시 자동 로드하여 Plan 작성에 활용
  - clarify.md 없을 시 실행 여부 확인
- `skills/fullrun/SKILL.md`: Clarify 단계 추가 (5단계 → 6단계)
  - Clarify → Plan → Design → Do → Check → Wrap-up
- `skills/harness/SKILL.md`: clarify 명령어 추가
  - `/harness clarify <기능 설명>` 진입점 추가
  - PDCA 흐름에 Clarify 단계 추가

### References
- Inspired by: [Superpowers brainstorming](https://github.com/obra/superpowers)
- Inspired by: [gstack /office-hours](https://github.com/garrytan/gstack)
- Inspired by: [GSD /gsd:discuss-phase](https://github.com/gsd-build/get-shit-done)
- Inspired by: [bkit /pdca pm](https://github.com/popup-studio-ai/bkit-claude-code)
- Inspired by: [Oh My OpenAgent Prometheus](https://github.com/code-yeongyu/oh-my-openagent)

## [1.3.0] - 2026-03-25

### Added
- **CSO (Claude Search Optimization)**: 스킬 description 검색 최적화
  - 9개 스킬 SKILL.md frontmatter description 개선
  - 트리거 키워드, 에러 메시지 패턴, 한/영 동의어 추가
  - 150단어 이내 토큰 효율성 유지

### Changed
- `skills/*/SKILL.md`: 모든 스킬 description에 CSO 패턴 적용
  - plan, design, implement, check, wrapup, harness, debug, fullrun, grill-me

### References
- Based on: [Superpowers CSO](https://github.com/obra/superpowers)

## [1.2.0] - 2026-03-25

### Added
- **Context Rot Prevention (Fresh Context)**: 긴 세션에서 컨텍스트 품질 저하 감지 및 관리
  - 복합 지표 기반 점수 계산 (토큰 40% + 작업 30% + 시간 30%)
  - 3단계 등급 시스템 (healthy / caution / rot)
  - 5초 TTL 캐시로 성능 최적화
  - JSONL 이벤트 로그 기록
- **11 Context Rot Functions**: `hooks/common.sh`에 추가
  - `record_session_start()`, `increment_tool_call_count()`
  - `calculate_context_rot()`, `get_context_rot_score()`, `get_context_rot_grade()`
  - `should_use_subagent()`, `log_context_rot_event()`
  - `get_tool_call_count()`, `get_session_duration_minutes()`
  - `reset_context_rot_state()`
- **Context Templates**: 서브에이전트 전달용 템플릿
  - `docs/templates/context/PROJECT.md`: 프로젝트 컨텍스트
  - `docs/templates/context/STATE.md`: 현재 상태 요약
  - `docs/templates/context/README.md`: 사용 가이드

### Changed
- `hooks/common.sh`: Context Rot 감지 함수 11개 추가 (+254줄)
- `hooks/session-start.sh`: 세션 초기화 로직 추가 (+15줄)
- `hooks/post-tool.sh`: 도구 호출 추적 로직 추가 (+28줄)
- `README.md`: Context Rot 섹션 추가

### Dependencies
- Requires: `automation-levels` (v1.1.0)

## [1.1.0] - 2026-03-25

### Added
- **Automation Levels (L0-L4)**: PDCA 워크플로우 자동화 정도를 5단계로 조절 가능
  - L0 (Manual): 모든 전환에 승인 필요
  - L1 (Guided): 중요 전환만 승인
  - L2 (Semi-Auto): 불확실할 때만 승인 (기본값)
  - L3 (Auto): 품질 게이트만 통과하면 자동
  - L4 (Full-Auto): 완전 자동
- **Trust Score System**: 6개 지표 기반 신뢰 점수 시스템
  - track_record (0.25): 과거 성공률
  - quality_metrics (0.20): 코드 품질 점수
  - velocity (0.15): 작업 속도
  - user_ratings (0.20): 사용자 평가
  - decision_accuracy (0.10): 결정 정확도
  - safety (0.10): 안전 위반 없음
- **Decision Logging**: 모든 PDCA 전환 결정을 JSONL로 기록
- **Recommended Level**: 신뢰 점수 기반 추천 레벨 제공

## [1.0.0] - 2025-01-15

### Added
- Initial release
- 6 specialized agents (strategist, architect, engineer, guardian, librarian, debugger)
- 9 execution skills (plan, design, implement, check, wrapup, harness, debug, fullrun, grill-me)
- Hook automation system (security, backup, logging, state tracking)
- PDCA 5-stage workflow with automatic iteration
- Feature registry and dependency management
- File conflict detection
