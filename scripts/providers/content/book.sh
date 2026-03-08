#!/usr/bin/env bash
# push-orchestrator content handler: book
# Outputs JSON: title, topic_key, content, source_summary, content_kind
set -e
task_json=$(cat)
kind="book"
title=$(echo "$task_json" | jq -r '.source_config.title // "Book recommendation"')
topic_key="book:$(date '+%Y-%m-%d')"
content=$(echo "$task_json" | jq -r '.source_config.body // "A book worth reading."')
source_summary="book"
jq -n \
  --arg title "$title" \
  --arg topic_key "$topic_key" \
  --arg content "$content" \
  --arg source_summary "$source_summary" \
  --arg content_kind "$kind" \
  '{title:$title, topic_key:$topic_key, content:$content, source_summary:$source_summary, content_kind:$content_kind}'
