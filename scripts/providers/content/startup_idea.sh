#!/usr/bin/env bash
# push-orchestrator content handler: startup_idea
set -e
task_json=$(cat)
kind="startup_idea"
title=$(echo "$task_json" | jq -r '.source_config.title // "Startup idea"')
topic_key="startup:$(date '+%Y-%m-%d')"
content=$(echo "$task_json" | jq -r '.source_config.body // "An idea worth exploring."')
source_summary="startup_idea"
jq -n \
  --arg title "$title" \
  --arg topic_key "$topic_key" \
  --arg content "$content" \
  --arg source_summary "$source_summary" \
  --arg content_kind "$kind" \
  '{title:$title, topic_key:$topic_key, content:$content, source_summary:$source_summary, content_kind:$content_kind}'
