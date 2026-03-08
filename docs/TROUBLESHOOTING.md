# Push Orchestrator 故障排查

## 退出码与错误码对照

脚本退出码与标准错误码一致，便于监控与脚本判断：

| 退出码 | 错误码名 | 含义 |
|--------|----------|------|
| 0 | SUCCESS | 成功 |
| 1 | CONFIG_INVALID | 配置错误 |
| 2 | LOCK_ACQUIRE_FAILED | 锁获取失败 |
| 3 | DEDUPE_HIT | 去重命中 |
| 4 | DATA_UNAVAILABLE | 数据不可用 |
| 5 | STALE_DATA | 数据过期 |
| 6 | SOURCE_UNTRUSTED | 来源不可信 |
| 7 | SEND_TIMEOUT | 发送超时 |
| 8 | SEND_REJECTED | 无 message_id/被拒绝 |
| 9 | DB_WRITE_FAILED | DB 写入失败 |
| 10 | PAYLOAD_INVALID | payload 非法 |
| 11 | PROVIDER_FAILED | provider/handler 失败 |
| 12 | INTERNAL_ERROR | 内部错误 |

## 常见错误码

| 码 | 名称 | 处理建议 |
|----|------|----------|
| 1 | CONFIG_INVALID | 检查 config/default.json 与 tasks 文件语法、必填字段；运行 validate-config.sh |
| 2 | LOCK_ACQUIRE_FAILED | 检查 lockDir 可写、无残留锁文件、同一任务未在另一进程长时间占用 |
| 3 | DEDUPE_HIT | 预期行为：内容重复或 topic 在冷却期内；若要强制发送可加 --force |
| 4 | DATA_UNAVAILABLE | 数据源不可用（如 market-price 未配置真实 API） |
| 5 | STALE_DATA | 数据时间戳过期；检查数据源与 cron 间隔 |
| 6 | SOURCE_UNTRUSTED | 市场类任务：真值来源未配置或不可信 |
| 7 | SEND_TIMEOUT | 增加 timeout 或检查网络与 sendCommand 可用性 |
| 8 | SEND_REJECTED | 发送命令未返回 message_id；检查 sendCommand、channel、target 与下游服务 |
| 9 | DB_WRITE_FAILED | 检查 state 目录与 push.db 权限、磁盘空间 |
| 10 | PAYLOAD_INVALID | 检查 provider/handler 输出是否含 content、title、topic_key（若适用）及 content_kind 一致 |
| 11 | PROVIDER_FAILED | 查看日志；检查 provider 或 content handler 脚本是否存在、可执行、无语法错误 |
| 12 | INTERNAL_ERROR | 查看脚本日志与堆栈，必要时提 issue |

## 如何查 DB

```bash
export PUSH_DB_PATH="<skill_root>/state/push.db"
# 或从 config 读
PUSH_DB_PATH="$(jq -r '.stateDbPath' config/default.json)"

sqlite3 "$PUSH_DB_PATH" "SELECT * FROM runs ORDER BY started_at DESC LIMIT 10;"
sqlite3 "$PUSH_DB_PATH" "SELECT * FROM runtime_state;"
sqlite3 "$PUSH_DB_PATH" "SELECT * FROM dedupe_records WHERE task_id='<id>' ORDER BY sent_at DESC LIMIT 5;"
sqlite3 "$PUSH_DB_PATH" "SELECT date_bucket, task_id, error_code, count FROM failure_stats ORDER BY date_bucket DESC LIMIT 20;"
```

## 锁问题

- 锁目录：config 中 `lockDir`，默认 `/tmp/push-orchestrator/locks`。
- 每个任务对应 `<task_id>.lock`，由 flock 持有。
- 若进程异常退出，锁会自动释放。
- 若怀疑残留，可查看该目录下无对应进程后再删锁文件（一般不推荐手动删）。

## Provider / Handler 失败

1. 单独执行 provider：`echo '<task_json>' | ./scripts/providers/content.sh`，看 stdout/stderr。
2. 对 content 任务，直接调 handler：`echo '<task_json>' | ./scripts/providers/content/<kind>.sh`。
3. 确认 task 的 provider 与 content_kind 与现有脚本一致；新增 kind 需新增 `content/<kind>.sh`。

## Send 失败

1. 确认 config 中 sendCommand、defaultChannel、defaultTarget（或 task 内 channel、target）正确。
2. 在 shell 中手动执行 sendCommand（如 `openclaw message send telegram <target>`）看是否返回 message_id。
3. 用 `--dry-run` 跳过发送，确认编排与 payload 正常后再排查发送端。

## 归档问题

- 归档目录：config 中 `contentArchiveDir`，默认 `./state/content_archive`。
- **content_path 存相对路径**（相对 contentArchiveDir），迁移 skill 目录时只需保证 contentArchiveDir 与 content_path 相对关系不变即可。
- 若写入失败，检查目录存在且可写；`archive_enabled` 为 true 时才会写入。
- 索引在 `content_archive` 表，可按 task_id、content_kind、archive_category 查询。
