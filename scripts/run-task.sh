#!/usr/bin/env bash
# push-orchestrator: run a single task (orchestration only; content from providers)
set -e
SKILL_ROOT="${PUSH_SKILL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${SKILL_ROOT}/config/default.json"
TASKS_FILE=""
TASK_ID=""
MODE="normal"
FORCE="0"
DRY_RUN="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tasks) TASKS_FILE="$2"; shift 2 ;;
    --task)  TASK_ID="$2"; shift 2 ;;
    --mode)  MODE="$2"; shift 2 ;;
    --force) FORCE="1"; shift ;;
    --dry-run) DRY_RUN="1"; shift ;;
    *) shift ;;
  esac
done

if [[ -z "$TASKS_FILE" ]] || [[ -z "$TASK_ID" ]]; then
  echo "Usage: run-task.sh --tasks <tasks_file> --task <task_id> [--mode normal|backfill|rerun] [--force] [--dry-run]" >&2
  exit 1
fi

export PUSH_SKILL_ROOT="$SKILL_ROOT"
export PUSH_TASKS_FILE="$SKILL_ROOT/$TASKS_FILE"
export PUSH_CONFIG="$CONFIG"
export PUSH_DB_PATH
export PUSH_LOCK_DIR
export PUSH_SEND_COMMAND
export PUSH_CHANNEL
export PUSH_TARGET
export PUSH_TZ
export PUSH_CONTENT_ARCHIVE_DIR
export PUSH_TEMPLATE_ROOT

# Load config
if [[ ! -f "$CONFIG" ]]; then
  CONFIG="$SKILL_ROOT/config/default.json"
