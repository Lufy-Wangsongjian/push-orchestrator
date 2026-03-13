#!/usr/bin/env bash
# push-orchestrator provider: market-brief
# Prefer real-data generators in workspace scripts; fallback to built-in price/news stub.
set -e

task_json=$(cat)
task_id=$(echo "$task_json" | jq -r '.id // "market-brief"')
SKILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKSPACE_ROOT="$(cd "$SKILL_ROOT/../../.." && pwd)"
SCRIPTS_DIR="$WORKSPACE_ROOT/scripts"

gen_from_workspace() {
  local py="$1"
  [[ -f "$py" ]] || return 1
  local out
  out=$(python3 "$py" 2>/dev/null | tail -n 1 || true)
  [[ -n "$out" && -f "$out" ]] || return 1
  cat "$out"
  return 0
}

content=""
if [[ "$task_id" == *"hk"* ]]; then
  content=$(gen_from_workspace "$SCRIPTS_DIR/hk_market_brief_real_data.py" || true)
  title="HK market brief"
  topic_key="market-hk:$(date '+%Y-%m-%d')"
else
  content=$(gen_from_workspace "$SCRIPTS_DIR/us_market_brief_real_data.py" || true)
  title="US market brief"
  topic_key="market-us:$(date '+%Y-%m-%d')"
fi

if [[ -z "$content" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  price_json=$(bash "$SCRIPT_DIR/market-price.sh" 2>/dev/null || echo '{"available":false}')
  news_json=$(bash "$SCRIPT_DIR/market-news.sh" 2>/dev/null || echo '{}')
  content=$(jq -n \
    --argjson p "$price_json" \
    --argjson n "$news_json" \
    '($p | if .available then "Price: \(.price) (\(.change))" else "Data unavailable" end) + "\n" + ($n.summary // "No news source configured.")')
fi

source_summary="market_brief"
data_timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

jq -n \
  --arg title "$title" \
  --arg topic_key "$topic_key" \
  --arg content "$content" \
  --arg source_summary "$source_summary" \
  --arg data_timestamp "$data_timestamp" \
  '{title:$title, topic_key:$topic_key, content:$content, source_summary:$source_summary, content_kind:"market", data_timestamp:$data_timestamp}'
