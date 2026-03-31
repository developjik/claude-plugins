#!/usr/bin/env bash
# result-summary.sh — 스킬 실행 결과 요약 유틸리티
# 각 PDCA 단계 완료 후 자동으로 결과 요약 생성
#
# DEPENDENCIES: logging.sh

# ============================================================================
# 결과 요약 템플릿
# ============================================================================

# 결과 요약 생성
# Usage: generate_result_summary <phase> <feature_slug> <start_time> [extra_data]
generate_result_summary() {
  local phase="${1:-unknown}"
  local feature_slug="${2:-unknown}"
  local start_time="${3:-$(date +%s)}"
  local extra_data="${4:-}"

  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))
  local duration_formatted
  duration_formatted=$(format_duration "$duration")

  local project_root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  local specs_dir="${project_root}/docs/specs/${feature_slug}"

  # 색상 (터미널 지원 시)
  local GREEN='\033[0;32m'
  local BLUE='\033[0;34m'
  local YELLOW='\033[1;33m'
  local NC='\033[0m'

  # 페이즈별 아이콘과 설명
  local phase_info
  case "$phase" in
    clarify)
      phase_info="📋 요청 구체화"
      ;;
    plan)
      phase_info="📝 요구사항 정의"
      ;;
    design)
      phase_info="🏗️ 기술 설계"
      ;;
    implement|do)
      phase_info="🔧 TDD 구현"
      ;;
    check)
      phase_info="✅ 검증"
      ;;
    wrapup)
      phase_info="📚 문서화"
      ;;
    *)
      phase_info="❓ $phase"
      ;;
  esac

  # 결과 출력
  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}✓ ${phase_info} 완료${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "${BLUE}⏱️ 소요 시간:${NC} ${duration_formatted}"
  echo -e "${BLUE}📁 기능명:${NC} ${feature_slug}"

  # 페이즈별 상세 정보
  case "$phase" in
    clarify)
      if [ -f "${specs_dir}/clarify.md" ]; then
        local goal
        goal=$(grep -A 5 "## 목표" "${specs_dir}/clarify.md" 2>/dev/null | head -3 | tail -2 || echo "")
        if [ -n "$goal" ]; then
          echo -e "${BLUE}🎯 핵심 목표:${NC}"
          echo "$goal" | sed 's/^/   /'
        fi
      fi
      echo ""
      echo -e "${YELLOW}➡️ 다음 단계:${NC} /plan ${feature_slug}"
      echo -e "${BLUE}📄 산출물:${NC} docs/specs/${feature_slug}/clarify.md"
      ;;

    plan)
      if [ -f "${specs_dir}/plan.md" ]; then
        local req_count
        req_count=$(grep -c "^- \*\*FR" "${specs_dir}/plan.md" 2>/dev/null || echo "0")
        echo -e "${BLUE}📋 요구사항:${NC} ${req_count}개 식별"

        local files_changed
        files_changed=$(grep -c "^\- " "${specs_dir}/plan.md" 2>/dev/null || echo "0")
        echo -e "${BLUE}📝 예상 파일:${NC} ${files_changed}개"
      fi
      echo ""
      echo -e "${YELLOW}➡️ 다음 단계:${NC} /design ${feature_slug}"
      echo -e "${BLUE}📄 산출물:${NC} docs/specs/${feature_slug}/plan.md"
      ;;

    design)
      if [ -f "${specs_dir}/design.md" ]; then
        local tech_decisions
        tech_decisions=$(grep -c "^### " "${specs_dir}/design.md" 2>/dev/null || echo "0")
        echo -e "${BLUE}🔧 기술 결정:${NC} ${tech_decisions}개"

        local files_to_change
        files_to_change=$(grep -c "| " "${specs_dir}/design.md" 2>/dev/null || echo "0")
        echo -e "${BLUE}📁 변경 파일:${NC} 약 ${files_to_change}개"
      fi
      echo ""
      echo -e "${YELLOW}➡️ 다음 단계:${NC} /implement ${feature_slug}"
      echo -e "${BLUE}📄 산출물:${NC} docs/specs/${feature_slug}/design.md"
      ;;

    implement|do)
      if [ -n "$extra_data" ]; then
        local tests_passed
        tests_passed=$(echo "$extra_data" | jq -r '.tests_passed // "N/A"' 2>/dev/null || echo "N/A")
        local tests_failed
        tests_failed=$(echo "$extra_data" | jq -r '.tests_failed // "N/A"' 2>/dev/null || echo "N/A")
        local files_changed
        files_changed=$(echo "$extra_data" | jq -r '.files_changed // "N/A"' 2>/dev/null || echo "N/A")

        [ "$tests_passed" != "N/A" ] && echo -e "${BLUE}✓ 테스트 통과:${NC} ${tests_passed}"
        [ "$tests_failed" != "N/A" ] && [ "$tests_failed" != "0" ] && echo -e "${YELLOW}✗ 테스트 실패:${NC} ${tests_failed}"
        [ "$files_changed" != "N/A" ] && echo -e "${BLUE}📁 파일 변경:${NC} ${files_changed}개"
      fi
      echo ""
      echo -e "${YELLOW}➡️ 다음 단계:${NC} /check ${feature_slug}"
      ;;

    check)
      if [ -n "$extra_data" ]; then
        local issues_found
        issues_found=$(echo "$extra_data" | jq -r '.issues_found // "N/A"' 2>/dev/null || echo "N/A")
        local iterations
        iterations=$(echo "$extra_data" | jq -r '.iterations // "N/A"' 2>/dev/null || echo "N/A")

        [ "$issues_found" != "N/A" ] && echo -e "${BLUE}🔍 발견 이슈:${NC} ${issues_found}개"
        [ "$iterations" != "N/A" ] && echo -e "${BLUE}🔄 반복 횟수:${NC} ${iterations}회"
      fi
      echo ""
      echo -e "${YELLOW}➡️ 다음 단계:${NC} /wrapup ${feature_slug}"
      ;;

    wrapup)
      if [ -f "${specs_dir}/wrapup.md" ]; then
        local summary
        summary=$(grep -A 10 "## 구현 개요" "${specs_dir}/wrapup.md" 2>/dev/null | head -5 || echo "")
        if [ -n "$summary" ]; then
          echo -e "${BLUE}📝 구현 요약:${NC}"
          echo "$summary" | sed 's/^/   /'
        fi
      fi
      echo ""
      echo -e "${GREEN}🎉 PDCA 사이클 완료!${NC}"
      echo -e "${BLUE}📄 산출물:${NC} docs/specs/${feature_slug}/"
      ;;
  esac

  echo ""
}

