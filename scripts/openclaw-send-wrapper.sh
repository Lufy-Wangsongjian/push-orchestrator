#!/usr/bin/env bash
# push-orchestrator: wrapper so openclaw message send gets --channel/--target/--message
# Usage: openclaw-send-wrapper.sh <channel> <target> [body from stdin]
# Account: 若未设置 PUSH_SEND_ACCOUNT，则根据 PUSH_WORKSPACE 从 openclaw.json 解析当前 agent 绑定的 Telegram account。
set -e
channel="${1:?channel required}"
target="${2:-}"
body=$(cat)

# 解析发送账号：优先 PUSH_SEND_ACCOUNT，否则按 workspace 从 openclaw.json 查 telegram 绑定
resolve_account() {
  if [[ -n "${PUSH_SEND_ACCOUNT:-}" ]]; then
    echo "$PUSH_SEND_ACCOUNT"
    return
  fi
  local ws="${PUSH_WORKSPACE:-}"
  if [[ -z "$ws" ]]; then
    echo "default"
    return
  fi
  local cfg="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"
  if [[ ! -f "$cfg" ]]; then
    echo "default"
    return
  fi
  local agent_id
  agent_id=$(jq -r --arg w "$ws" '
    .agents.defaults.workspace as $def
    | .agents.list[] | select((.workspace // $def) == $w) | .id
  ' "$cfg" 2>/dev/null | head -n1)
  if [[ -z "$agent_id" ]] || [[ "$agent_id" == "null" ]]; then
    echo "default"
    return
  fi
  local acc
  acc=$(jq -r --arg a "$agent_id" '
    .bindings[] | select(.match.channel == "telegram" and .agentId == $a) | .match.accountId
  ' "$cfg" 2>/dev/null | head -n1)
  if [[ -n "$acc" ]] && [[ "$acc" != "null" ]]; then
    echo "$acc"
  else
    echo "default"
  fi
}

account=$(resolve_account)

OPENCLAW_BIN="${OPENCLAW_BIN:-$(command -v openclaw 2>/dev/null || true)}"
if [[ -z "$OPENCLAW_BIN" ]] && [[ -x "$HOME/.local/share/pnpm/openclaw" ]]; then
  OPENCLAW_BIN="$HOME/.local/share/pnpm/openclaw"
fi
if [[ -z "$OPENCLAW_BIN" ]]; then
  echo "openclaw binary not found (set OPENCLAW_BIN)" >&2
  exit 127
fi

if [[ -z "$body" ]]; then
  exec "$OPENCLAW_BIN" message send --channel "$channel" --target "$target" --account "$account" --message ""
fi
exec "$OPENCLAW_BIN" message send --channel "$channel" --target "$target" --account "$account" --message "$body"
