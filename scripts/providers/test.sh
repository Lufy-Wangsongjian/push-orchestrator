#!/usr/bin/env bash
# push-orchestrator provider: test (stub for testing pipeline)
set -e
task_json=$(cat)
title="Test push"
topic_key="test:$(date '+%s')"
content="Test message from push-orchestrator."
source_summary="test"
jq -n \
  --arg title "$title" \
  --arg topic_key "$topic_key" \
  --arg content "$content" \
  --arg source_summary "$source_summary" \
  '{title:$title, topic_key:$topic_key, content:$content, source_summary:$source_summary, content_kind:""}'
