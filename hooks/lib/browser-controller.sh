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

readonly BROWSER_STATE_SUBDIR=".harness/browser"
readonly BROWSER_SESSION_FILE="${BROWSER_STATE_SUBDIR}/session.json"
readonly BROWSER_LOG_FILE="${BROWSER_STATE_SUBDIR}/browser.log"
readonly BROWSER_TIMEOUT=30000
readonly BROWSER_PAGE_TIMEOUT=60000
readonly BROWSER_SCRIPT_TIMEOUT=10000
readonly BROWSER_STATE_ENV_VAR="HARNESS_BROWSER_STATE_DIR"

if [[ -z "${BROWSER_CONTROLLER_LIB_DIR:-}" ]]; then
  BROWSER_CONTROLLER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# ============================================================================
# 내부 모듈 로드
# ============================================================================
if ! declare -f browser_state_dir > /dev/null 2>&1; then
  # shellcheck source=hooks/lib/browser-state.sh
  source "${BROWSER_CONTROLLER_LIB_DIR}/browser-state.sh"
fi

if ! declare -f browser_run_node_script > /dev/null 2>&1; then
  # shellcheck source=hooks/lib/browser-session.sh
  source "${BROWSER_CONTROLLER_LIB_DIR}/browser-session.sh"
fi

if ! declare -f _browser_action > /dev/null 2>&1; then
  # shellcheck source=hooks/lib/browser-actions.sh
  source "${BROWSER_CONTROLLER_LIB_DIR}/browser-actions.sh"
fi

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
    navigate | goto | go)
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
    screenshot | shot)
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
    wait | wait_for)
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
    evaluate | eval | js)
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
  local state_dir session_file
  state_dir=$(browser_state_dir "$project_root")
  session_file=$(browser_session_file "$project_root")

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Browser Debug Info"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  echo "Project Root: $project_root"
  echo "State Directory: $state_dir"
  echo ""

  if [[ -f "$session_file" ]]; then
    echo "Session State:"
    jq '.' "$session_file"
  else
    echo "No session file found"
  fi

  echo ""
  echo "Playwright Available: $(command -v npx &> /dev/null && npx playwright --version 2> /dev/null || echo 'No')"
  echo "Node.js Version: $(node --version 2> /dev/null || echo 'Not installed')"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}
