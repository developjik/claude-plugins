#!/usr/bin/env bash
# browser-controller.sh — 실제 브라우저 제어 시스템
# P1-5: gstack $B connect 패턴 기반
#
# DEPENDENCIES: json-utils.sh, logging.sh
#
# 참고: gstack /browse 스킬
# - $B connect: headed Chrome 연결
# - $B disconnect: headless로 복귀
# - $B screenshot: 스크린샷
# - $B click: 클릭
# - $B fill: 입력
#
# 이 스크립트는 Playwright를 사용하여 실제 브라우저를 제어합니다.
# Claude Code에서 Agent 툴을 통해 브라우저 조작을 수행합니다.

set -euo pipefail

# ============================================================================
# 상수
# ============================================================================

readonly BROWSER_STATE_DIR=".harness/browser"
readonly BROWSER_SESSION_FILE="${BROWSER_STATE_DIR}/session.json"
readonly BROWSER_LOG_FILE="${BROWSER_STATE_DIR}/browser.log"
readonly BROWSER_TIMEOUT=30000          # 30초
readonly BROWSER_PAGE_TIMEOUT=60000    # 60초
readonly BROWSER_SCRIPT_TIMEOUT=10000  # 10초
readonly BROWSER_STATE_ENV_VAR="HARNESS_BROWSER_STATE_DIR"

# ============================================================================
# 상태 관리
# ============================================================================

# 브라우저 상태 초기화
_init_browser_state() {
  local project_root="${1:-$(pwd)}"
  local state_dir="${project_root}/${BROWSER_STATE_DIR}"

  mkdir -p "$state_dir"

  if [[ ! -f "${state_dir}/session.json" ]]; then
    cat > "${state_dir}/session.json" << 'EOF'
{
  "connected": false,
  "mode": "headless",
  "browser": null,
  "page": null,
  "url": null,
  "last_action": null,
  "actions_count": 0
}
EOF
  fi
}

# 상태 업데이트
_update_browser_state() {
  local project_root="${1:-$(pwd)}"
  local key="${2:-}"
  local value="${3:-}"

  _init_browser_state "$project_root"

  local state_file="${project_root}/${BROWSER_STATE_DIR}/session.json"

  if [[ -n "$key" ]] && command -v jq &>/dev/null; then
    local tmp_file="${state_file}.tmp"
    # Fixed: Pass $key to jq using --arg
    jq --arg key "$key" --argjson val "$value" '.[$key] = $val' "$state_file" > "$tmp_file" && \
      mv "$tmp_file" "$state_file"
  fi
}

# 상태 조회
_get_browser_state() {
  local project_root="${1:-$(pwd)}"
  local key="${2:-}"

  _init_browser_state "$project_root"

  local state_file="${project_root}/${BROWSER_STATE_DIR}/session.json"

  if [[ -n "$key" ]]; then
    jq -r ".$key // null" "$state_file" 2>/dev/null || echo "null"
  else
    cat "$state_file"
  fi
}

# ============================================================================
# 브라우저 연결 관리
# ============================================================================

# browser_connect — headed Chrome 연결
# Usage: browser_connect [project_root] [options]
# Options: --url=<url> --browser=<browser>
#
# gstack의 $B connect와 동일한 기능
# 실제 Chrome 창을 열고 Claude가 제어할 수 있게 합니다.
#
# Returns: JSON with session info
browser_connect() {
  local project_root="${1:-$(pwd)}"
  shift || true

  local url=""
  local browser="chromium"

  # 옵션 파싱
  for arg in "$@"; do
    case "$arg" in
      --url=*) url="${arg#*=}" ;;
      --browser=*) browser="${arg#*=}" ;;
    esac
  done

  if ! command -v node >/dev/null 2>&1; then
    echo '{"success": false, "error": "node_not_installed"}'
    return 1
  fi

  if ! node -e "require('playwright')" >/dev/null 2>&1; then
    echo '{"success": false, "error": "playwright_not_installed"}'
    return 1
  fi

  _init_browser_state "$project_root"

  local state_dir="${project_root}/${BROWSER_STATE_DIR}"
  local script_file="${state_dir}/connect.js"

  # Playwright 연결 스크립트 생성
  cat > "$script_file" << 'SCRIPT'
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

