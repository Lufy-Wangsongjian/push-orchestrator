#!/usr/bin/env bash
# push-orchestrator: healthcheck (text or JSON)
set -e
SKILL_ROOT="${PUSH_SKILL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${SKILL_ROOT}/config/default.json"
OUTPUT="text"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) OUTPUT="json"; shift ;;
    *) shift ;;
  esac
done

fail() { echo "$1" >&2; exit 1; }

# 1) Config valid
if ! jq -e . "$CONFIG" >/dev/null 2>&1; then
  [[ "$OUTPUT" == "json" ]] && echo "{\"config_valid\": false}" && exit 1
  fail "Config invalid"
fi

# 2) DB writable
db_path="$SKILL_ROOT/$(jq -r '.stateDbPath // "./state/push.db"' "$CONFIG")"
if [[ ! -f "$db_path" ]]; then
  "$SCRIPT_DIR/init-db.sh" >/dev/null 2>&1 || true
fi
if ! sqlite3 "$db_path" "SELECT 1;" >/dev/null 2>&1; then
  [[ "$OUTPUT" == "json" ]] && echo "{\"db_ok\": false}" && exit 1
  fail "DB not readable"
fi

# 3) Cron sync
cron_synced="false"
crontab -l 2>/dev/null | grep -q "push-orchestrator begin" && cron_synced="true"

# 4) Recent 24h
since=$(date -u -v-24H '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -u '+%Y-%m-%d %H:%M:%S')
total=$(sqlite3 "$db_path" "SELECT COUNT(1) FROM runs WHERE started_at >= '$since';" 2>/dev/null || echo "0")
success=$(sqlite3 "$db_path" "SELECT COUNT(1) FROM runs WHERE started_at >= '$since' AND status = 'success';" 2>/dev/null || echo "0")

# 5) Recent failures
failures=$(sqlite3 "$db_path" "SELECT task_id, error_code, error_message FROM runs WHERE status = 'failed' ORDER BY started_at DESC LIMIT 5;" 2>/dev/null || true)

# 6) Providers
providers_ok="true"
for p in reminder content market-price market-news market-brief ops test; do
  if [[ ! -f "$SCRIPT_DIR/providers/$p.sh" ]]; then
    providers_ok="false"
    break
  fi
done

# 7) Archive dir
arch_dir="$SKILL_ROOT/$(jq -r '.contentArchiveDir // "./state/content_archive"' "$CONFIG")"
mkdir -p "$arch_dir"
archive_writable="false"
[[ -w "$arch_dir" ]] && archive_writable="true"

if [[ "$OUTPUT" == "json" ]]; then
  jq -n \
    --argjson config_valid true \
    --argjson db_ok true \
    --arg cron_synced "$cron_synced" \
    --argjson recent24h_total "${total:-0}" \
    --argjson recent24h_success "${success:-0}" \
    --arg providers_ok "$providers_ok" \
    --arg archive_writable "$archive_writable" \
    '{config_valid:$config_valid, db_ok:$db_ok, cron_synced:($cron_synced=="true"), recent24h_total:$recent24h_total, recent24h_success:$recent24h_success, providers_ok:($providers_ok=="true"), archive_writable:($archive_writable=="true")}'
else
  echo "OK: config_valid"
  echo "OK: db_ok"
  echo "cron_synced: $cron_synced"
  echo "Recent 24h: $success / $total success"
  echo "Recent failures: $failures"
  echo "OK: providers"
  echo "archive_writable: $archive_writable"
fi
exit 0
