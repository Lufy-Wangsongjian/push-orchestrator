#!/usr/bin/env bash
# push-orchestrator: sync crontab from tasks file (manage own block only, idempotent)
set -e
SKILL_ROOT="${PUSH_SKILL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${SKILL_ROOT}/config/default.json"
TASKS_FILE=""
DRY_RUN="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tasks) TASKS_FILE="$2"; shift 2 ;;
    --dry-run) DRY_RUN="1"; shift ;;
    *) shift ;;
  esac
done

if [[ -z "$TASKS_FILE" ]]; then
  echo "Usage: sync-cron.sh --tasks <path_to_tasks.json> [--dry-run]" >&2
  exit 1
fi

# Resolve tasks path: absolute as-is, else under SKILL_ROOT
if [[ "$TASKS_FILE" == /* ]]; then
  TASKS_PATH="$TASKS_FILE"
else
  TASKS_PATH="$SKILL_ROOT/$TASKS_FILE"
fi
if [[ ! -f "$TASKS_PATH" ]]; then
  echo "Tasks file not found: $TASKS_PATH" >&2
  exit 1
fi
# For cron lines use absolute path so run-task works regardless of cwd
TASKS_PATH_ABS="$(cd "$(dirname "$TASKS_PATH")" 2>/dev/null && pwd)/$(basename "$TASKS_PATH")"

export TZ=$(jq -r '.timezone // "Asia/Shanghai"' "$CONFIG")
MARKER_BEGIN="# push-orchestrator begin"
MARKER_END="# push-orchestrator end"
RUN_SCRIPT="$SCRIPT_DIR/run-task.sh"

# Build new block
new_block=""
while read -r id cron; do
  [[ -z "$id" ]] && continue
  enabled=$(jq -r --arg id "$id" '.tasks[] | select(.id==$id) | .enabled' "$TASKS_PATH")
  if [[ "$enabled" != "true" ]]; then
    continue
  fi
  if [[ -z "$cron" ]] || [[ "$cron" == "null" ]]; then
    continue
  fi
  new_block="${new_block}${cron} $RUN_SCRIPT --tasks $TASKS_PATH_ABS --task $id
"
done < <(jq -r '.tasks[] | select(.cron != null) | "\(.id) \(.cron)"' "$TASKS_PATH")

if [[ "$DRY_RUN" == "1" ]]; then
  echo "--- would install cron block ---"
  echo "$MARKER_BEGIN"
  echo -n "$new_block"
  echo "$MARKER_END"
  exit 0
fi

# Get current crontab, remove old block, normalize CRON_TZ, append new
tmp=$(mktemp)
crontab -l 2>/dev/null > "$tmp" || true
# Remove existing block (macOS and GNU compatible)
awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
  $0 ~ b { f=1 }
  !f { print }
  $0 ~ e { f=0 }
' "$tmp" > "${tmp}.noblock"
mv "${tmp}.noblock" "$tmp"

# Remove existing CRON_TZ lines, then add configured timezone at top
awk '!/^CRON_TZ=/' "$tmp" > "${tmp}.notz"
{
  echo "CRON_TZ=$(jq -r '.timezone // "Asia/Shanghai"' "$CONFIG")"
  echo
  cat "${tmp}.notz"
} > "${tmp}.withtz"
mv "${tmp}.withtz" "$tmp"
rm -f "${tmp}.notz"

# Append new block
echo "$MARKER_BEGIN" >> "$tmp"
echo -n "$new_block" >> "$tmp"
echo "$MARKER_END" >> "$tmp"
crontab "$tmp"
rm -f "$tmp"
echo "Cron synced."
exit 0
