#!/usr/bin/env bash

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./state.sh
source "$LIB_DIR/state.sh"

cff_verification_record_check() {
  local project_root="$1"
  local ticket_key="$2"
  local check_status="$3"
  local open_gaps="$4"
  local plan_compliance_score="$5"
  local class_a="$6"
  local class_b="$7"
  local class_c="$8"
  local class_d="$9"
  local ticket_path
  local now

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  now="$(cff_now_iso8601)"

  python3 - "$ticket_path" "$check_status" "$open_gaps" "$plan_compliance_score" "$class_a" "$class_b" "$class_c" "$class_d" "$now" <<'PY'
import json
import sys

(
    ticket_path,
    check_status,
    open_gaps,
    plan_compliance_score,
    class_a,
    class_b,
    class_c,
    class_d,
    now,
) = sys.argv[1:10]

with open(ticket_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

verification = data.setdefault("verification", {})
verification["last_check_status"] = check_status
verification["last_check_at"] = now
verification["open_gaps"] = int(open_gaps)
verification["plan_compliance_score"] = None if plan_compliance_score == "null" else int(plan_compliance_score)
verification["classes"] = {
    "A": class_a,
    "B": class_b,
    "C": class_c,
    "D": class_d,
}
data["updated_at"] = now

with open(ticket_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=True, indent=2)
    handle.write("\n")
PY
}

cff_verification_last_status() {
  local project_root="$1"
  local ticket_key="$2"
  local ticket_path

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  cff_json_get "$ticket_path" "verification.last_check_status" "not_run"
}

cff_verification_open_gaps() {
  local project_root="$1"
  local ticket_key="$2"
  local ticket_path

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  cff_json_get "$ticket_path" "verification.open_gaps" "0"
}

cff_verification_is_passing() {
  local project_root="$1"
  local ticket_key="$2"
  local ticket_path
  local last_status
  local open_gaps
  local class_a
  local class_b
  local class_d

  ticket_path="$(cff_ticket_state_path "$project_root" "$ticket_key")"
  last_status="$(cff_json_get "$ticket_path" "verification.last_check_status" "not_run")"
  open_gaps="$(cff_json_get "$ticket_path" "verification.open_gaps" "0")"
  class_a="$(cff_json_get "$ticket_path" "verification.classes.A" "not_run")"
  class_b="$(cff_json_get "$ticket_path" "verification.classes.B" "not_run")"
  class_d="$(cff_json_get "$ticket_path" "verification.classes.D" "not_run")"

  [[ "$last_status" == "passed" && "$open_gaps" == "0" && "$class_a" == "passed" && "$class_b" == "passed" && "$class_d" == "passed" ]]
}

