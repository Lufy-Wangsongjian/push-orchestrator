#!/usr/bin/env bash
# push-orchestrator lib: task parsing from tasks JSON file
# Requires jq. Usage: source this file, set PUSH_TASKS_FILE, then use get_task_by_id, etc.

get_task_by_id() {
  local task_id="$1"
  jq -r --arg id "$task_id" '.tasks[] | select(.id == $id) | @json' "${PUSH_TASKS_FILE:?PUSH_TASKS_FILE not set}" 2>/dev/null | head -1
}

get_task_ids() {
  jq -r '.tasks[] | .id' "${PUSH_TASKS_FILE:?PUSH_TASKS_FILE not set}" 2>/dev/null
}

get_task_field() {
  local task_json="$1"
  local field="$2"
  echo "$task_json" | jq -r --arg f "$field" '.[$f] // empty'
}

# Get content_kind for type=content (default to empty)
task_content_kind() {
  get_task_field "$1" "content_kind"
}

task_content_handler() {
  local json="$1"
  local handler
  handler=$(get_task_field "$json" "content_handler")
  if [[ -n "$handler" ]]; then
    echo "$handler"
  else
    get_task_field "$json" "content_kind"
  fi
}

task_dedupe_mode() {
  local json="$1"
  local mode
  mode=$(echo "$json" | jq -r '.dedupe.mode // empty')
  if [[ -n "$mode" ]]; then
    echo "$mode"
  else
    case "$(get_task_field "$json" "type")" in
      content) echo "hash_topic" ;;
      market)  echo "window" ;;
      *)       echo "none" ;;
    esac
  fi
}

task_dedupe_cooldown_days() {
  local json="$1"
  echo "$json" | jq -r '.dedupe.cooldown_days // 0'
}

# Export task snapshot for db (config_json = full task JSON)
task_snapshot_for_db() {
  local json="$1"
  local id name type provider severity enabled cron channel target archive_category
  id=$(get_task_field "$json" "id")
  name=$(get_task_field "$json" "name")
  type=$(get_task_field "$json" "type")
  content_kind=$(task_content_kind "$json")
  provider=$(get_task_field "$json" "provider")
  severity=$(get_task_field "$json" "severity")
  enabled=$(get_task_field "$json" "enabled")
  cron=$(get_task_field "$json" "cron")
  channel=$(get_task_field "$json" "channel")
  target=$(get_task_field "$json" "target")
  archive_category=$(get_task_field "$json" "archive_category")
  echo "$id|$name|$type|$content_kind|$provider|$severity|$enabled|$cron|$channel|$target|$archive_category"
}
