#!/usr/bin/env bash
# push-orchestrator lib: logging
# Standard log and JSON output helpers.

push_log_level="${PUSH_LOG_LEVEL:-INFO}"

log_ts() {
  date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%SZ'
}

log_info() {
  echo "[$(log_ts)] [INFO] $*" >&2
}

log_warn() {
  echo "[$(log_ts)] [WARN] $*" >&2
}

log_error() {
  echo "[$(log_ts)] [ERROR] $*" >&2
}

log_debug() {
  if [[ "$push_log_level" == "DEBUG" ]]; then
    echo "[$(log_ts)] [DEBUG] $*" >&2
  fi
}

# Output a JSON object (one line). Keys and string values must be safe.
json_output() {
  local key val
  local first=1
  echo -n '{'
  while [[ $# -ge 2 ]]; do
    key="$1"
    val="$2"
    shift 2
    [[ $first -eq 0 ]] && echo -n ','
    first=0
    printf '%s:"%s"' "$key" "$(echo -n "$val" | sed 's/\\/\\\\/g; s/"/\\"/g')"
  done
  echo '}'
}
