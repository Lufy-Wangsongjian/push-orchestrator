#!/usr/bin/env bash
# push-orchestrator lib: content handler dispatch and content-kind checks
# Content dispatcher calls into handlers by content_kind.

# Known content kinds (extensible: add new handler file under providers/content/<kind>.sh)
CONTENT_KINDS="book musical startup_idea coffee ai_news poem movie podcast rss_digest custom_prompt"

content_kind_valid() {
  local kind="$1"
  if [[ -z "$kind" ]]; then
    return 1
  fi
  # Allow any alphanumeric + underscore for extensibility
  [[ "$kind" =~ ^[a-z][a-z0-9_]*$ ]]
}

# Resolve handler script path. PUSH_SCRIPTS_DIR = directory containing providers/.
content_handler_script() {
  local kind="$1"
  local scripts_dir="${PUSH_SCRIPTS_DIR:?PUSH_SCRIPTS_DIR not set}"
  echo "${scripts_dir}/providers/content/${kind}.sh"
}

# Check if handler exists
content_handler_exists() {
  local kind="$1"
  local script
  script=$(content_handler_script "$kind")
  [[ -x "$script" ]] || [[ -f "$script" ]]
}

# Invoke content handler: stdout = JSON { title, topic_key, content, source_summary, content_kind }
# Handler receives task JSON on stdin and env: PUSH_TASK_JSON, PUSH_TEMPLATE_ROOT, PUSH_SOURCE_CONFIG (JSON)
invoke_content_handler() {
  local kind="$1"
  local task_json="$2"
  local script
  script=$(content_handler_script "$kind")
  if [[ ! -f "$script" ]]; then
    echo "{\"error\":\"handler not found: $kind\"}" >&2
    return 1
  fi
  export PUSH_TASK_JSON="$task_json"
  export PUSH_TEMPLATE_ROOT="${PUSH_TEMPLATE_ROOT:-.}"
  export PUSH_SOURCE_CONFIG
  PUSH_SOURCE_CONFIG=$(echo "$task_json" | jq -c '.source_config // {}')
  echo "$task_json" | bash "$script"
}
