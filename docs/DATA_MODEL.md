# Push Orchestrator 数据模型

主状态库：`state/push.db`（SQLite）。

## 表结构

### tasks

任务快照与元信息。

| 字段 | 类型 | 说明 |
|------|------|------|
| id | TEXT PK | 任务 id |
| name | TEXT | 名称 |
| type | TEXT | reminder / content / market / ops / test |
| content_kind | TEXT | 内容类型（仅 type=content 有值） |
| provider | TEXT | 提供方脚本名 |
| severity | TEXT | high / medium / low |
| enabled | INTEGER | 是否启用 |
| cron_expr | TEXT | cron 表达式 |
| channel | TEXT | 发送通道 |
| target | TEXT | 发送目标 |
| archive_category | TEXT | 归档分类 |
| config_json | TEXT | 完整 task 配置 JSON |
| updated_at | TEXT | 更新时间 |

### runs

任务执行历史。

| 字段 | 类型 | 说明 |
|------|------|------|
| run_id | TEXT PK | 运行 id |
| task_id | TEXT | 任务 id |
| type | TEXT | 任务类型 |
| content_kind | TEXT | 内容类型 |
| trigger_type | TEXT | cron / manual 等 |
| mode | TEXT | normal / backfill / rerun |
| status | TEXT | success / failed / dedupe_hit |
| error_code | INTEGER | 标准错误码 |
| error_message | TEXT | 错误信息 |
| started_at | TEXT | 开始时间 |
| finished_at | TEXT | 结束时间 |
| duration_ms | INTEGER | 耗时毫秒 |
| message_id | TEXT | 发送返回的 message_id |
| payload_hash | TEXT | payload 哈希（去重用） |
| data_timestamp | TEXT | 数据时间戳（如 market） |
| source_summary | TEXT | 来源摘要 |

### dedupe_records

去重记录。

| 字段 | 类型 | 说明 |
|------|------|------|
| id | INTEGER PK | 自增 |
| task_id | TEXT | 任务 id |
| type | TEXT | 任务类型 |
| content_kind | TEXT | 内容类型 |
| content_hash | TEXT | 内容哈希 |
| topic_key | TEXT | 主题键（topic 冷却用） |
| title | TEXT | 标题 |
| source | TEXT | 来源摘要 |
| sent_at | TEXT | 发送时间 |
| cooldown_until | TEXT | 冷却截止：**约定为 Unix epoch 秒**（整数字符串），用于 topic 冷却比较 |
| mode | TEXT | 去重模式 |

### runtime_state

每个任务最近一次执行结果。

| 字段 | 类型 | 说明 |
|------|------|------|
| task_id | TEXT PK | 任务 id |
| type | TEXT | 任务类型 |
| content_kind | TEXT | 内容类型 |
| last_status | TEXT | 最近状态 |
| last_run_at | TEXT | 最近运行时间 |
| last_message_id | TEXT | 最近 message_id |
| last_error_code | INTEGER | 最近错误码 |
| last_error_message | TEXT | 最近错误信息 |
| last_duration_ms | INTEGER | 最近耗时 |

### content_archive

内容归档索引。

| 字段 | 类型 | 说明 |
|------|------|------|
| archive_id | TEXT PK | 归档 id |
| task_id | TEXT | 任务 id |
| content_kind | TEXT | 内容类型 |
| archive_category | TEXT | 归档分类 |
| topic | TEXT | 主题 |
| title | TEXT | 标题 |
| content_path | TEXT | **相对路径**（相对 config 中 contentArchiveDir），便于迁移；解析时拼 `contentArchiveDir/content_path` |
| source_summary | TEXT | 来源摘要 |
| created_at | TEXT | 创建时间 |
| sent_at | TEXT | 发送时间 |

### replay_records

补发/重跑记录。

| 字段 | 类型 | 说明 |
|------|------|------|
| replay_id | TEXT PK | 回放 id |
| task_id | TEXT | 任务 id |
| content_kind | TEXT | 内容类型 |
| target_date | TEXT | 目标日期 |
| mode | TEXT | backfill / rerun |
| force_flag | INTEGER | 是否强制 |
| status | TEXT | 状态 |
| created_at | TEXT | 创建时间 |

### failure_stats

失败聚合统计（按日/任务/内容类型/错误码）。

| 字段 | 类型 | 说明 |
|------|------|------|
| date_bucket | TEXT | 日期桶 |
| task_id | TEXT | 任务 id |
| content_kind | TEXT | 内容类型 |
| error_code | INTEGER | 错误码 |
| count | INTEGER | 次数 |
| PK | (date_bucket, task_id, content_kind, error_code) | 联合主键 |

## 索引

- runs: task_id, started_at, content_kind
- dedupe_records: task_id, content_hash, topic_key, content_kind
- runtime_state: task_id
- failure_stats: date_bucket

## content_kind 相关字段

- **tasks.content_kind**：任务配置的内容类型（仅 type=content 使用）。
- **runs.content_kind**：当次运行的内容类型（来自 task 或 provider 输出）。
- **dedupe_records.content_kind**：去重记录所属内容类型。
- **content_archive.content_kind**：归档内容类型，用于按类型分目录与查询。

## 归档路径解析

`content_archive.content_path` 存的是**相对 config 中 contentArchiveDir 的路径**（如 `book/arch-xxx.md`）。读取或导出时需拼成绝对路径：`<skill_root>/<contentArchiveDir>/<content_path>`。

## 典型查询示例

```sql
-- 最近 24 小时成功率
SELECT COUNT(*) FILTER (WHERE status = 'success') AS ok, COUNT(*) AS total
FROM runs WHERE started_at >= datetime('now', '-24 hours');

-- 某任务最近 5 次运行
SELECT run_id, status, error_code, started_at FROM runs
WHERE task_id = 'content-book' ORDER BY started_at DESC LIMIT 5;

-- 某任务去重记录（topic 冷却）
SELECT topic_key, sent_at, cooldown_until FROM dedupe_records
WHERE task_id = 'content-book' ORDER BY sent_at DESC LIMIT 10;

-- 失败统计
SELECT date_bucket, task_id, error_code, count FROM failure_stats
ORDER BY date_bucket DESC LIMIT 20;
```
