# 브라우저저 제어 시스템 (Browser Controller)

Playwright 기반 실제 브라우저 제어 시스템입니다 gstack의 `$B connect` 패턴과 영감을밨습니다.

---

## 설치

### 전제조건

```bash
npm install -D @playwright/test
```

### 지원 언어

| 언어 | LSP 서버 |
| TypeScript | `typescript-language-server` | `npm i -g typescript-language-server` |
| Python | `pylsp` | `pip install python-lsp-server` |
| Go | `gopls` | Go 설치 시 자동 포함 |
| Rust | `rust-analyzer` | `rustup component add rust-analyzer` |

---

## 사용법

### 1. 브라우저 연결

```bash
browser_connect . --url="https://example.com"
```

gstack의 `$B connect`와 동일하게 headed Chrome 창이 열리고 실제 브라우저 창을을 수 있습니다 있습니다```json
{
  "success": true,
  "mode": "headed",
  " " "message": " " Browser connected. Use browser_* functions to control."
}
```

### 2. URL 이동

```bash
browser_navigate "https://myapp.com/login"
```

### 2. 요소 클릭

```bash
browser_click "button[type='submit']"
browser_click "text=Login"          # 텍스트으로 클릭
```

### 4. 입력 채우기

```bash
browser_fill "#email" "user@example.com"
browser_fill "#password" "secretpass"
```

### 5. 스크린샷

```bash
browser_screenshot login.png
```

### 6. 텍스트 추출

```bash
browser_text "h1"
browser_value "#email"
```

### 7. JavaScript 실행

```bash
browser_evaluate "document.title"
```

### 8. 대기

```bash
browser_wait_for_selector ".loading" 5000
```

### 9. 연결 해제

```bash
browser_disconnect
```

---

## API 함수

### 기본 조작

| 함수 | 설명 |
|------|------|
| `browser_connect()` | headed Chrome 연결 |
| `browser_disconnect()` | headless로 복귀 |
| `browser_navigate()` | URL 이동 |
| `browser_click()` | 요소 클릭 |
| `browser_fill()` | 입력 필드 채우기 |
| `browser_type()` | 느린 타이핑 |
| `browser_screenshot()` | 스크린샷 |
| `browser_text()` | 요소 텍스트 추출 |
| `browser_value()` | 입력 값 추출 |
| `browser_html()` | HTML 추출 |
| `browser_exists()` | 요소 존재 확인 |
| `browser_visible()` | 요소 가시성 확인 |
| `browser_wait_for_selector()` | 요소 대기 |
| `browser_wait_for_url()` | URL 변경 대기 |
| `browser_wait()` | 단순 대기 |
| `browser_evaluate()` | JavaScript 실행 |
| `browser_hover()` | 마우스 호버 |
| `browser_focus()` | 요소 포커스 |
| `browser_press()` | 키 입력 |
| `browser_upload()` | 파일 업로드 |
| `browser_get_cookies()` | 쿠키 가져오기 |
| `browser_set_cookies()` | 쿠키 설정 |
| `browser_clear_cookies()` | 쿠키 삭제 |
| `browser_status()` | 현재 상태 |
| `browser_is_connected()` | 연결 여부 확인 |
| `browser_debug()` | 디버그 정보 |

---

## CLI 인터페이스 (`browser` 명령어)

```bash
browser connect https://example.com
browser click "button.submit"
browser fill "#email" "test@test.com"
browser screenshot
browser disconnect
```

---

## 상태 관리

- `.harness/browser/session.json` - 세션 상태
- `.harness/browser/ws-endpoint.txt` - WebSocket 엔드포인트
- `.harness/browser/screenshots/` - 스크린샷 저장

---

## 참고

- gstack `/browse` 스킬
- Playwright 공식 문서
