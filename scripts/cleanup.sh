#!/usr/bin/env bash
# push-orchestrator: cleanup old dedupe_records and optionally runs (by historyRetentionDays)
# Usage: cleanup.sh [--dedupe-days N] [--runs] [--dry-run]
# Default: --dedupe-days from config or 90; --runs uses historyRetentionDays from config.
set -e
SKILL_ROOT="${PUSH_SKILL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG="${SKILL_ROOT}/config/default.json"
DB_PATH="${PUSH_DB_PATH}"
DRY_RUN="0"
DEDUPE_DAYS=""
DO_RUNS="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dedupe-days) DEDUPE_DAYS="$2"; shift 2 ;;
    --runs) DO_RUNS="1"; shift ;;
    --dry-run) DRY_RUN="1"; shift ;;
    *) shift ;;
  esac
done

if [[ -z "$DB_PATH" ]]; then
  DB_PATH="$SKILL_ROOT/$(jq -r '.stateDbPath // "./state/push.db"' "$CONFIG")"
fi
export PUSH_DB_PATH="$DB_PATH"

if [[ ! -f "$DB_PATH" ]]; then
  echo "DB not found: $DB_PATH" >&2
  exit 0
fi

# Default dedupe retention: 90 days (or config dedupeRetentionDays if added later)
if [[ -z "$DEDUPE_DAYS" ]]; then
  DEDUPE_DAYS=$(jq -r '.dedupeRetentionDays // .historyRetentionDays // 90' "$CONFIG")
fi

# Delete dedupe_records where sent_at older than N days (compare as date string YYYY-MM-DD)
if date -v-1d '+%Y-%m-%d' >/dev/null 2>&1; then
  since_date=$(date -v-${DEDUPE_DAYS}d '+%Y-%m-%d')
else
  since_date=$(date -d "${DEDUPE_DAYS} days ago" '+%Y-%m-%d')
fi
count_dedupe=$(sqlite3 "$DB_PATH" "SELECT COUNT(1) FROM dedupe_records WHERE sent_at < '$since_date 00:00:00';" 2>/dev/null || echo "0")
if [[ "$DRY_RUN" == "1" ]]; then
  echo "Would delete $count_dedupe dedupe_records older than $since_date"
else
  sqlite3 "$DB_PATH" "DELETE FROM dedupe_records WHERE sent_at < '$since_date 00:00:00';" 2>/dev/null || true
  echo "Deleted dedupe_records older than $since_date"
fi

if [[ "$DO_RUNS" == "1" ]]; then
  retention=$(jq -r '.historyRetentionDays // 30' "$CONFIG")
  if date -v-1d '+%Y-%m-%d' >/dev/null 2>&1; then
    since_runs=$(date -v-${retention}d '+%Y-%m-%d' 2>/dev/null || echo "2020-01-01")
  else
    since_runs=$(date -d "${retention} days ago" '+%Y-%m-%d' 2>/dev/null || echo "2020-01-01")
  fi
  count_runs=$(sqlite3 "$DB_PATH" "SELECT COUNT(1) FROM runs WHERE started_at < '$since_runs 00:00:00';" 2>/dev/null || echo "0")
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "Would delete $count_runs runs older than $since_runs"
  else
    sqlite3 "$DB_PATH" "DELETE FROM runs WHERE started_at < '$since_runs 00:00:00';" 2>/dev/null || true
    echo "Deleted runs older than $since_runs"
  fi
fi
exit 0
