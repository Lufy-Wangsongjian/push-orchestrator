#!/usr/bin/env bash
# push-orchestrator content handler: custom_prompt
# Content from prompt/source_config; topic_key and title can be overridden.
set -e
task_json=$(cat)
kind="custom_prompt"
title=$(echo "$task_json" | jq -r '.source_config.title // .metadata.title // "Custom"')
topic_key=$(echo "$task_json" | jq -r '.source_config.topic_key // .metadata.topic_key // "custom:'"$(date '+%Y-%m-%d')"'"')
content=$(echo "$task_json" | jq -r '.source_config.body // .source_config.prompt // .metadata.body // "No content"')
source_summary=$(echo "$task_json" | jq -r '.source_config.source_summary // "custom_prompt"')
jq -n \
  --arg title "$title" \
  --arg topic_key "$topic_key" \
  --arg content "$content" \
  --arg source_summary "$source_summary" \
  --arg content_kind "$kind" \
  '{title:$title, topic_key:$topic_key, content:$content, source_summary:$source_summary, content_kind:$content_kind}'
