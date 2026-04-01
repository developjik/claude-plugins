#!/usr/bin/env bash

# Common helpers shared by colo-fe-flow shell libraries.

cff_now_iso8601() {
  python3 - <<'PY'
from datetime import datetime
print(datetime.now().astimezone().isoformat(timespec="seconds"))
PY
}

cff_json_get() {
  local file_path="$1"
  local json_path="$2"
  local default_value="${3-__CFF_NO_DEFAULT__}"

  python3 - "$file_path" "$json_path" "$default_value" <<'PY'
import json
import sys

file_path, json_path, default_value = sys.argv[1:4]
sentinel = "__CFF_NO_DEFAULT__"

try:
    with open(file_path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
except FileNotFoundError:
    if default_value != sentinel:
        print(default_value)
        raise SystemExit(0)
    raise

current = data
try:
    for part in json_path.split("."):
        if isinstance(current, list):
            current = current[int(part)]
        else:
            current = current[part]
except (KeyError, IndexError, ValueError, TypeError):
    if default_value != sentinel:
        print(default_value)
        raise SystemExit(0)
    raise

if current is None:
    print("null")
elif isinstance(current, bool):
    print("true" if current else "false")
elif isinstance(current, (dict, list)):
    print(json.dumps(current, ensure_ascii=True, separators=(",", ":")))
else:
    print(str(current))
PY
}

cff_json_write_pretty() {
  local file_path="$1"
  local payload="$2"

  python3 - "$file_path" "$payload" <<'PY'
import json
import sys

file_path, payload = sys.argv[1:3]
data = json.loads(payload)

with open(file_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=True, indent=2)
    handle.write("\n")
PY
}

cff_append_unique_line() {
  local file_path="$1"
  local line="$2"

  touch "$file_path"
  if ! grep -Fqx "$line" "$file_path"; then
    printf '%s\n' "$line" >> "$file_path"
  fi
}

cff_assert_ticket_key() {
  local ticket_key="$1"

  if [[ ! "$ticket_key" =~ ^[A-Z][A-Z0-9]+-[0-9]+$ ]]; then
    echo "invalid ticket key: $ticket_key" >&2
    return 1
  fi
}

