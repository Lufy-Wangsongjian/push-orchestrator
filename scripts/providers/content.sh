#!/usr/bin/env bash
# push-orchestrator provider: content dispatcher
# Dispatches by content_kind to providers/content/<kind>.sh. No hardcoded if/elif chain.
set -e
task_json=$(cat)
content_kind=$(echo "$task_json" | jq -r '.content_kind // empty')
content_handler=$(echo "$task_json" | jq -r '.content_handler // .content_kind // empty')
if [[ -z "$content_handler" ]]; then
  echo "{\"error\":\"content_kind required\"}" >&2
  exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PUSH_SCRIPTS_DIR="$SCRIPT_DIR/.."
export PUSH_TASK_JSON="$task_json"
export PUSH_TEMPLATE_ROOT="${PUSH_TEMPLATE_ROOT:-.}"
export PUSH_SOURCE_CONFIG
PUSH_SOURCE_CONFIG=$(echo "$task_json" | jq -c '.source_config // {}')
handler_script="${SCRIPT_DIR}/content/${content_handler}.sh"
if [[ ! -f "$handler_script" ]]; then
  echo "{\"error\":\"handler not found: $content_handler\"}" >&2
  exit 1
fi
echo "$task_json" | bash "$handler_script"
