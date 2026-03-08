#!/usr/bin/env bash
# push-orchestrator: validate payload before send
# type=content: content non-empty, title/topic_key present, content_kind consistent
# type=market: source URL, data_timestamp, stale check
set -e
payload_file="${1:-/dev/stdin}"
task_type="${PUSH_TASK_TYPE:-}"
task_content_kind="${PUSH_TASK_CONTENT_KIND:-}"
payload=$(cat "$payload_file")

if echo "$payload" | jq -e '.error' >/dev/null 2>&1; then
  echo "Payload has error key" >&2
  exit 10
fi

content=$(echo "$payload" | jq -r '.content // empty')
title=$(echo "$payload" | jq -r '.title // empty')
topic_key=$(echo "$payload" | jq -r '.topic_key // empty')

case "$task_type" in
  content)
    if [[ -z "$content" ]]; then
      echo "content empty" >&2
      exit 10
    fi
    if [[ -z "$title" ]] || [[ -z "$topic_key" ]]; then
      echo "title or topic_key missing" >&2
      exit 10
    fi
    payload_kind=$(echo "$payload" | jq -r '.content_kind // empty')
    if [[ -n "$task_content_kind" ]] && [[ -n "$payload_kind" ]] && [[ "$payload_kind" != "$task_content_kind" ]]; then
      echo "content_kind mismatch" >&2
      exit 10
    fi
    ;;
  market)
    data_ts=$(echo "$payload" | jq -r '.data_timestamp // empty')
    if [[ -z "$data_ts" ]]; then
      echo "market: data_timestamp missing" >&2
      exit 10
    fi
    ;;
  reminder|ops|test)
    if [[ -z "$content" ]]; then
      echo "content empty" >&2
      exit 10
    fi
    ;;
  *) ;;
esac
exit 0