# ============================================================================
# 유틸리티 함수
# ============================================================================

# 시간 포맷팅
format_duration() {
  local seconds="${1:-0}"

  if [ $seconds -lt 60 ]; then
    echo "${seconds}초"
  elif [ $seconds -lt 3600 ]; then
    local minutes=$((seconds / 60))
    local secs=$((seconds % 60))
    echo "${minutes}분 ${secs}초"
  else
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    echo "${hours}시간 ${minutes}분"
  fi
}

# ============================================================================
# 진행 상황 표시 (실시간)
# ============================================================================

# PDCA 진행 상황 표시
show_pdca_progress() {
  local current_phase="${1:-}"
  local feature_slug="${2:-}"

  local phases=("clarify" "plan" "design" "implement" "check" "wrapup")
  local phase_names=("Clarify" "Plan" "Design" "Implement" "Check" "Wrap-up")
  local total=${#phases[@]}
  local current_index=0

  # 현재 단계 인덱스 찾기
  for i in "${!phases[@]}"; do
    if [[ "${phases[$i]}" == "$current_phase" ]]; then
      current_index=$((i + 1))
      break
    fi
  done

  local percentage=0
  if [ $current_index -gt 0 ]; then
    percentage=$((current_index * 100 / total))
  fi

  # 진행 바 생성
  local bar=""
  local filled=$((percentage / 10))
  local empty=$((10 - filled))

  for ((i = 0; i < filled; i++)); do
    bar+="█"
  done
  for ((i = 0; i < empty; i++)); do
    bar+="░"
  done

  # 상태 아이콘
  local icons=("")
  for phase in "${phases[@]}"; do
    local idx=$((${#icons[@]}))
    if [[ "$phase" == "$current_phase" ]]; then
      icons+=("○")
    elif [ $idx -lt $current_index ]; then
      icons+=("✓")
    else
      icons+=("○")
    fi
  done

  # 출력
  echo ""
  echo "[PDCA Progress] ${icons[0]} → ${icons[1]} → ${icons[2]} → ${icons[3]} → ${icons[4]} → ${icons[5]} (${current_index}/${total}) - ${percentage}%"
  echo "[${bar}] ${percentage}%"
  echo ""
}

# ============================================================================
# 통계 요약
# ============================================================================

# 세션 통계 요약
show_session_summary() {
  local project_root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  local harness_dir="${project_root}/.harness"

  if [ ! -d "$harness_dir" ]; then
    return 0
  fi

  local tool_calls=0
  if [ -f "${harness_dir}/state/tool-call-count" ]; then
    tool_calls=$(cat "${harness_dir}/state/tool-call-count" 2>/dev/null || echo "0")
  fi

  local session_start
  if [ -f "${harness_dir}/state/session-start-time" ]; then
    session_start=$(cat "${harness_dir}/state/session-start-time" 2>/dev/null || echo "")
  fi

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📊 세션 통계"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  🔧 도구 호출: ${tool_calls}회"

  if [ -n "$session_start" ]; then
    local current_time
    current_time=$(date +%s)
    local session_duration=$((current_time - session_start))
    echo "  ⏱️ 세션 시간: $(format_duration $session_duration)"
  fi

  # 완료된 기능 수
  local completed_features=0
  if [ -d "${project_root}/docs/specs" ]; then
    completed_features=$(find "${project_root}/docs/specs" -name "wrapup.md" 2>/dev/null | wc -l | tr -d ' ')
  fi
  echo "  ✅ 완료된 기능: ${completed_features}개"

  echo ""
}
