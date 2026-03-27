#!/usr/bin/env bash
# skill-chain.sh — 스킬 체인 검증 유틸리티
# requires 필드를 기반으로 선행 스킬 완료 여부 확인

# ============================================================================
# 스킬 체인 검증
# ============================================================================

# 스킬의 requires 필드 확인
# Usage: get_skill_requires <skill_name>
get_skill_requires() {
  local skill_name="${1:-}"
  local plugin_root="${CLAUDE_PLUGIN_ROOT:-$(pwd)}"
  local skill_file="${plugin_root}/skills/${skill_name}/SKILL.md"

  if [ ! -f "$skill_file" ]; then
    echo ""
    return 0
  fi

  # frontmatter에서 requires 필드 추출
  grep -A 20 "^---$" "$skill_file" 2>/dev/null | head -25 | grep "^requires:" | sed 's/^requires:[[:space:]]*//' || echo ""
}

# 선행 문서 존재 확인
# Usage: check_prerequisite_doc <feature_slug> <required_phase>
check_prerequisite_doc() {
  local feature_slug="${1:-}"
  local required_phase="${2:-}"
  local project_root="${CLAUDE_PROJECT_DIR:-$(pwd)}"

  local required_doc
  case "$required_phase" in
    clarify)
      required_doc="${project_root}/docs/specs/${feature_slug}/clarify.md"
      ;;
    plan)
      required_doc="${project_root}/docs/specs/${feature_slug}/plan.md"
      ;;
    design)
      required_doc="${project_root}/docs/specs/${feature_slug}/design.md"
      ;;
    implement|do)
      required_doc="${project_root}/docs/specs/${feature_slug}/design.md"
      ;;
    check)
      # check는 구현 후이므로 코드 존재 여부로 판단 (생략)
      return 0
      ;;
    wrapup)
      # wrapup은 check 후 (생략)
      return 0
      ;;
    *)
      return 0
      ;;
  esac

  if [ -f "$required_doc" ]; then
    return 0
  else
    return 1
  fi
}

# 스킬 체인 검증 메인 함수
# Usage: validate_skill_chain <skill_name> <feature_slug>
validate_skill_chain() {
  local skill_name="${1:-}"
  local feature_slug="${2:-}"
  local project_root="${CLAUDE_PROJECT_DIR:-$(pwd)}"

  if [ -z "$skill_name" ] || [ -z "$feature_slug" ]; then
    return 0
  fi

  # requires 필드 확인
  local requires
  requires=$(get_skill_requires "$skill_name")

  if [ -z "$requires" ]; then
    # requires가 없으면 검증 없이 통과
    return 0
  fi

  # 선행 문서 확인
  if ! check_prerequisite_doc "$feature_slug" "$requires"; then
    # 선행 문서가 없으면 실패
    echo "MISSING_PREREQUISITE"
    return 1
  fi

  return 0
}

# 차단 메시지 생성
# Usage: generate_chain_block_message <skill_name> <requires> <feature_slug>
generate_chain_block_message() {
  local skill_name="${1:-}"
  local requires="${2:-}"
  local feature_slug="${3:-}"

  local phase_names
  declare -A phase_names=(
    ["clarify"]="Clarify (요청 구체화)"
    ["plan"]="Plan (요구사항 정의)"
    ["design"]="Design (기술 설계)"
    ["implement"]="Implement (TDD 구현)"
    ["check"]="Check (검증)"
    ["wrapup"]="Wrap-up (문서화)"
  )

  local required_name="${phase_names[$requires]:-$requires}"
  local current_name="${phase_names[$skill_name]:-$skill_name}"

  cat <<EOF
{
  "decision": "block",
  "error_code": "E501",
  "reason": "스킬 체인 검증 실패: 선행 단계가 완료되지 않았습니다",
  "details": {
    "current_skill": "$skill_name",
    "required_phase": "$requires",
    "feature_slug": "$feature_slug"
  },
  "suggestion": "${required_name} 단계를 먼저 완료하세요: /${requires} ${feature_slug}",
  "workflow": "PDCA 순서: Clarify → Plan → Design → Implement → Check → Wrap-up"
}
EOF
}

# 경고 메시지 생성 (차단하지 않고 경고만)
# Usage: generate_chain_warning_message <skill_name> <requires> <feature_slug>
generate_chain_warning_message() {
  local skill_name="${1:-}"
  local requires="${2:-}"
  local feature_slug="${3:-}"

  cat <<EOF
{
  "decision": "allow",
  "warning": "선행 단계 문서가 없습니다. 진행하기 전에 /${requires} ${feature_slug} 실행을 권장합니다.",
  "warning_code": "W501"
}
EOF
}

# ============================================================================
# 통합 검증 함수
# ============================================================================

# 스킬 체인 검증 및 결과 반환
# Usage: check_and_validate_chain <skill_name> <feature_slug> [strict_mode]
# strict_mode가 "true"면 차단, 아니면 경고만
check_and_validate_chain() {
  local skill_name="${1:-}"
  local feature_slug="${2:-}"
  local strict_mode="${3:-false}"
  local project_root="${CLAUDE_PROJECT_DIR:-$(pwd)}"

  # requires 확인
  local requires
  requires=$(get_skill_requires "$skill_name")

  if [ -z "$requires" ]; then
    return 0
  fi

  # 선행 문서 확인
  if ! check_prerequisite_doc "$feature_slug" "$requires"; then
    if [ "$strict_mode" == "true" ]; then
      generate_chain_block_message "$skill_name" "$requires" "$feature_slug"
      return 1
    else
      generate_chain_warning_message "$skill_name" "$requires" "$feature_slug"
      return 0
    fi
  fi

  return 0
}

# ============================================================================
# 에이전트-스킬 매핑
# ============================================================================

# 에이전트 이름으로 스킬 이름 추론
# Usage: infer_skill_from_agent <agent_name>
infer_skill_from_agent() {
  local agent_name="${1:-}"

  # 에이전트 이름에서 스킬 이름 추출
  case "$agent_name" in
    strategist|harness-engineering:strategist)
      echo "plan"
      ;;
    architect|harness-engineering:architect)
      echo "design"
      ;;
    engineer|harness-engineering:engineer)
      echo "implement"
      ;;
    guardian|harness-engineering:guardian)
      echo "check"
      ;;
    librarian|harness-engineering:librarian)
      echo "wrapup"
      ;;
    debugger|harness-engineering:debugger)
      echo "debug"
      ;;
    *)
      # 패턴 매칭 시도
      if [[ "$agent_name" == *":"* ]]; then
        echo "${agent_name##*:}"
      else
        echo "$agent_name"
      fi
      ;;
  esac
}
