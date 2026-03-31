# ADR-002: 보안 강화 3단계 전략

## 상태

수락됨 (2026-03-27)

## 링락

AI 어시스턴트가 Bash 명령어와 파일 시스템에 접근할 때 다음 보안 위험이 존재합니다:

1. **명령어 인젝션**: `$(...)`, 백틱, `;`, `&&`, `||`
2. **경로 순회**: `../`를 통한 프로젝트 외부 접근
3. **JSON 인젝션**: 로그/에러 메시지의 특수 문자

## 결정

**3단계 보안 강화** 전략을 채택합니다:

### Phase 1 (P0): 긴급 수정
- JSON 이스케이프 (`escape_json_string()`)
- 명령어 체이닝 차단 (`&&`, `||`, `;`)
- 하드코딩 경로 제거

### Phase 2 (P1): Fail-safe 처리
- jq 미설치 시 `return 1` (fail-safe)
- 에러 메시지 JSON 이스케이프
- 화이트리스트 접미사 `/` 차단

### Phase 3 (P2): 기능 완성
- Wave 실행기 완성
- 모듈 의존성 명시화
- 로깅 표준화

## 근거

### 보안 원칙
- **Fail-safe**: 의존성 부재 시 안전하게 실패
- **Defense in depth**: 다층 보안 검증
- **Explicit over implicit**: 명시적 차단 패턴

### 위험 평가
| 공격 벡터 | 차단 방법 |
|-----------|-----------|
| `rm -rf /` | 블랙리스트 + 화이트리스트 |
| `$(whoami)` | 명령어 치환 패턴 감지 |
| `../../../etc/passwd` | 경로 순회 패턴 감지 |
| `"key":"value"` | JSON 이스케이프 |

## 결과

- 30개 보안 테스트 통과
- 34개 검증 항목 통과
- 아키텍처 건전성 8.3/10 → 8.5/10

## 참조

- [validation.sh](../../hooks/lib/validation.sh)
- [error-messages.sh](../../hooks/lib/error-messages.sh)
- [security.test.sh](../../hooks/__tests__/security.test.sh)
