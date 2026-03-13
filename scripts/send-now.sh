#!/usr/bin/env bash
# push-orchestrator: 立即发一条消息到默认 channel/target（不写 DB、不走 cron）
# 用法: ./scripts/send-now.sh "消息内容"
# 用于「通过 Telegram 让 bot 马上发一条」的场景。发送账号由 PUSH_WORKSPACE 从 openclaw.json 自动解析。
set -e
SKILL_ROOT="${PUSH_SKILL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# 约定：skill 安装在 <workspace>/skills/<skill-name>，workspace = SKILL_ROOT/../.. ；兼容 .agents/skills 时 workspace = SKILL_ROOT/../../..
_push_parent="$(dirname "$SKILL_ROOT")"
_push_name="$(basename "$_push_parent")"
if [[ "$_push_name" == "skills" ]]; then
  [[ "$(basename "$(dirname "$_push_parent")")" == ".agents" ]] && export PUSH_WORKSPACE="${OPENCLAW_WORKSPACE:-$(cd "$SKILL_ROOT/../../.." && pwd)}" || export PUSH_WORKSPACE="${OPENCLAW_WORKSPACE:-$(cd "$SKILL_ROOT/../.." && pwd)}"
elif [[ "$_push_name" == ".agents" ]]; then
  export PUSH_WORKSPACE="${OPENCLAW_WORKSPACE:-$(cd "$SKILL_ROOT/../.." && pwd)}"
else
  export PUSH_WORKSPACE="${OPENCLAW_WORKSPACE:-$(cd "$SKILL_ROOT/.." && pwd)}"
fi
unset _push_parent _push_name
CONFIG="${SKILL_ROOT}/config/default.json"
body="${1:-}"
channel=$(jq -r '.defaultChannel // "telegram"' "$CONFIG")
target=$(jq -r '.defaultTarget // ""' "$CONFIG")
wrapper=$(jq -r '.sendCommand // ""' "$CONFIG")
if [[ -n "$wrapper" ]] && [[ "$wrapper" != /* ]]; then
  wrapper="$SKILL_ROOT/$wrapper"
fi
if [[ -z "$wrapper" ]] || [[ ! -x "$wrapper" ]]; then
  echo "sendCommand not set or not executable in $CONFIG" >&2
  exit 1
fi
if [[ -z "$body" ]]; then
  echo "Usage: $0 \"message body\"" >&2
  exit 1
fi
echo "$body" | PUSH_CHANNEL="$channel" PUSH_TARGET="$target" PUSH_WORKSPACE="$PUSH_WORKSPACE" "$wrapper"
