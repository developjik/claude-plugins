#!/usr/bin/env bash
# browser-actions.sh — browser-controller page action helpers

set -euo pipefail

browser_escape_action_text() {
  local value="${1:-}"
  echo "$value" | jq -Rs '.' | sed 's/^"//;s/"$//'
}

# ============================================================================
# 내비게이션
# ============================================================================

browser_navigate() {
  local url="${1:-}"
  local project_root="${2:-$(pwd)}"

  if [[ -z "$url" ]]; then
    echo '{"success": false, "error": "url_required"}'
    return 1
  fi

  _browser_action "$project_root" "navigate" "$url"
}

browser_back() {
  local project_root="${1:-$(pwd)}"
  _browser_action "$project_root" "back" ""
}

browser_forward() {
  local project_root="${1:-$(pwd)}"
  _browser_action "$project_root" "forward" ""
}

browser_refresh() {
  local project_root="${1:-$(pwd)}"
  _browser_action "$project_root" "refresh" ""
}

# ============================================================================
# 요소 조작
# ============================================================================

browser_click() {
  local selector="${1:-}"
  local project_root="${2:-$(pwd)}"

  if [[ -z "$selector" ]]; then
    echo '{"success": false, "error": "selector_required"}'
    return 1
  fi

  _browser_action "$project_root" "click" "$selector"
}

browser_fill() {
  local selector="${1:-}"
  local value="${2:-}"
  local project_root="${3:-$(pwd)}"

  if [[ -z "$selector" ]]; then
    echo '{"success": false, "error": "selector_required"}'
    return 1
  fi

  _browser_action "$project_root" "fill" "${selector}|||$(browser_escape_action_text "$value")"
}

browser_type() {
  local selector="${1:-}"
  local text="${2:-}"
  local project_root="${3:-$(pwd)}"

  if [[ -z "$selector" ]]; then
    echo '{"success": false, "error": "selector_required"}'
    return 1
  fi

  _browser_action "$project_root" "type" "${selector}|||$(browser_escape_action_text "$text")"
}

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

browser_check() {
  local selector="${1:-}"
  local project_root="${2:-$(pwd)}"
  _browser_action "$project_root" "check" "$selector"
}

browser_uncheck() {
  local selector="${1:-}"
  local project_root="${2:-$(pwd)}"
  _browser_action "$project_root" "uncheck" "$selector"
}

# ============================================================================
# 정보 수집
# ============================================================================

browser_screenshot() {
  local filename="${1:-screenshot_$(date +%Y%m%d_%H%M%S).png}"
  local project_root="${2:-$(pwd)}"
  local screenshot_dir screenshot_path

  screenshot_dir=$(browser_screenshot_dir "$project_root")
  screenshot_path="${screenshot_dir}/${filename}"

  mkdir -p "$screenshot_dir"

  _browser_action "$project_root" "screenshot" "$screenshot_path"
}

browser_text() {
  local selector="${1:-}"
  local project_root="${2:-$(pwd)}"

  if [[ -z "$selector" ]]; then
    echo '{"success": false, "error": "selector_required"}'
    return 1
  fi

  _browser_action "$project_root" "text" "$selector"
}

browser_value() {
  local selector="${1:-}"
  local project_root="${2:-$(pwd)}"

  if [[ -z "$selector" ]]; then
    echo '{"success": false, "error": "selector_required"}'
    return 1
  fi

  _browser_action "$project_root" "value" "$selector"
}

browser_title() {
  local project_root="${1:-$(pwd)}"
  _browser_action "$project_root" "title" ""
}

browser_url() {
  local project_root="${1:-$(pwd)}"
  _browser_action "$project_root" "url" ""
}

browser_html() {
  local selector="${1:-}"
  local project_root="${2:-$(pwd)}"
  _browser_action "$project_root" "html" "$selector"
}

