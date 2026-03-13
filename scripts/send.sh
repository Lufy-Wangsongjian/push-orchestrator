#!/usr/bin/env bash
# push-orchestrator: send message via sendCommand (with retry)
# Reads payload JSON from stdin. Env: PUSH_SEND_COMMAND, PUSH_CHANNEL, PUSH_TARGET.
# Outputs JSON with message_id on success; exit 0 only when message_id is present.
set -e
payload=$(cat)
body=$(echo "$payload" | jq -r '.content // .body // .text // ""')
channel="${PUSH_CHANNEL:-}"
target="${PUSH_TARGET:-}"
send_cmd="${PUSH_SEND_COMMAND:?PUSH_SEND_COMMAND not set}"
max_attempts="${PUSH_SEND_MAX_ATTEMPTS:-3}"
# Backoff seconds per attempt (from config or default "2 6 15")
backoff_str="${PUSH_SEND_BACKOFF:-2 6 15}"
backoff_arr=($backoff_str)

send_one() {
  if [[ -n "$body" ]]; then
    echo "$body" | $send_cmd $channel $target 2>&1
  else
    $send_cmd $channel $target 2>&1
  fi
}

attempt=1
out=""
while [[ $attempt -le $max_attempts ]]; do
  out=$(send_one) || true
  message_id=$(echo "$out" | jq -r '.message_id // empty' 2>/dev/null || true)
  if [[ -z "$message_id" ]]; then
    # Fallback for human-readable CLI output, e.g. "✅ Sent via Telegram. Message ID: 1430"
    message_id=$(echo "$out" | sed -nE 's/.*Message ID:[[:space:]]*([0-9]+).*/\1/p' | tail -n1)
  fi
  if [[ -n "$message_id" ]]; then
    echo "{\"message_id\":\"$message_id\"}"
    exit 0
  fi
  if [[ $attempt -lt $max_attempts ]]; then
    idx=$((attempt - 1))
    sec="${backoff_arr[$idx]:-2}"
    sleep "${sec:-2}"
  fi
  attempt=$((attempt + 1))
done
echo "{\"error\":\"no message_id\",\"raw\":$(echo -n "$out" | jq -Rs .)}" >&2
exit 8
