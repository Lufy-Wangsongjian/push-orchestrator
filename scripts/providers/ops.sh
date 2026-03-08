#!/usr/bin/env bash
# push-orchestrator provider: ops (monitor / maintenance / test_push)
set -e
task_json=$(cat)
name=$(echo "$task_json" | jq -r '.name // "Ops"')
title="Ops: $name"
topic_key="ops:$(echo "$task_json" | jq -r '.id'):$(date '+%Y-%m-%d-%H')"
content=$(echo "$task_json" | jq -r '.source_config.body // .metadata.body // "Ops check OK"')
source_summary="ops"
jq -n \
  --arg title "$title" \
  --arg topic_key "$topic_key" \
  --arg content "$content" \
  --arg source_summary "$source_summary" \
  '{title:$title, topic_key:$topic_key, content:$content, source_summary:$source_summary, content_kind:""}'