async function connect() {
  const stateDir = process.env.HARNESS_BROWSER_STATE_DIR || '.harness/browser';
  const url = process.env.BROWSER_URL || 'about:blank';
  const browserType = process.env.BROWSER_TYPE || 'chromium';

  let browser, context, page;

  try {
    const { chromium } = require('playwright');

    // Headed 모드로 브라우저 시작
    browser = await chromium.launch({
      headless: false,
      args: [
        '--disable-blink-features=AutomationControlled',
        '--no-sandbox',
        '--disable-setuid-sandbox'
      ]
    });

    context = await browser.newContext({
      viewport: { width: 1280, height: 720 }
    });

    page = await context.newPage();

    // URL로 이동
    if (url && url !== 'about:blank') {
      await page.goto(url, { waitUntil: 'networkidle', timeout: 60000 });
    }

    // 세션 정보 저장
    const session = {
      connected: true,
      mode: 'headed',
      browser: browserType,
      page: 'active',
      url: page.url(),
      last_action: 'connect',
      actions_count: 0,
      timestamp: new Date().toISOString()
    };

    fs.writeFileSync(
      path.join(stateDir, 'session.json'),
      JSON.stringify(session, null, 2)
    );

    // CDP 엔드포인트 저장 (재연결용)
    const wsEndpoint = browser.wsEndpoint();
    fs.writeFileSync(
      path.join(stateDir, 'ws-endpoint.txt'),
      wsEndpoint
    );

    console.log(JSON.stringify({
      success: true,
      mode: 'headed',
      url: page.url(),
      wsEndpoint: wsEndpoint,
      message: 'Browser connected. Use browser_* functions to control.'
    }));

  } catch (error) {
    console.log(JSON.stringify({
      success: false,
      error: error.message
    }));
    process.exit(1);
  }
}

connect();
SCRIPT

  # 스크립트 실행
  local result
  result=$(
    cd "$project_root" && \
    HARNESS_BROWSER_STATE_DIR="${state_dir}" \
    BROWSER_URL="$url" \
    BROWSER_TYPE="$browser" \
    node "$script_file" 2>&1
  )

  # 결과 파싱
  if echo "$result" | jq -e '.success' &>/dev/null; then
    _update_browser_state "$project_root" "connected" "true"
    _update_browser_state "$project_root" "mode" '"headed"'

    echo "$result"
    return 0
  else
    if echo "$result" | jq -e . >/dev/null 2>&1; then
      echo "$result"
    elif [[ -n "$result" ]]; then
      jq -cn --arg err "$result" '{"success": false, "error": $err}'
    else
      echo '{"success": false, "error": "browser_connect_failed"}'
    fi
    return 1
  fi
}

# browser_disconnect — headless 모드로 복귀
# Usage: browser_disconnect [project_root]
#
# gstack의 $B disconnect와 동일
browser_disconnect() {
  local project_root="${1:-$(pwd)}"

  local state_dir="${project_root}/${BROWSER_STATE_DIR}"
  local script_file="${state_dir}/disconnect.js"

  # 종료 스크립트 생성
  cat > "$script_file" << 'SCRIPT'
const fs = require('fs');
const path = require('path');

async function disconnect() {
  const stateDir = process.env.HARNESS_BROWSER_STATE_DIR || '.harness/browser';
  const wsEndpointFile = path.join(stateDir, 'ws-endpoint.txt');

  if (!fs.existsSync(wsEndpointFile)) {
    console.log(JSON.stringify({ success: true, message: 'No active session' }));
    return;
  }

  try {
    const wsEndpoint = fs.readFileSync(wsEndpointFile, 'utf8').trim();
    const { chromium } = require('playwright');

    const browser = await chromium.connect({ wsEndpoint });
    await browser.close();

    // 세션 정리
    fs.writeFileSync(
      path.join(stateDir, 'session.json'),
      JSON.stringify({
        connected: false,
        mode: 'headless',
        browser: null,
        page: null,
        url: null,
        last_action: 'disconnect',
        actions_count: 0
      }, null, 2)
    );

    fs.unlinkSync(wsEndpointFile);

    console.log(JSON.stringify({ success: true, message: 'Browser disconnected' }));
  } catch (error) {
    console.log(JSON.stringify({ success: false, error: error.message }));
  }
}

disconnect();
SCRIPT

  local result
  result=$(
    cd "$project_root" && \
    HARNESS_BROWSER_STATE_DIR="${state_dir}" \
    node "$script_file" 2>&1
  )

  _update_browser_state "$project_root" "connected" "false"
  _update_browser_state "$project_root" "mode" '"headless"'

  echo "$result"
}

