#!/usr/bin/env bash
# push-orchestrator provider: reminder
# Reads task JSON from stdin, outputs JSON: title, topic_key, content, source_summary, content_kind (empty for reminder)
set -e
task_json=$(cat)
name=$(echo "$task_json" | jq -r '.name // "Reminder"')
body=$(echo "$task_json" | jq -r '.metadata.body // .source_config.body // "No message"')
title="Reminder: $name"
topic_key="reminder:$(echo "$task_json" | jq -r '.id')"
content="$body"
source_summary="reminder"
jq -n \
  --arg title "$title" \
  --arg topic_key "$topic_key" \
  --arg content "$content" \
  --arg source_summary "$source_summary" \
  '{title:$title, topic_key:$topic_key, content:$content, source_summary:$source_summary, content_kind:""}'