fi
PUSH_DB_PATH="$SKILL_ROOT/$(jq -r '.stateDbPath // "./state/push.db"' "$CONFIG")"
PUSH_LOCK_DIR="$SKILL_ROOT/$(jq -r '.lockDir // "/tmp/push-orchestrator/locks"' "$CONFIG")"
if [[ "$PUSH_LOCK_DIR" == /* ]]; then
  :;
else
  PUSH_LOCK_DIR="$SKILL_ROOT/$PUSH_LOCK_DIR"
fi
PUSH_SEND_COMMAND=$(jq -r '.sendCommand // "openclaw message send"' "$CONFIG")
PUSH_TZ=$(jq -r '.timezone // "Asia/Shanghai"' "$CONFIG")
PUSH_CONTENT_ARCHIVE_DIR="$SKILL_ROOT/$(jq -r '.contentArchiveDir // "./state/content_archive"' "$CONFIG")"
PUSH_TEMPLATE_ROOT="$SKILL_ROOT/templates"

# Validate
export PUSH_TASKS_FILE
"$SCRIPT_DIR/validate-config.sh" || exit 1
"$SCRIPT_DIR/init-db.sh" || exit 1

# Resolve task
if [[ ! -f "$PUSH_TASKS_FILE" ]]; then
  echo "Tasks file not found: $PUSH_TASKS_FILE" >&2
  exit 1
fi
source "$SCRIPT_DIR/lib/task.sh"
source "$SCRIPT_DIR/lib/db.sh"
source "$SCRIPT_DIR/lib/logging.sh"
source "$SCRIPT_DIR/lib/time.sh"

task_json=$(get_task_by_id "$TASK_ID")
if [[ -z "$task_json" ]]; then
  log_error "Task not found: $TASK_ID"
  exit 1
fi

enabled=$(get_task_field "$task_json" "enabled")
if [[ "$enabled" == "false" ]] && [[ "$FORCE" != "1" ]]; then
  log_info "Task disabled: $TASK_ID"
  exit 0
fi

export TZ="$PUSH_TZ"
task_type=$(get_task_field "$task_json" "type")
task_provider=$(get_task_field "$task_json" "provider")
task_content_kind=$(task_content_kind "$task_json")
channel=$(get_task_field "$task_json" "channel")
target=$(get_task_field "$task_json" "target")
PUSH_CHANNEL="${channel:-$(jq -r '.defaultChannel // "telegram"' "$CONFIG")}"
PUSH_TARGET="${target:-$(jq -r '.defaultTarget // ""' "$CONFIG")}"

# Helper: record failure and exit (run_id, started_at must be set if we already have them)
record_failure_and_exit() {
  local code="$1"
  local msg="$2"
  local run_id_val="${3:-$run_id}"
  local started_at_val="${4:-$started_at}"
  local date_bucket
  date_bucket=$(date '+%Y-%m-%d')
  if [[ -n "$run_id_val" ]] && [[ -n "$started_at_val" ]]; then
    db_insert_run "$run_id_val" "$TASK_ID" "$task_type" "$task_content_kind" "cron" "$MODE" "failed" "$code" "$msg" "$started_at_val" "$(date -u '+%Y-%m-%d %H:%M:%S')" 0 "" "" "" "" ""
  fi
  db_upsert_runtime_state "$TASK_ID" "$task_type" "$task_content_kind" "failed" "${started_at_val:-$(date -u '+%Y-%m-%d %H:%M:%S')}" "" "$code" "$msg" 0
  db_upsert_failure_stat "$date_bucket" "$TASK_ID" "$task_content_kind" "$code" 1
  exit "$code"
}

# Lock
source "$SCRIPT_DIR/lib/locks.sh"
lock_file=$(lock_acquire "$TASK_ID") || {
  run_id="run-$(date '+%Y%m%d%H%M%S')-$$"
  started_at=$(date -u '+%Y-%m-%d %H:%M:%S')
  record_failure_and_exit 2 "LOCK_ACQUIRE_FAILED" "$run_id" "$started_at"
}
export LOCK_PATH="$lock_file"
trap 'lock_release' EXIT

run_id="run-$(date '+%Y%m%d%H%M%S')-$$"
started_at=$(date -u '+%Y-%m-%d %H:%M:%S')
start_epoch=$(now_epoch)

# Dedupe (unless force or backfill)
dedupe_mode=$(task_dedupe_mode "$task_json")
payload_hash=""
topic_key=""
if [[ "$FORCE" != "1" ]] && [[ "$MODE" != "backfill" ]] && [[ "$dedupe_mode" != "none" ]]; then
  # Run provider to get payload for hash/topic
  provider_script="$SCRIPT_DIR/providers/${task_provider}.sh"
  if [[ ! -f "$provider_script" ]]; then
    log_error "Provider not found: $task_provider"
    exit 11
  fi
  payload=$(echo "$task_json" | bash "$provider_script" 2>/dev/null) || true
  if echo "$payload" | jq -e '.error' >/dev/null 2>&1; then
    log_error "Provider failed: $(echo "$payload" | jq -r '.error')"
    exit 11
  fi
  payload_hash=$(echo -n "$(echo "$payload" | jq -c .)" | sha256sum | cut -d' ' -f1)
  topic_key=$(echo "$payload" | jq -r '.topic_key // empty')
  if [[ "$dedupe_mode" == "hash" ]] || [[ "$dedupe_mode" == "hash_topic" ]]; then
    if db_dedupe_hash_hit "$TASK_ID" "$payload_hash"; then
      log_info "Dedupe hash hit: $TASK_ID"
      db_insert_run "$run_id" "$TASK_ID" "$task_type" "$task_content_kind" "cron" "$MODE" "dedupe_hit" 3 "DEDUPE_HIT" "$started_at" "$(date -u '+%Y-%m-%d %H:%M:%S')" 0 "" "" "" "" ""
      exit 3
    fi
  fi
  if [[ -n "$topic_key" ]] && { [[ "$dedupe_mode" == "topic_cooldown" ]] || [[ "$dedupe_mode" == "hash_topic" ]]; }; then
    cooldown_days=$(task_dedupe_cooldown_days "$task_json")
    until_epoch=$(db_dedupe_topic_cooldown_until "$TASK_ID" "$topic_key")
    if [[ -n "$until_epoch" ]] && [[ "$(date '+%s')" -lt "$until_epoch" ]]; then
      log_info "Dedupe topic cooldown hit: $TASK_ID"
      db_insert_run "$run_id" "$TASK_ID" "$task_type" "$task_content_kind" "cron" "$MODE" "dedupe_hit" 3 "DEDUPE_HIT" "$started_at" "$(date -u '+%Y-%m-%d %H:%M:%S')" 0 "" "" "" "" ""
      exit 3
    fi
  fi
  # Re-use payload below
else
  # Run provider to get payload
  provider_script="$SCRIPT_DIR/providers/${task_provider}.sh"
  payload=$(echo "$task_json" | bash "$provider_script" 2>/dev/null) || true
  if echo "$payload" | jq -e '.error' >/dev/null 2>&1; then
    log_error "Provider failed: $(echo "$payload" | jq -r '.error')"
    record_failure_and_exit 11 "PROVIDER_FAILED"
  fi
  payload_hash=$(echo -n "$(echo "$payload" | jq -c .)" | sha256sum | cut -d' ' -f1)
  topic_key=$(echo "$payload" | jq -r '.topic_key // empty')
fi

# Validate payload
export PUSH_TASK_TYPE="$task_type"
export PUSH_TASK_CONTENT_KIND="$task_content_kind"
echo "$payload" | "$SCRIPT_DIR/validate-payload.sh" /dev/stdin || record_failure_and_exit 10 "PAYLOAD_INVALID"

# Send (unless dry-run)
message_id=""
if [[ "$DRY_RUN" == "1" ]]; then
  log_info "Dry-run: would send"
  message_id="dry-run"
else
  send_out=$(echo "$payload" | "$SCRIPT_DIR/send.sh" 2>/dev/null) || true
  message_id=$(echo "$send_out" | jq -r '.message_id // empty')
  if [[ -z "$message_id" ]]; then
    end_epoch=$(now_epoch)
    finished_at=$(date -u '+%Y-%m-%d %H:%M:%S')
    duration_ms=$(( (end_epoch - start_epoch) * 1000 ))
    db_insert_run "$run_id" "$TASK_ID" "$task_type" "$task_content_kind" "cron" "$MODE" "failed" 8 "SEND_REJECTED" "$started_at" "$finished_at" "$duration_ms" "" "$payload_hash" "" "$(echo "$payload" | jq -r '.source_summary // ""')"
    db_upsert_runtime_state "$TASK_ID" "$task_type" "$task_content_kind" "failed" "$finished_at" "" 8 "SEND_REJECTED" "$duration_ms"
    db_upsert_failure_stat "$(date '+%Y-%m-%d')" "$TASK_ID" "$task_content_kind" 8 1
    log_error "Send failed: no message_id"
    exit 8
  fi
fi

finished_at=$(date -u '+%Y-%m-%d %H:%M:%S')
end_epoch=$(now_epoch)
duration_ms=$(( (end_epoch - start_epoch) * 1000 ))
data_ts=$(echo "$payload" | jq -r '.data_timestamp // empty')
source_summary=$(echo "$payload" | jq -r '.source_summary // ""')

# Upsert task snapshot
snap=$(task_snapshot_for_db "$task_json")
IFS='|' read -r id name type ck provider severity enabled cron ch target arch_cat <<< "$snap"
config_json_escaped=$(echo "$task_json" | jq -c . | sed "s/'/''/g")
db_upsert_task "$id" "$name" "$type" "$ck" "$provider" "$severity" "$enabled" "$cron" "$ch" "$target" "$arch_cat" "$config_json_escaped" "$finished_at"

# Insert run
db_insert_run "$run_id" "$TASK_ID" "$task_type" "$task_content_kind" "cron" "$MODE" "success" 0 "" "$started_at" "$finished_at" "$duration_ms" "$message_id" "$payload_hash" "$data_ts" "$source_summary"

# Runtime state
db_upsert_runtime_state "$TASK_ID" "$task_type" "$task_content_kind" "success" "$finished_at" "$message_id" 0 "" "$duration_ms"

# Dedupe record (on success, and not backfill)
if [[ "$MODE" != "backfill" ]] && [[ "$DRY_RUN" != "1" ]]; then
  cooldown_days=$(task_dedupe_cooldown_days "$task_json")
  sent_epoch=$(date '+%s')
  cooldown_until=$(cooldown_until_epoch "$sent_epoch" "$cooldown_days")
  title=$(echo "$payload" | jq -r '.title // ""')
  db_insert_dedupe "$TASK_ID" "$task_type" "$task_content_kind" "$payload_hash" "$topic_key" "$title" "$source_summary" "$finished_at" "$cooldown_until" "$dedupe_mode"
fi

# Content archive
archive_enabled=$(echo "$task_json" | jq -r '.archive_enabled // false')
if [[ "$archive_enabled" == "true" ]] && [[ "$DRY_RUN" != "1" ]]; then
  archive_id="arch-$(date '+%Y%m%d%H%M%S')-$$"
  arch_cat=$(echo "$task_json" | jq -r '.archive_category // .content_kind // "misc"')
  subdir="${PUSH_CONTENT_ARCHIVE_DIR}/${arch_cat}"
  mkdir -p "$subdir"
  content_path="${subdir}/${archive_id}.md"
  echo "$payload" | jq -r '.content // ""' > "$content_path"
  db_insert_content_archive "$archive_id" "$TASK_ID" "${task_content_kind:-task}" "$arch_cat" "$topic_key" "$(echo "$payload" | jq -r '.title // ""')" "$content_path" "$source_summary" "$finished_at" "$finished_at"
fi

# Replay record if replay mode
if [[ "$MODE" == "backfill" ]] || [[ "$MODE" == "rerun" ]]; then
  replay_id="replay-$(date '+%Y%m%d%H%M%S')-$$"
  db_insert_replay_record "$replay_id" "$TASK_ID" "$task_content_kind" "$(date '+%Y-%m-%d')" "$MODE" "$FORCE" "completed" "$finished_at"
fi

echo "{\"run_id\":\"$run_id\",\"status\":\"success\",\"message_id\":\"$message_id\"}"
exit 0
