#!/usr/bin/env bash
# push-orchestrator: initialize SQLite DB (idempotent)
set -e
SKILL_ROOT="${PUSH_SKILL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG="${PUSH_CONFIG:-$SKILL_ROOT/config/default.json}"
DB_PATH="${PUSH_DB_PATH}"
if [[ -z "$DB_PATH" ]]; then
  DB_PATH=$(jq -r '.stateDbPath // "./state/push.db"' "$CONFIG")
  DB_PATH="$SKILL_ROOT/$DB_PATH"
fi
mkdir -p "$(dirname "$DB_PATH")"
export PUSH_DB_PATH="$DB_PATH"

sqlite3 "$DB_PATH" "
  CREATE TABLE IF NOT EXISTS tasks (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    content_kind TEXT,
    provider TEXT NOT NULL,
    severity TEXT DEFAULT 'medium',
    enabled INTEGER DEFAULT 1,
    cron_expr TEXT,
    channel TEXT,
    target TEXT,
    archive_category TEXT,
    config_json TEXT,
    updated_at TEXT
  );

  CREATE TABLE IF NOT EXISTS runs (
    run_id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL,
    type TEXT NOT NULL,
    content_kind TEXT,
    trigger_type TEXT DEFAULT 'cron',
    mode TEXT DEFAULT 'normal',
    status TEXT NOT NULL,
    error_code INTEGER DEFAULT 0,
    error_message TEXT,
    started_at TEXT NOT NULL,
    finished_at TEXT,
    duration_ms INTEGER DEFAULT 0,
    message_id TEXT,
    payload_hash TEXT,
    data_timestamp TEXT,
    source_summary TEXT
  );

  CREATE TABLE IF NOT EXISTS dedupe_records (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id TEXT NOT NULL,
    type TEXT NOT NULL,
    content_kind TEXT,
    content_hash TEXT NOT NULL,
    topic_key TEXT,
    title TEXT,
    source TEXT,
    sent_at TEXT NOT NULL,
    cooldown_until TEXT,
    mode TEXT
  );

  CREATE TABLE IF NOT EXISTS runtime_state (
    task_id TEXT PRIMARY KEY,
    type TEXT NOT NULL,
    content_kind TEXT,
    last_status TEXT NOT NULL,
    last_run_at TEXT NOT NULL,
    last_message_id TEXT,
    last_error_code INTEGER DEFAULT 0,
    last_error_message TEXT,
    last_duration_ms INTEGER DEFAULT 0
  );

  CREATE TABLE IF NOT EXISTS content_archive (
    archive_id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL,
    content_kind TEXT NOT NULL,
    archive_category TEXT,
    topic TEXT,
    title TEXT,
    content_path TEXT NOT NULL,
    source_summary TEXT,
    created_at TEXT NOT NULL,
    sent_at TEXT
  );

  CREATE TABLE IF NOT EXISTS replay_records (
    replay_id TEXT PRIMARY KEY,
    task_id TEXT NOT NULL,
    content_kind TEXT,
    target_date TEXT NOT NULL,
    mode TEXT NOT NULL,
    force_flag INTEGER DEFAULT 0,
    status TEXT NOT NULL,
    created_at TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS failure_stats (
    date_bucket TEXT NOT NULL,
    task_id TEXT NOT NULL,
    content_kind TEXT,
    error_code INTEGER NOT NULL,
    count INTEGER DEFAULT 1,
    PRIMARY KEY (date_bucket, task_id, content_kind, error_code)
  );
"

# Indexes
sqlite3 "$DB_PATH" "
  CREATE INDEX IF NOT EXISTS idx_runs_task_id ON runs(task_id);
  CREATE INDEX IF NOT EXISTS idx_runs_started_at ON runs(started_at);
  CREATE INDEX IF NOT EXISTS idx_runs_content_kind ON runs(content_kind);
  CREATE INDEX IF NOT EXISTS idx_dedupe_task_id ON dedupe_records(task_id);
  CREATE INDEX IF NOT EXISTS idx_dedupe_content_hash ON dedupe_records(content_hash);
  CREATE INDEX IF NOT EXISTS idx_dedupe_topic_key ON dedupe_records(topic_key);
  CREATE INDEX IF NOT EXISTS idx_dedupe_content_kind ON dedupe_records(content_kind);
  CREATE INDEX IF NOT EXISTS idx_runtime_state_task_id ON runtime_state(task_id);
  CREATE INDEX IF NOT EXISTS idx_failure_stats_date ON failure_stats(date_bucket);
" 2>/dev/null || true

echo "DB initialized: $DB_PATH"
