#!/usr/bin/env bash
# push-orchestrator lib: SQLite DB operations
# Uses PUSH_DB_PATH for DB path.

db_query() {
  local db="${PUSH_DB_PATH:?PUSH_DB_PATH not set}"
  sqlite3 -batch "$db" "$@"
}

db_exec() {
  local db="${PUSH_DB_PATH:?PUSH_DB_PATH not set}"
  sqlite3 -batch "$db" "$@"
}

# Escape single quote for SQLite
sql_escape() {
  sed "s/'/''/g" <<< "$1"
}

# Upsert task snapshot
db_upsert_task() {
  local id name type content_kind provider severity enabled cron_expr channel target archive_category config_json updated_at
  id=$(sql_escape "$1")
  name=$(sql_escape "$2")
  type=$(sql_escape "$3")
  content_kind=$(sql_escape "${4:-}")
  provider=$(sql_escape "$5")
  severity=$(sql_escape "${6:-medium}")
  enabled="${7:-1}"
  cron_expr=$(sql_escape "${8:-}")
  channel=$(sql_escape "${9:-}")
  target=$(sql_escape "${10:-}")
  archive_category=$(sql_escape "${11:-}")
  config_json=$(sql_escape "${12:-{}}")
  updated_at="${13:-$(date -u '+%Y-%m-%d %H:%M:%S')}"

  db_exec "
    INSERT INTO tasks (id, name, type, content_kind, provider, severity, enabled, cron_expr, channel, target, archive_category, config_json, updated_at)
    VALUES ('$id','$name','$type','$content_kind','$provider','$severity','$enabled','$cron_expr','$channel','$target','$archive_category','$config_json','$updated_at')
    ON CONFLICT(id) DO UPDATE SET
      name=excluded.name, type=excluded.type, content_kind=excluded.content_kind, provider=excluded.provider,
      severity=excluded.severity, enabled=excluded.enabled, cron_expr=excluded.cron_expr,
      channel=excluded.channel, target=excluded.target, archive_category=excluded.archive_category,
      config_json=excluded.config_json, updated_at=excluded.updated_at;
  "
}

# Insert run record
db_insert_run() {
  local run_id task_id type content_kind trigger_type mode status error_code error_message started_at finished_at duration_ms message_id payload_hash data_timestamp source_summary
  run_id=$(sql_escape "$1")
  task_id=$(sql_escape "$2")
  type=$(sql_escape "$3")
  content_kind=$(sql_escape "${4:-}")
  trigger_type=$(sql_escape "${5:-cron}")
  mode=$(sql_escape "${6:-normal}")
  status=$(sql_escape "$7")
  error_code="${8:-0}"
  error_message=$(sql_escape "${9:-}")
  started_at=$(sql_escape "$10")
  finished_at=$(sql_escape "${11:-}")
  duration_ms="${12:-0}"
  message_id=$(sql_escape "${13:-}")
  payload_hash=$(sql_escape "${14:-}")
  data_timestamp=$(sql_escape "${15:-}")
  source_summary=$(sql_escape "${16:-}")

  db_exec "
    INSERT INTO runs (run_id, task_id, type, content_kind, trigger_type, mode, status, error_code, error_message, started_at, finished_at, duration_ms, message_id, payload_hash, data_timestamp, source_summary)
    VALUES ('$run_id','$task_id','$type','$content_kind','$trigger_type','$mode','$status','$error_code','$error_message','$started_at','$finished_at','$duration_ms','$message_id','$payload_hash','$data_timestamp','$source_summary');
  "
}

# Update runtime_state
db_upsert_runtime_state() {
  local task_id type content_kind last_status last_run_at last_message_id last_error_code last_error_message last_duration_ms
  task_id=$(sql_escape "$1")
  type=$(sql_escape "$2")
  content_kind=$(sql_escape "${3:-}")
  last_status=$(sql_escape "$4")
  last_run_at=$(sql_escape "$5")
  last_message_id=$(sql_escape "${6:-}")
  last_error_code="${7:-0}"
  last_error_message=$(sql_escape "${8:-}")
  last_duration_ms="${9:-0}"

  db_exec "
    INSERT INTO runtime_state (task_id, type, content_kind, last_status, last_run_at, last_message_id, last_error_code, last_error_message, last_duration_ms)
    VALUES ('$task_id','$type','$content_kind','$last_status','$last_run_at','$last_message_id','$last_error_code','$last_error_message','$last_duration_ms')
    ON CONFLICT(task_id) DO UPDATE SET
      type=excluded.type, content_kind=excluded.content_kind, last_status=excluded.last_status,
      last_run_at=excluded.last_run_at, last_message_id=excluded.last_message_id,
      last_error_code=excluded.last_error_code, last_error_message=excluded.last_error_message,
      last_duration_ms=excluded.last_duration_ms;
  "
}