# ============================================================================
# 내비게이션
# ============================================================================

# browser_navigate — URL로 이동
# Usage: browser_navigate <url> [project_root]
browser_navigate() {
  local url="${1:-}"
  local project_root="${2:-$(pwd)}"

  if [[ -z "$url" ]]; then
    echo '{"success": false, "error": "url_required"}'
    return 1
  fi

  _browser_action "$project_root" "navigate" "$url"
}

# browser_back — 뒤로 가기
browser_back() {
  local project_root="${1:-$(pwd)}"
  _browser_action "$project_root" "back" ""
}

# browser_forward — 앞으로 가기
browser_forward() {
  local project_root="${1:-$(pwd)}"
  _browser_action "$project_root" "forward" ""
}

# browser_refresh — 새로고침
browser_refresh() {
  local project_root="${1:-$(pwd)}"
  _browser_action "$project_root" "refresh" ""
}

# ============================================================================
# 요소 조작
# ============================================================================

# browser_click — 요소 클릭
# Usage: browser_click <selector> [project_root]
#
# selector: CSS 선택자 또는 텍스트
# 예: browser_click "button[type='submit']"
#     browser_click "text=Login"
browser_click() {
  local selector="${1:-}"
  local project_root="${2:-$(pwd)}"

  if [[ -z "$selector" ]]; then
    echo '{"success": false, "error": "selector_required"}'
    return 1
  fi

  _browser_action "$project_root" "click" "$selector"
}

# browser_fill — 입력 필드 채우기
# Usage: browser_fill <selector> <value> [project_root]
#
# 예: browser_fill "#email" "user@example.com"
#     browser_fill "input[name='password']" "secretpass"
browser_fill() {
  local selector="${1:-}"
  local value="${2:-}"
  local project_root="${3:-$(pwd)}"

  if [[ -z "$selector" ]]; then
    echo '{"success": false, "error": "selector_required"}'
    return 1
  fi

  # JSON 이스케이프
  local escaped_value
  escaped_value=$(echo "$value" | jq -Rs '.' | sed 's/^"//;s/"$//')

  _browser_action "$project_root" "fill" "${selector}|||${escaped_value}"
}

# browser_type — 타이핑 (느리게)
# Usage: browser_type <selector> <text> [project_root]
browser_type() {
  local selector="${1:-}"
  local text="${2:-}"
  local project_root="${3:-$(pwd)}"

  if [[ -z "$selector" ]]; then
    echo '{"success": false, "error": "selector_required"}'
    return 1
  fi

  local escaped_text
  escaped_text=$(echo "$text" | jq -Rs '.' | sed 's/^"//;s/"$//')

  _browser_action "$project_root" "type" "${selector}|||${escaped_text}"
}

# browser_select — 드롭다운 선택
# Usage: browser_select <selector> <value> [project_root]
browser_select() {
  local selector="${1:-}"
  local value="${2:-}"
  local project_root="${3:-$(pwd)}"

  if [[ -z "$selector" ]]; then
    echo '{"success": false, "error": "selector_required"}'
    return 1
  fi

  _browser_action "$project_root" "select" "${selector}|||${value}"
}

# browser_check — 체크박스/라디오 체크
# Usage: browser_check <selector> [project_root]
browser_check() {
  local selector="${1:-}"
  local project_root="${2:-$(pwd)}"

  _browser_action "$project_root" "check" "$selector"
}

# browser_uncheck — 체크박스 체크 해제
# Usage: browser_uncheck <selector> [project_root]
browser_uncheck() {
  local selector="${1:-}"
  local project_root="${2:-$(pwd)}"

  _browser_action "$project_root" "uncheck" "$selector"
}

# ============================================================================
# 정보 수집
# ============================================================================

# browser_screenshot — 스크린샷 촬영
# Usage: browser_screenshot [filename] [project_root]
#
# gstack의 스크린샷 기능과 동일
browser_screenshot() {
  local filename="${1:-screenshot_$(date +%Y%m%d_%H%M%S).png}"
  local project_root="${2:-$(pwd)}"

  local state_dir="${project_root}/${BROWSER_STATE_DIR}"
  local screenshot_path="${state_dir}/screenshots/${filename}"

  mkdir -p "$(dirname "$screenshot_path")"

  _browser_action "$project_root" "screenshot" "$screenshot_path"
}

