#!/usr/bin/env bash
# push-orchestrator: validate config, tasks, schema, providers
set -e
SKILL_ROOT="${PUSH_SKILL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG="${PUSH_CONFIG:-$SKILL_ROOT/config/default.json}"
TASKS_FILE="${PUSH_TASKS_FILE:-}"
FAIL=0

log() { echo "[validate-config] $*" >&2; }

if [[ ! -f "$CONFIG" ]]; then
  log "Missing config: $CONFIG"
  exit 1
fi
if ! jq -e . "$CONFIG" >/dev/null 2>&1; then
  log "Invalid JSON: $CONFIG"
  exit 1
fi

# Required config keys
for key in timezone stateDbPath sendCommand lockDir contentArchiveDir runHistoryExportDir; do
  if ! jq -e ".$key" "$CONFIG" >/dev/null 2>&1; then
    log "Missing config key: $key"
    FAIL=1
  fi
done

if [[ -n "$TASKS_FILE" ]] && [[ -f "$TASKS_FILE" ]]; then
  if ! jq -e '.tasks | length' "$TASKS_FILE" >/dev/null 2>&1; then
    log "Invalid tasks file or missing .tasks: $TASKS_FILE"
    FAIL=1
  else
    # Task id uniqueness
    ids=$(jq -r '.tasks[].id' "$TASKS_FILE")
    dup=$(echo "$ids" | sort | uniq -d)
    if [[ -n "$dup" ]]; then
      log "Duplicate task ids: $dup"
      FAIL=1
    fi
    # type=content must have content_kind, content_source_type, dedupe_strategy, render_strategy
    while read -r t; do
      type=$(echo "$t" | jq -r '.type')
      if [[ "$type" == "content" ]]; then
        for f in content_kind content_source_type; do
          if [[ -z "$(echo "$t" | jq -r ".$f // empty")" ]]; then
            log "Task $(echo "$t" | jq -r '.id') type=content missing $f"
            FAIL=1
          fi
        done
      fi
    done < <(jq -c '.tasks[]' "$TASKS_FILE")
  fi
fi

# Schema files
for s in "$SKILL_ROOT/config/tasks.schema.json" "$SKILL_ROOT/config/channels.schema.json"; do
  if [[ -f "$s" ]] && ! jq -e . "$s" >/dev/null 2>&1; then
    log "Invalid schema: $s"
    FAIL=1
  fi
done

# DB dir writable
db_path=$(jq -r '.stateDbPath // "./state/push.db"' "$CONFIG")
db_dir="$SKILL_ROOT/$(dirname "$db_path")"
if ! mkdir -p "$db_dir" 2>/dev/null || [[ ! -w "$db_dir" ]]; then
  log "DB directory not writable: $db_dir"
  FAIL=1
fi

# Archive dir
arch_dir=$(jq -r '.contentArchiveDir // "./state/content_archive"' "$CONFIG")
arch_abs="$SKILL_ROOT/$arch_dir"
if ! mkdir -p "$arch_abs" 2>/dev/null || [[ ! -w "$arch_abs" ]]; then
  log "Archive directory not writable: $arch_abs"
  FAIL=1
fi

# Providers exist (reminder, content, market-*, ops, test)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for p in reminder content market-price market-news market-brief ops test; do
  if [[ ! -f "$SCRIPT_DIR/providers/$p.sh" ]]; then
    log "Missing provider: $p.sh"
    FAIL=1
  fi
done

# Content handlers: check that referenced content_kinds have a handler
if [[ -n "$TASKS_FILE" ]] && [[ -f "$TASKS_FILE" ]]; then
  kinds=$(jq -r '.tasks[] | select(.type=="content") | .content_kind // .content_handler // empty' "$TASKS_FILE" | sort -u)
  for k in $kinds; do
    [[ -z "$k" ]] && continue
    if [[ ! -f "$SCRIPT_DIR/providers/content/${k}.sh" ]]; then
      log "Content handler not found: content/${k}.sh"
      FAIL=1
    fi
  done
fi

if [[ $FAIL -eq 1 ]]; then
  exit 1
fi
log "Validation OK"
exit 0
