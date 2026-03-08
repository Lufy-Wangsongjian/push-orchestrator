#!/usr/bin/env bash
# push-orchestrator content handler: poem
set -e
task_json=$(cat)
kind="poem"
title=$(echo "$task_json" | jq -r '.source_config.title // "Poem"')
topic_key="poem:$(date '+%Y-%m-%d')"
content=$(echo "$task_json" | jq -r '.source_config.body // "A poem for the day."')
source_summary="poem"
jq -n \
  --arg title "$title" \
  --arg topic_key "$topic_key" \
  --arg content "$content" \
  --arg source_summary "$source_summary" \
  --arg content_kind "$kind" \
  '{title:$title, topic_key:$topic_key, content:$content, source_summary:$source_summary, content_kind:$content_kind}'
