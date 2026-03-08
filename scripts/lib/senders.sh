#!/usr/bin/env bash
# push-orchestrator lib: send command construction and message_id parsing
# sendCommand and target come from config/task.

build_send_command() {
  local send_cmd="${PUSH_SEND_COMMAND:?PUSH_SEND_COMMAND not set}"
  local channel="${1:-$PUSH_CHANNEL}"
  local target="${2:-$PUSH_TARGET}"
  local body="$3"
  if [[ -z "$body" ]]; then
    echo "$send_cmd" "$channel" "$target"
    return
  fi
  # Assume send command accepts: sendCommand channel target [body from stdin or --body]
  # Common pattern: openclaw message send telegram <target> with body on stdin
  echo "$send_cmd" "$channel" "$target"
}

# Parse message_id from provider/send stdout (JSON line or key=value)
parse_message_id() {
  local output="$1"
  local id
  id=$(echo "$output" | jq -r '.message_id // empty' 2>/dev/null)
  if [[ -n "$id" ]]; then
    echo "$id"
    return
  fi
  id=$(echo "$output" | grep -oE 'message_id["\s:=]+[^",\s]+' | sed 's/.*["\s:=]\+//')
  echo "$id"
}