# browser_text — 요소 텍스트 가져오기
# Usage: browser_text <selector> [project_root]
browser_text() {
  local selector="${1:-}"
  local project_root="${2:-$(pwd)}"

  if [[ -z "$selector" ]]; then
    echo '{"success": false, "error": "selector_required"}'
    return 1
  fi

  _browser_action "$project_root" "text" "$selector"
}

# browser_value — 입력 필드 값 가져오기
# Usage: browser_value <selector> [project_root]
browser_value() {
  local selector="${1:-}"
  local project_root="${2:-$(pwd)}"

  if [[ -z "$selector" ]]; then
    echo '{"success": false, "error": "selector_required"}'
    return 1
  fi

  _browser_action "$project_root" "value" "$selector"
}

# browser_title — 페이지 제목 가져오기
browser_title() {
  local project_root="${1:-$(pwd)}"
  _browser_action "$project_root" "title" ""
}

# browser_url — 현재 URL 가져오기
browser_url() {
  local project_root="${1:-$(pwd)}"
  _browser_action "$project_root" "url" ""
}

# browser_html — 페이지 HTML 가져오기
# Usage: browser_html [selector] [project_root]
browser_html() {
  local selector="${1:-}"
  local project_root="${2:-$(pwd)}"

  _browser_action "$project_root" "html" "$selector"
}

# browser_exists — 요소 존재 확인
# Usage: browser_exists <selector> [project_root]
browser_exists() {
  local selector="${1:-}"
  local project_root="${2:-$(pwd)}"

  if [[ -z "$selector" ]]; then
    echo '{"success": false, "error": "selector_required", "exists": false}'
    return 1
  fi

  _browser_action "$project_root" "exists" "$selector"
}

# browser_visible — 요소 가시성 확인
# Usage: browser_visible <selector> [project_root]
browser_visible() {
  local selector="${1:-}"
  local project_root="${2:-$(pwd)}"

  if [[ -z "$selector" ]]; then
    echo '{"success": false, "error": "selector_required", "visible": false}'
    return 1
  fi

  _browser_action "$project_root" "visible" "$selector"
}

# ============================================================================
# 대기 및 동기화
# ============================================================================

# browser_wait_for_selector — 요소 대기
# Usage: browser_wait_for_selector <selector> [timeout_ms] [project_root]
browser_wait_for_selector() {
  local selector="${1:-}"
  local timeout="${2:-30000}"
  local project_root="${3:-$(pwd)}"

  if [[ -z "$selector" ]]; then
    echo '{"success": false, "error": "selector_required"}'
    return 1
  fi

  _browser_action "$project_root" "wait_for_selector" "${selector}|||${timeout}"
}

# browser_wait_for_url — URL 변경 대기
# Usage: browser_wait_for_url <url_pattern> [timeout_ms] [project_root]
browser_wait_for_url() {
  local url_pattern="${1:-}"
  local timeout="${2:-30000}"
  local project_root="${3:-$(pwd)}"

  if [[ -z "$url_pattern" ]]; then
    echo '{"success": false, "error": "url_pattern_required"}'
    return 1
  fi

  _browser_action "$project_root" "wait_for_url" "${url_pattern}|||${timeout}"
}

# browser_wait — 단순 대기
# Usage: browser_wait <ms> [project_root]
browser_wait() {
  local ms="${1:-1000}"
  local project_root="${2:-$(pwd)}"

  _browser_action "$project_root" "wait" "$ms"
}

# ============================================================================
# 고급 기능
# ============================================================================

# browser_evaluate — JavaScript 실행
# Usage: browser_evaluate <script> [project_root]
#
# 예: browser_evaluate "document.querySelector('h1').textContent"
browser_evaluate() {
  local script="${1:-}"
  local project_root="${2:-$(pwd)}"

  if [[ -z "$script" ]]; then
    echo '{"success": false, "error": "script_required"}'
    return 1
  fi

  _browser_action "$project_root" "evaluate" "$script"
}

# browser_hover — 마우스 호버
# Usage: browser_hover <selector> [project_root]
browser_hover() {
  local selector="${1:-}"
  local project_root="${2:-$(pwd)}"

  if [[ -z "$selector" ]]; then
    echo '{"success": false, "error": "selector_required"}'
    return 1
  fi

  _browser_action "$project_root" "hover" "$selector"
}