browser_exists() {
  local selector="${1:-}"
  local project_root="${2:-$(pwd)}"

  if [[ -z "$selector" ]]; then
    echo '{"success": false, "error": "selector_required", "exists": false}'
    return 1
  fi

  _browser_action "$project_root" "exists" "$selector"
}

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

browser_wait() {
  local ms="${1:-1000}"
  local project_root="${2:-$(pwd)}"
  _browser_action "$project_root" "wait" "$ms"
}

# ============================================================================
# 고급 기능
# ============================================================================

browser_evaluate() {
  local script="${1:-}"
  local project_root="${2:-$(pwd)}"

  if [[ -z "$script" ]]; then
    echo '{"success": false, "error": "script_required"}'
    return 1
  fi

  _browser_action "$project_root" "evaluate" "$script"
}

browser_hover() {
  local selector="${1:-}"
  local project_root="${2:-$(pwd)}"

  if [[ -z "$selector" ]]; then
    echo '{"success": false, "error": "selector_required"}'
    return 1
  fi

  _browser_action "$project_root" "hover" "$selector"
}

browser_focus() {
  local selector="${1:-}"
  local project_root="${2:-$(pwd)}"

  if [[ -z "$selector" ]]; then
    echo '{"success": false, "error": "selector_required"}'
    return 1
  fi

  _browser_action "$project_root" "focus" "$selector"
}

browser_press() {
  local key="${1:-}"
  local project_root="${2:-$(pwd)}"

  if [[ -z "$key" ]]; then
    echo '{"success": false, "error": "key_required"}'
    return 1
  fi

  _browser_action "$project_root" "press" "$key"
}

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

browser_get_cookies() {
  local project_root="${1:-$(pwd)}"
  _browser_action "$project_root" "get_cookies" ""
}

browser_set_cookies() {
  local cookies="${1:-}"
  local project_root="${2:-$(pwd)}"

  if [[ -z "$cookies" ]]; then
    echo '{"success": false, "error": "cookies_required"}'
    return 1
  fi

  _browser_action "$project_root" "set_cookies" "$cookies"
}

browser_clear_cookies() {
  local project_root="${1:-$(pwd)}"
  _browser_action "$project_root" "clear_cookies" ""
}

# ============================================================================
# 내부 구현
# ============================================================================

_browser_action() {
  local project_root="${1:-}"
  local action="${2:-}"
  local params="${3:-}"
  local state_dir script_file result

  state_dir=$(browser_state_dir "$project_root")
  script_file=$(browser_runtime_script_file "$project_root" "action.js")

  cat > "$script_file" << 'SCRIPT'
const fs = require('fs');
const path = require('path');

async function performAction() {
  const stateDir = process.env.HARNESS_BROWSER_STATE_DIR || '.harness/browser';
  const action = process.env.BROWSER_ACTION || '';
  const params = process.env.BROWSER_PARAMS || '';
  const wsEndpointFile = path.join(stateDir, 'ws-endpoint.txt');

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
        const element = await page.$(params);
        result.exists = !!element;
        break;
      }

      case 'visible': {
        const element = await page.$(params);
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
        result.error = `Unknown action: ${action}`;
    }

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

  if ! command -v node > /dev/null 2>&1; then
    result='{"success": false, "error": "node_not_installed"}'
  else
    result=$(browser_run_node_script \
      "$project_root" \
      "$script_file" \
      "HARNESS_BROWSER_STATE_DIR=${state_dir}" \
      "BROWSER_ACTION=$action" \
      "BROWSER_PARAMS=$params")
  fi

  if echo "$result" | jq -e . > /dev/null 2>&1; then
    echo "$result"
  elif [[ -n "$result" ]]; then
    jq -cn --arg err "$result" '{"success": false, "error": $err}'
  else
    echo '{"success": false, "error": "browser_action_failed"}'
  fi

  if echo "$result" | jq -e '.success' > /dev/null 2>&1; then
    return 0
  fi
  return 1
}
