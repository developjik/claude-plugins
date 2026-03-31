# ADR-001: 모듈형 훅 아키텍처

## 상태

수락됨 (2026-03-27)

## 맥락

Harness Engineering의 훅 시스템이 초기에는 단일 `common.sh` 파일에 모든 함수가 포함되어 있었습니다. 파일이 300줄 이상으로 성장하면서 다음 문제가 발생했습니다:

1. 유지보수 어려움
2. 함수 간 의존성 파악困难
3. 개별 기능 테스트 불가
4. 코드 충돌 빈번

## 결정

`common.sh`를 **14개 기능별 모듈**로 분리합니다:

```
hooks/lib/
├── json-utils.sh       # JSON 파싱 (Layer 0)
├── logging.sh          # 로깅 (Layer 0)
├── validation.sh       # 입력 검증 (Layer 1)
├── error-messages.sh   # 에러 메시지 (Layer 1)
├── context-rot.sh      # Context Rot 감지 (Layer 2)
├── automation-level.sh # 자동화 레벨 (Layer 2)
├── feature-registry.sh # 기능 레지스트리 (Layer 2)
├── feature-sync.sh     # 레지스트리 동기화 (Layer 3)
├── skill-chain.sh      # 스킬 체인 검증 (Layer 3)
├── wave-executor.sh    # Wave 실행 (Layer 3)
├── result-summary.sh   # 결과 요약 (Layer 3)
├── cleanup.sh          # 리소스 정리 (Layer 1)
├── doctor.sh           # 진단 유틸리티 (Layer 2)
└── worktree.sh         # Git Worktree (Layer 2)
```

## 근거

### 장점
- **단일 책임 원칙**: 각 모듈이 명확한 하나의 역할
- **테스트 용이성**: 모듈별 독립 테스트 가능
- **의존성 명확화**: `# DEPENDENCIES:` 주석으로 명시
- **확장성**: 새 기능을 별도 모듈로 추가

### 단점
- **초기 학습 곡선**: 14개 파일의 관계 이해 필요
- **파일 수 증가**: 관리 포인트 증가

## 대안

1. **단일 파일 유지**: 거부됨 - 유지보수 문제 심화
2. **클래스 기반 OOP**: 거부됨 - Bash에서 과도한 복잡성

## 결과

- `common.sh`는 모듈 로더 역할로 축소 (123줄)
- 각 모듈에 `# DEPENDENCIES:` 주석 추가
- 모듈 로드 순서가 중요해짐

## 참조

- [architecture.md](../reference/architecture.md)
- [hook-writing.md](../guides/hook-writing.md)