# browser_focus — 요소 포커스
# Usage: browser_focus <selector> [project_root]
browser_focus() {
  local selector="${1:-}"
  local project_root="${2:-$(pwd)}"

  if [[ -z "$selector" ]]; then
    echo '{"success": false, "error": "selector_required"}'
    return 1
  fi

  _browser_action "$project_root" "focus" "$selector"
}

# browser_press — 키 입력
# Usage: browser_press <key> [project_root]
#
# 예: browser_press "Enter"
#     browser_press "Control+A"
browser_press() {
  local key="${1:-}"
  local project_root="${2:-$(pwd)}"

  if [[ -z "$key" ]]; then
    echo '{"success": false, "error": "key_required"}'
    return 1
  fi

  _browser_action "$project_root" "press" "$key"
}

# browser_upload — 파일 업로드
# Usage: browser_upload <selector> <file_path> [project_root]
browser_upload() {
  local selector="${1:-}"
  local file_path="${2:-}"
  local project_root="${3:-$(pwd)}"

  if [[ -z "$selector" ]] || [[ -z "$file_path" ]]; then
    echo '{"success": false, "error": "selector_and_file_required"}'
    return 1
  fi

  local abs_path
  abs_path=$(cd "$(dirname "$file_path")" && pwd)/$(basename "$file_path")

  _browser_action "$project_root" "upload" "${selector}|||${abs_path}"
}

# ============================================================================
# 쿠키 및 인증
# ============================================================================

# browser_get_cookies — 쿠키 가져오기
# Usage: browser_get_cookies [project_root]
browser_get_cookies() {
  local project_root="${1:-$(pwd)}"
  _browser_action "$project_root" "get_cookies" ""
}

# browser_set_cookies — 쿠키 설정
# Usage: browser_set_cookies <cookies_json> [project_root]
#
# 예: browser_set_cookies '[{"name": "session", "value": "abc123", "domain": "example.com"}]'
browser_set_cookies() {
  local cookies="${1:-}"
  local project_root="${2:-$(pwd)}"

  if [[ -z "$cookies" ]]; then
    echo '{"success": false, "error": "cookies_required"}'
    return 1
  fi

  _browser_action "$project_root" "set_cookies" "$cookies"
}

# browser_clear_cookies — 쿠키 삭제
# Usage: browser_clear_cookies [project_root]
browser_clear_cookies() {
  local project_root="${1:-$(pwd)}"
  _browser_action "$project_root" "clear_cookies" ""
}

# ============================================================================
# 내부 구현
# ============================================================================

