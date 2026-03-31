# Automation Levels 설정 가이드

## config.yaml 예시

```yaml
# .harness/config.yaml

automation:
  # 현재 자동화 레벨 (L0-L4)
  level: L2

  # 기본 자동화 레벨 (새 프로젝트 생성 시)
  default_level: L2

trust:
  # 신뢰 점수 시스템 활성화
  enabled: true

  # 신뢰 점수 기반 자동 레벨 상향 조정
  auto_escalation: false

  # 신뢰 점수 기반 자동 레벨 하향 조정
  auto_downgrade: true

  # 레벨 상향 임계값 (신뢰 점수 >= 이 값이면 레벨 상향)
  escalation_threshold: 0.8

  # 레벨 하향 임계값 (신뢰 점수 < 이 값이면 레벨 하향)
  downgrade_threshold: 0.3
```

## 자동화 레벨 설명

| 레벨 | 이름 | Plan→Design | Design→Do | Do→Check | Check→Wrapup | 추천 대상 |
|:----:|:-----|:-----------:|:---------:|:--------:|:------------:|:----------|
| L0 | Manual | 승인 | 승인 | 승인 | 승인 | 초보자, 중요 프로젝트 |
| L1 | Guided | 승인 | 승인 | 승인 | 자동 | 학습 단계 |
| L2 | Semi-Auto | 불확실시 승인 | 자동 | 자동 | 자동 | 일반 사용자 (기본값) |
| L3 | Auto | 자동 | 자동 | 게이트 | 자동 | 숙련자 |
| L4 | Full-Auto | 자동 | 자동 | 자동 | 자동 | 매우 숙련된 사용자 |

## 신뢰 점수 구성

```
trust_score = (track_record × 0.25)
            + (quality_metrics × 0.20)
            + (velocity × 0.15)
            + (user_ratings × 0.20)
            + (decision_accuracy × 0.10)
            + (safety × 0.10)
```

| 점수 범위 | 추천 레벨 |
|:---------:|:---------:|
| 0.0 - 0.3 | L0 |
| 0.3 - 0.5 | L1 |
| 0.5 - 0.7 | L2 |
| 0.7 - 0.85 | L3 |
| 0.85 - 1.0 | L4 |

## 설정 변경 방법

1. `.harness/config.yaml` 파일 열기
2. `automation.level` 값을 L0~L4 중 하나로 변경
3. 다음 세션부터 새 레벨이 적용됨

```bash
# 예: L3으로 변경
sed -i '' 's/level: L2/level: L3/' .harness/config.yaml
```
