#!/usr/bin/env bash
# push-orchestrator: replay (backfill / rerun) with --force and --dry-run
set -e
SKILL_ROOT="${PUSH_SKILL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_SCRIPT="$SCRIPT_DIR/run-task.sh"
TASKS_FILE=""
TASK_ID=""
MODE=""
TARGET_DATE=""
FORCE="0"
DRY_RUN="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tasks) TASKS_FILE="$2"; shift 2 ;;
    --task) TASK_ID="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --target-date) TARGET_DATE="$2"; shift 2 ;;
    --force) FORCE="1"; shift ;;
    --dry-run) DRY_RUN="1"; shift ;;
    *) shift ;;
  esac
done

if [[ -z "$TASKS_FILE" ]]; then
  echo "Usage: replay.sh --tasks <tasks_file> [--task <id>] --mode backfill|rerun [--target-date YYYY-MM-DD] [--force] [--dry-run]" >&2
  exit 1
fi

if [[ "$MODE" != "backfill" ]] && [[ "$MODE" != "rerun" ]]; then
  echo "Usage: replay.sh ... --mode backfill|rerun" >&2
  exit 1
fi

TASKS_PATH="$SKILL_ROOT/$TASKS_FILE"
if [[ ! -f "$TASKS_PATH" ]]; then
  echo "Tasks file not found: $TASKS_PATH" >&2
  exit 1
fi

args="--tasks $TASKS_FILE --mode $MODE"
[[ "$FORCE" == "1" ]] && args="$args --force"
[[ "$DRY_RUN" == "1" ]] && args="$args --dry-run"

if [[ -n "$TASK_ID" ]]; then
  bash "$RUN_SCRIPT" $args --task "$TASK_ID"
else
  for id in $(jq -r '.tasks[] | .id' "$TASKS_PATH"); do
    echo "Replay $MODE task: $id" >&2
    bash "$RUN_SCRIPT" $args --task "$id" || true
  done
fi
exit 0
