#!/usr/bin/env bash
# push-orchestrator lib: logging
# Standard log and JSON output helpers.
# Set PUSH_LOG_FORMAT=json for one-JSON-line-per-call (includes PUSH_RUN_ID, PUSH_TASK_ID when set).

push_log_level="${PUSH_LOG_LEVEL:-INFO}"
push_log_format="${PUSH_LOG_FORMAT:-text}"

log_ts() {
  date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%SZ'
}

_log_json() {
  local level="$1"
  shift
  local msg="$*"
  local run_id="${PUSH_RUN_ID:-}"
  local task_id="${PUSH_TASK_ID:-}"
  jq -n \
    --arg ts "$(log_ts)" \
    --arg level "$level" \
    --arg run_id "$run_id" \
    --arg task_id "$task_id" \
    --arg message "$msg" \
    '{ts:$ts, level:$level, run_id:$run_id, task_id:$task_id, message:$message}' 2>/dev/null || echo "{\"ts\":\"$(log_ts)\",\"level\":\"$level\",\"message\":\"$msg\"}"
}

log_info() {
  if [[ "$push_log_format" == "json" ]]; then
    _log_json "info" "$@" >&2
  else
    echo "[$(log_ts)] [INFO] $*" >&2
  fi
}

log_warn() {
  if [[ "$push_log_format" == "json" ]]; then
    _log_json "warn" "$@" >&2
  else
    echo "[$(log_ts)] [WARN] $*" >&2
  fi
}

log_error() {
  if [[ "$push_log_format" == "json" ]]; then
    _log_json "error" "$@" >&2
  else
    echo "[$(log_ts)] [ERROR] $*" >&2
  fi
}

log_debug() {
  if [[ "$push_log_level" == "DEBUG" ]]; then
    if [[ "$push_log_format" == "json" ]]; then
      _log_json "debug" "$@" >&2
    else
      echo "[$(log_ts)] [DEBUG] $*" >&2
    fi
  fi
}

# Optional: structured run stage (when PUSH_LOG_FORMAT=json)
# Usage: log_stage stage [duration_ms] [error_code]
log_stage() {
  local stage="$1"
  local duration_ms="${2:-}"
  local error_code="${3:-}"
  if [[ "$push_log_format" != "json" ]]; then return 0; fi
  local run_id="${PUSH_RUN_ID:-}"
  local task_id="${PUSH_TASK_ID:-}"
  local out
  out=$(jq -n \
    --arg ts "$(log_ts)" \
    --arg run_id "$run_id" \
    --arg task_id "$task_id" \
    --arg stage "$stage" \
    --arg duration_ms "$duration_ms" \
    --arg error_code "$error_code" \
    '{ts:$ts, run_id:$run_id, task_id:$task_id, stage:$stage, duration_ms:(if $duration_ms=="" then null else ($duration_ms|tonumber) end), error_code:(if $error_code=="" then null else ($error_code|tonumber) end)}' 2>/dev/null)
  [[ -n "$out" ]] && echo "$out" >&2
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
