# 프로젝트 컨텍스트 템플릿

> 이 파일을 `.harness/context/PROJECT.md`에 복사하여 프로젝트 정보를 기록하세요.

## 프로젝트명

[프로젝트 이름]

## 한 줄 설명

[프로젝트를 한 문장으로 설명]

## 기술 스택

| 구분 | 기술 |
|:-----|:-----|
| 언어 | [예: TypeScript, Python, Go] |
| 프레임워크 | [예: Next.js, FastAPI, Gin] |
| 데이터베이스 | [예: PostgreSQL, MongoDB, Redis] |
| 클라우드 | [예: AWS, GCP, Azure] |

## 디렉토리 구조

```
project-root/
├── src/           # 소스 코드
├── tests/         # 테스트 파일
├── docs/          # 문서
├── scripts/       # 스크립트
└── .harness/      # 런타임 상태 (git 제외)
```

## 코딩 컨벤션

- [컨벤션 1: 예 - 함수명은 camelCase]
- [컨벤션 2: 예 - 파일명은 kebab-case]
- [컨벤션 3: 예 - 테스트는 .test.ts 확장자]

## 주요 진입점

| 파일 | 역할 |
|:-----|:-----|
| `src/index.ts` | 메인 진입점 |
| `src/app.ts` | 앱 초기화 |
| `src/api.ts` | API 라우트 |

## 외부 의존성

| 의존성 | 버전 | 용도 |
|:-------|:-----|:-----|
| [package] | [version] | [purpose] |

## 환경 변수

| 변수명 | 필수 | 설명 |
|:-------|:----:|:-----|
| `DATABASE_URL` | ✅ | DB 연결 문자열 |
| `API_KEY` | ✅ | 외부 API 키 |
| `DEBUG` | ❌ | 디버그 모드 |

## 알려진 제약사항

- [제약사항 1]
- [제약사항 2]

## 참고 링크

- [API 문서](https://...)
- [디자인 시스템](https://...)
- [CI/CD 대시보드](https://...)
