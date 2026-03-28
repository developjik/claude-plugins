# ADR-003: 자동화 레벨 시스템 (L0-L4)

## 상태

수락됨 (2026-03-27)

## 맥락

사용자마다 AI 자동화에 대한 신뢰도가 다릅니다:
- 초보자: 모든 단계에서 승인 원함
- 숙련자: 완전 자동화 선호
- 팀 환경: 중요 변경만 승인

## 결정

**5단계 자동화 레벨** 시스템을 도입합니다:

| 레벨 | 이름 | 동작 | 대상 |
|------|------|------|------|
| L0 | Manual | 모든 전환에 승인 필요 | 초보자, 중요 프로젝트 |
| L1 | Guided | 중요 전환만 승인 | 학습 단계 |
| L2 | Semi-Auto | 불확실할 때만 승인 | 일반 사용자 (기본값) |
| L3 | Auto | 품질 게이트만 통과하면 자동 | 숙련자 |
| L4 | Full-Auto | 완전 자동 | 매우 숙련된 사용자 |

## 설정

```yaml
# .harness/config.yaml
automation:
  level: L2
  overrides:
    destructive_operations: L0  # 파괴적 작업은 항상 수동
```

## 근거

### 장점
- **점진적 신뢰 구축**: 사용자가 편안한 수준에서 시작
- **팀 표준화**: 팀별로 일관된 자동화 수준
- **위험 관리**: 파괴적 작업은 별도 설정

### 단점
- **설정 복잡성**: 추가 구성 파일 필요
- **일관성 유지**: 레벨 간 동작 차이 설명 필요

## 결과

- 기본값 L2로 설정
- `automation-level.sh` 모듈로 구현
- Context Rot 점수와 연동 가능

## 참조

- [automation-level.sh](../../hooks/lib/automation-level.sh)
- [ARTIFACT-CONVENTION.md](../ARTIFACT-CONVENTION.md)
