#!/usr/bin/env bash
# push-orchestrator lib: time
# Timezone and stale checks.

export TZ="${PUSH_TZ:-Asia/Shanghai}"

now_iso() {
  date '+%Y-%m-%dT%H:%M:%S%z'
}

now_epoch() {
  date '+%s'
}

# Check if a timestamp (epoch or ISO) is stale: age_seconds > cron_interval_seconds * factor
# Usage: is_stale data_timestamp_epoch cron_expression factor
# cron_expression can be simple like "0 * * * *" (hourly). We approximate interval from cron.
cron_interval_seconds() {
  local cron="$1"
  if [[ "$cron" == *"* * * * *"* ]] || [[ "$cron" == *"*/1 * * * *"* ]]; then
    echo 60
    return
  fi
  if [[ "$cron" == *"* * * *"* ]]; then
    echo 3600
    return
  fi
  if [[ "$cron" == *"* * *"* ]]; then
    echo 86400
    return
  fi
  echo 86400
}

is_stale() {
  local data_ts="$1"
  local cron_expr="$2"
  local factor="${3:-2}"
  local interval
  interval=$(cron_interval_seconds "$cron_expr")
  local max_age=$((interval * factor))
  local now
  now=$(now_epoch)
  local age=$((now - data_ts))
  [[ $age -gt $max_age ]]
}

cooldown_until_epoch() {
  local sent_at_epoch="$1"
  local cooldown_days="${2:-0}"
  local seconds
  seconds=$(echo "$cooldown_days * 86400" | bc 2>/dev/null || echo $((cooldown_days * 86400)))
  echo $((sent_at_epoch + seconds))
}
