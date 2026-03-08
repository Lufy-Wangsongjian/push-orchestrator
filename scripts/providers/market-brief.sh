#!/usr/bin/env bash
# push-orchestrator provider: market-brief (merge price + news)
# Reads task JSON from stdin. Calls market-price and market-news, merges output.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
price_json=$(bash "$SCRIPT_DIR/market-price.sh" 2>/dev/null || echo '{"available":false}')
news_json=$(bash "$SCRIPT_DIR/market-news.sh" 2>/dev/null || echo '{}')
title="Market brief"
topic_key="market:$(date '+%Y-%m-%d-%H')"
content=$(jq -n \
  --argjson p "$price_json" \
  --argjson n "$news_json" \
  '($p | if .available then "Price: \(.price) (\(.change))" else "Data unavailable" end) + "\n" + ($n.summary // "No news")')
source_summary="market_brief"
data_ts=$(echo "$price_json" | jq -r '.data_timestamp // empty')
jq -n \
  --arg title "$title" \
  --arg topic_key "$topic_key" \
  --arg content "$content" \
  --arg source_summary "$source_summary" \
  --arg data_timestamp "${data_ts:-}" \
  '{title:$title, topic_key:$topic_key, content:$content, source_summary:$source_summary, content_kind:"market", data_timestamp:$data_timestamp}'