# Insert dedupe record
db_insert_dedupe() {
  local task_id type content_kind content_hash topic_key title source sent_at cooldown_until mode
  task_id=$(sql_escape "$1")
  type=$(sql_escape "$2")
  content_kind=$(sql_escape "${3:-}")
  content_hash=$(sql_escape "$4")
  topic_key=$(sql_escape "${5:-}")
  title=$(sql_escape "${6:-}")
  source=$(sql_escape "${7:-}")
  sent_at=$(sql_escape "$8")
  cooldown_until=$(sql_escape "${9:-}")
  mode=$(sql_escape "${10:-hash_topic}")

  db_exec "
    INSERT INTO dedupe_records (task_id, type, content_kind, content_hash, topic_key, title, source, sent_at, cooldown_until, mode)
    VALUES ('$task_id','$type','$content_kind','$content_hash','$topic_key','$title','$source','$sent_at','$cooldown_until','$mode');
  "
}

# Insert content_archive
db_insert_content_archive() {
  local archive_id task_id content_kind archive_category topic title content_path source_summary created_at sent_at
  archive_id=$(sql_escape "$1")
  task_id=$(sql_escape "$2")
  content_kind=$(sql_escape "$3")
  archive_category=$(sql_escape "${4:-}")
  topic=$(sql_escape "${5:-}")
  title=$(sql_escape "${6:-}")
  content_path=$(sql_escape "$7")
  source_summary=$(sql_escape "${8:-}")
  created_at=$(sql_escape "$9")
  sent_at=$(sql_escape "${10:-}")

  db_exec "
    INSERT INTO content_archive (archive_id, task_id, content_kind, archive_category, topic, title, content_path, source_summary, created_at, sent_at)
    VALUES ('$archive_id','$task_id','$content_kind','$archive_category','$topic','$title','$content_path','$source_summary','$created_at','$sent_at');
  "
}

# Insert replay_record
db_insert_replay_record() {
  local replay_id task_id content_kind target_date mode force_flag status created_at
  replay_id=$(sql_escape "$1")
  task_id=$(sql_escape "$2")
  content_kind=$(sql_escape "${3:-}")
  target_date=$(sql_escape "$4")
  mode=$(sql_escape "$5")
  force_flag="${6:-0}"
  status=$(sql_escape "$7")
  created_at=$(sql_escape "$8")

  db_exec "
    INSERT INTO replay_records (replay_id, task_id, content_kind, target_date, mode, force_flag, status, created_at)
    VALUES ('$replay_id','$task_id','$content_kind','$target_date','$mode','$force_flag','$status','$created_at');
  "
}

# Upsert failure_stats
db_upsert_failure_stat() {
  local date_bucket task_id content_kind error_code count
  date_bucket=$(sql_escape "$1")
  task_id=$(sql_escape "$2")
  content_kind=$(sql_escape "${3:-}")
  error_code="${4:-12}"
  count="${5:-1}"

  db_exec "
    INSERT INTO failure_stats (date_bucket, task_id, content_kind, error_code, count)
    VALUES ('$date_bucket','$task_id','$content_kind','$error_code','$count')
    ON CONFLICT(date_bucket, task_id, content_kind, error_code) DO UPDATE SET count = count + $count;
  "
}

# Check dedupe: hash
db_dedupe_hash_hit() {
  local task_id content_hash
  task_id=$(sql_escape "$1")
  content_hash=$(sql_escape "$2")
  local c
  c=$(db_query "SELECT COUNT(1) FROM dedupe_records WHERE task_id='$task_id' AND content_hash='$content_hash' LIMIT 1;")
  [[ "${c:-0}" -gt 0 ]]
}

# Check dedupe: topic cooldown
db_dedupe_topic_cooldown_hit() {
  local task_id topic_key now_epoch
  task_id=$(sql_escape "$1")
  topic_key=$(sql_escape "$2")
  now_epoch="${3:-$(date '+%s')}"
  local c
  c=$(db_query "SELECT COUNT(1) FROM dedupe_records WHERE task_id='$task_id' AND topic_key='$topic_key' AND cooldown_until != '' AND CAST(cooldown_until AS INTEGER) > $now_epoch LIMIT 1;")
  [[ "${c:-0}" -gt 0 ]]
}

# Get last sent cooldown_until for topic
db_dedupe_topic_cooldown_until() {
  local task_id topic_key
  task_id=$(sql_escape "$1")
  topic_key=$(sql_escape "$2")
  db_query "SELECT cooldown_until FROM dedupe_records WHERE task_id='$task_id' AND topic_key='$topic_key' ORDER BY sent_at DESC LIMIT 1;"
}
