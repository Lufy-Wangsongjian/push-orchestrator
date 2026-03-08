#!/usr/bin/env bash
# push-orchestrator content handler: ai_news
set -e
task_json=$(cat)
kind="ai_news"
title=$(echo "$task_json" | jq -r '.source_config.title // "AI news digest"')
topic_key="ai_news:$(date '+%Y-%m-%d')"
content=$(echo "$task_json" | jq -r '.source_config.body // "AI news summary."')
source_summary="ai_news"
jq -n \
  --arg title "$title" \
  --arg topic_key "$topic_key" \
  --arg content "$content" \
  --arg source_summary "$source_summary" \
  --arg content_kind "$kind" \
  '{title:$title, topic_key:$topic_key, content:$content, source_summary:$source_summary, content_kind:$content_kind}'
