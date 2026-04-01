# State Schema

로컬 상태 구조의 사람 친화적 설명은 [local-runtime-schema.md](./local-runtime-schema.md) 를 기준 문서로 봅니다.

이 문서는 짧은 엔트리 포인트만 제공합니다.

## Runtime State Paths

- `.colo-fe-flow/.state/index.json`
- `.colo-fe-flow/.state/tickets/<JIRA-KEY>.json`

## 핵심 원칙

- 전역 인덱스와 티켓별 상태를 분리합니다.
- 전역 인덱스는 얇게 유지합니다.
- 실제 제어 정보는 티켓 상태 파일에 저장합니다.
- `route-workflow`는 상태 파일과 `docs/specs/<JIRA-KEY>/` 산출물을 함께 읽습니다.

자세한 필드 설명, 예시 JSON, `tasks.json`의 역할은 [local-runtime-schema.md](./local-runtime-schema.md) 를 참고합니다.
