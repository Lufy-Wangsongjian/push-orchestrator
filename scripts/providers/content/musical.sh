#!/usr/bin/env bash
# push-orchestrator content handler: musical
set -e
task_json=$(cat)
kind="musical"
title=$(echo "$task_json" | jq -r '.source_config.title // "Musical pick"')
topic_key="musical:$(date '+%Y-%m-%d')"
content=$(echo "$task_json" | jq -r '.source_config.body // "A musical recommendation."')
source_summary="musical"
jq -n \
  --arg title "$title" \
  --arg topic_key "$topic_key" \
  --arg content "$content" \
  --arg source_summary "$source_summary" \
  --arg content_kind "$kind" \
  '{title:$title, topic_key:$topic_key, content:$content, source_summary:$source_summary, content_kind:$content_kind}'
