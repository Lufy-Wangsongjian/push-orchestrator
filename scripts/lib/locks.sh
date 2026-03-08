#!/usr/bin/env bash
# push-orchestrator lib: task-level lock (flock when available, else mkdir+pid fallback)
# Usage: source this file, then use lock_acquire / lock_release

LOCK_TIMEOUT_SECONDS="${PUSH_LOCK_TIMEOUT:-300}"

_lock_acquire_flock() {
  local task_id="$1"
  local lock_dir="${PUSH_LOCK_DIR:-/tmp/push-orchestrator/locks}"
  mkdir -p "$lock_dir"
  local lock_file="${lock_dir}/${task_id}.lock"
  exec 200>"$lock_file"
  if flock -w "$LOCK_TIMEOUT_SECONDS" 200 2>/dev/null; then
    echo "$lock_file"
    return 0
  fi
  exec 200>&-
  return 1
}

_lock_acquire_mkdir() {
  local task_id="$1"
  local lock_dir="${PUSH_LOCK_DIR:-/tmp/push-orchestrator/locks}"
  mkdir -p "$lock_dir"
  local lock_dir_lock="${lock_dir}/${task_id}.lock.d"
  local start_ts=$(date '+%s')
  while true; do
    if mkdir "$lock_dir_lock" 2>/dev/null; then
      echo "$$" > "${lock_dir_lock}/pid"
      echo "$lock_dir_lock"
      return 0
    fi
    local pid=$(cat "${lock_dir_lock}/pid" 2>/dev/null)
    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
      rm -rf "$lock_dir_lock"
      continue
    fi
    local now=$(date '+%s')
    if [[ $((now - start_ts)) -ge $LOCK_TIMEOUT_SECONDS ]]; then
      return 1
    fi
    sleep 1
  done
}

lock_acquire() {
  local task_id="$1"
  if command -v flock >/dev/null 2>&1; then
    _lock_acquire_flock "$task_id"
  else
    _lock_acquire_mkdir "$task_id"
  fi
}

lock_release() {
  local lock_path="${LOCK_PATH:-}"
  if [[ -z "$lock_path" ]]; then
    exec 200>&- 2>/dev/null || true
    return 0
  fi
  if [[ -d "$lock_path" ]]; then
    rm -rf "$lock_path"
  fi
  exec 200>&- 2>/dev/null || true
  return 0
}