# 공통 액션 실행 함수
_browser_action() {
  local project_root="${1:-}"
  local action="${2:-}"
  local params="${3:-}"

  local state_dir="${project_root}/${BROWSER_STATE_DIR}"
  local script_file="${state_dir}/action.js"

  # 액션 스크립트 생성
  cat > "$script_file" << SCRIPT
const fs = require('fs');
const path = require('path');

async function performAction() {
  const stateDir = process.env.HARNESS_BROWSER_STATE_DIR || '.harness/browser';
  const action = process.env.BROWSER_ACTION || '';
  const params = process.env.BROWSER_PARAMS || '';
  const wsEndpointFile = path.join(stateDir, 'ws-endpoint.txt');

  // 세션 확인
  if (!fs.existsSync(wsEndpointFile)) {
    console.log(JSON.stringify({
      success: false,
      error: 'no_active_session',
      message: 'Run browser_connect first'
    }));
    process.exit(1);
  }

  try {
    const { chromium } = require('playwright');
    const wsEndpoint = fs.readFileSync(wsEndpointFile, 'utf8').trim();
    const browser = await chromium.connect({ wsEndpoint });
    const context = browser.contexts()[0];
    const page = context.pages()[0] || await context.newPage();

    let result = { success: true };

    switch (action) {
      case 'navigate':
        await page.goto(params, { waitUntil: 'networkidle', timeout: 60000 });
        result.url = page.url();
        break;

      case 'back':
        await page.goBack({ waitUntil: 'networkidle' });
        result.url = page.url();
        break;

      case 'forward':
        await page.goForward({ waitUntil: 'networkidle' });
        result.url = page.url();
        break;

      case 'refresh':
        await page.reload({ waitUntil: 'networkidle' });
        result.url = page.url();
        break;

      case 'click':
        await page.click(params);
        break;

      case 'fill': {
        const [selector, value] = params.split('|||');
        await page.fill(selector, value);
        break;
      }

      case 'type': {
        const [selector, text] = params.split('|||');
        await page.type(selector, text, { delay: 50 });
        break;
      }

      case 'select': {
        const [selector, value] = params.split('|||');
        await page.selectOption(selector, value);
        break;
      }

      case 'check':
        await page.check(params);
        break;

      case 'uncheck':
        await page.uncheck(params);
        break;

      case 'screenshot':
        await page.screenshot({ path: params, fullPage: true });
        result.path = params;
        break;

      case 'text': {
        const element = await page.waitForSelector(params, { timeout: 10000 });
        result.text = await element.textContent();
        break;
      }

      case 'value': {
        const element = await page.waitForSelector(params, { timeout: 10000 });
        result.value = await element.inputValue();
        break;
      }

      case 'title':
        result.title = await page.title();
        break;

      case 'url':
        result.url = page.url();
        break;

      case 'html': {
        if (params) {
          const element = await page.waitForSelector(params, { timeout: 10000 });
          result.html = await element.innerHTML();
        } else {
          result.html = await page.content();
        }
        break;
      }

      case 'exists': {
        const element = await page.\$(params);
        result.exists = !!element;
        break;
      }

      case 'visible': {
        const element = await page.\$(params);
        result.visible = element ? await element.isVisible() : false;
        break;
      }

      case 'wait_for_selector': {
        const [selector, timeout] = params.split('|||');
        await page.waitForSelector(selector, { timeout: parseInt(timeout) || 30000 });
        break;
      }

      case 'wait_for_url': {
        const [pattern, timeout] = params.split('|||');
        await page.waitForURL(pattern, { timeout: parseInt(timeout) || 30000 });
        result.url = page.url();
        break;
      }

      case 'wait':
        await page.waitForTimeout(parseInt(params) || 1000);
        break;

      case 'evaluate': {
        // Security: Validate and sanitize JavaScript before evaluation
        // Block dangerous patterns that could escape sandbox or access Node.js APIs
        const dangerousPatterns = [
          /require\s*\(/,
          /import\s+/,
          /process\./,
          /global\./,
          /eval\s*\(/,
          /Function\s*\(/,
          /fetch\s*\(/,
          /XMLHttpRequest/,
          /WebSocket/,
          /\.exit\s*\(/,
          /child_process/,
          /fs\./,
          /path\./,
          /os\./,
          /crypto\./,
          /buffer\./,
        ];

        let sanitizedScript = params;
        let isDangerous = false;

        for (const pattern of dangerousPatterns) {
          if (pattern.test(sanitizedScript)) {
            isDangerous = true;
            break;
          }
        }

        if (isDangerous) {
          result.success = false;
          result.error = 'script_blocked';
          result.message = 'Script contains blocked patterns (require, process, fs, etc.)';
        } else {
          // Safe evaluation - only DOM access allowed
          result.result = await page.evaluate(sanitizedScript);
        }
        break;
      }

      case 'hover':
        await page.hover(params);
        break;

      case 'focus':
        await page.focus(params);
        break;

      case 'press':
        await page.keyboard.press(params);
        break;

      case 'upload': {
        const [selector, filePath] = params.split('|||');
        const fileChooserPromise = page.waitForEvent('filechooser');
        await page.click(selector);
        const fileChooser = await fileChooserPromise;
        await fileChooser.setFiles(filePath);
        break;
      }

      case 'get_cookies':
        result.cookies = await context.cookies();
        break;

      case 'set_cookies':
        await context.addCookies(JSON.parse(params));
        break;

      case 'clear_cookies':
        await context.clearCookies();
        break;

      default:
        result.success = false;
        result.error = \`Unknown action: \${action}\`;
    }

    // 세션 상태 업데이트
    const session = JSON.parse(fs.readFileSync(path.join(stateDir, 'session.json'), 'utf8'));
    session.last_action = action;
    session.actions_count = (session.actions_count || 0) + 1;
    session.url = page.url();
    session.timestamp = new Date().toISOString();
    fs.writeFileSync(path.join(stateDir, 'session.json'), JSON.stringify(session, null, 2));

    console.log(JSON.stringify(result));

  } catch (error) {
    console.log(JSON.stringify({ success: false, error: error.message }));
    process.exit(1);
  }
}

performAction();
SCRIPT

  # 스크립트 실행
  local result
  result=$(
    cd "$project_root" && \
    HARNESS_BROWSER_STATE_DIR="${state_dir}" \
    BROWSER_ACTION="$action" \
    BROWSER_PARAMS="$params" \
    node "$script_file" 2>&1
  )

  if echo "$result" | jq -e . >/dev/null 2>&1; then
    echo "$result"
  elif [[ -n "$result" ]]; then
    jq -cn --arg err "$result" '{"success": false, "error": $err}'
  else
    echo '{"success": false, "error": "browser_action_failed"}'
  fi

  # 성공 여부 확인
  if echo "$result" | jq -e '.success' &>/dev/null; then
    return 0
  else
    return 1
  fi
}

# ============================================================================
# 상태 조회 함수
# ============================================================================

# browser_status — 현재 브라우저 상태
# Usage: browser_status [project_root]
browser_status() {
  local project_root="${1:-$(pwd)}"

  _init_browser_state "$project_root"
  cat "${project_root}/${BROWSER_STATE_DIR}/session.json"
}

# browser_is_connected — 연결 여부 확인
# Usage: browser_is_connected [project_root]
browser_is_connected() {
  local project_root="${1:-$(pwd)}"

  local connected
  connected=$(_get_browser_state "$project_root" "connected")

  [[ "$connected" == "true" ]] && return 0 || return 1
}

# ============================================================================
# 헬퍼 함수 (gstack 스타일)
# ============================================================================

# $B 스타일의 통합 인터페이스
# Usage: browser <command> [args...]
#
# 예: browser connect https://example.com
#     browser click "button.submit"
#     browser fill "#email" "user@test.com"
#     browser screenshot
#     browser disconnect
browser() {
  local command="${1:-}"
  shift || true

  case "$command" in
    connect)
      local url="${1:-}"
      browser_connect "$(pwd)" --url="$url"
      ;;
    disconnect)
      browser_disconnect "$(pwd)"
      ;;
    navigate|goto|go)
      browser_navigate "$1"
      ;;
    click)
      browser_click "$1"
      ;;
    fill)
      browser_fill "$1" "$2"
      ;;
    type)
      browser_type "$1" "$2"
      ;;
    screenshot|shot)
      browser_screenshot "$1"
      ;;
    text)
      browser_text "$1"
      ;;
    value)
      browser_value "$1"
      ;;
    title)
      browser_title
      ;;
    url)
      browser_url
      ;;
    html)
      browser_html "$1"
      ;;
    exists)
      browser_exists "$1"
      ;;
    visible)
      browser_visible "$1"
      ;;
    wait|wait_for)
      browser_wait_for_selector "$1" "${2:-30000}"
      ;;
    hover)
      browser_hover "$1"
      ;;
    focus)
      browser_focus "$1"
      ;;
    press)
      browser_press "$1"
      ;;
    evaluate|eval|js)
      browser_evaluate "$1"
      ;;
    cookies)
      browser_get_cookies
      ;;
    status)
      browser_status
      ;;
    *)
      echo "Unknown command: $command"
      echo "Available: connect, disconnect, navigate, click, fill, type, screenshot, text, value, title, url, html, exists, visible, wait, hover, focus, press, evaluate, cookies, status"
      return 1
      ;;
  esac
}

# ============================================================================
# 디버깅
# ============================================================================

# browser_debug — 디버그 정보 출력
browser_debug() {
  local project_root="${1:-$(pwd)}"

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Browser Debug Info"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  echo "Project Root: $project_root"
  echo "State Directory: ${project_root}/${BROWSER_STATE_DIR}"
  echo ""

  if [[ -f "${project_root}/${BROWSER_STATE_DIR}/session.json" ]]; then
    echo "Session State:"
    jq '.' "${project_root}/${BROWSER_STATE_DIR}/session.json"
  else
    echo "No session file found"
  fi

  echo ""
  echo "Playwright Available: $(command -v npx &>/dev/null && npx playwright --version 2>/dev/null || echo 'No')"
  echo "Node.js Version: $(node --version 2>/dev/null || echo 'Not installed')"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}
