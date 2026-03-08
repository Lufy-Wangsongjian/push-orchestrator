# Push Orchestrator 运维与操作

## 受信输入说明

**config 与 tasks 文件视为受信输入**：仅由运维或本机配置生成，不解析不可信来源。DB 层对 task_id、content_hash 等做单引号转义；若未来从外部系统读入任务 id 等，需先做白名单或格式校验。

## 初始化数据库

```bash
cd <skill_root>
./scripts/init-db.sh
```

会创建 `state/push.db`（若不存在）及所有表与索引，幂等可重复执行。

## 配置 tasks 文件

1. 复制或参考 `examples/tasks.*.example.json`。
2. 填写 `tasks[]`：id、name、type、provider、enabled、cron、channel、target 等。
3. `type=content` 时必须包含 content_kind、content_source_type、dedupe_strategy、render_strategy。
4. 在 `config/default.json` 中确认 sendCommand、defaultTarget、stateDbPath、contentArchiveDir 等。

## 同步 cron

- `--tasks` 可为相对路径（相对 skill 根）或绝对路径；**sync-cron 写入 crontab 时会转为绝对路径**，保证 cron 触发时无论当前目录如何都能找到 tasks 文件。
- 只管理以 `# push-orchestrator begin` / `# push-orchestrator end` 包裹的 crontab 块，幂等。

```bash
./scripts/sync-cron.sh --tasks examples/tasks.content.example.json
# 仅预览
./scripts/sync-cron.sh --tasks examples/tasks.content.example.json --dry-run
```

## 手工运行任务

```bash
./scripts/run-task.sh --tasks examples/tasks.content.example.json --task <task_id>
# 不真正发送
./scripts/run-task.sh --tasks examples/tasks.content.example.json --task <task_id> --dry-run
# 补发/重跑
./scripts/run-task.sh --tasks examples/tasks.content.example.json --task <task_id> --mode backfill
./scripts/run-task.sh --tasks examples/tasks.content.example.json --task <task_id> --mode rerun --force
```

## Replay

- **当前语义**：replay 为**整任务重跑**（再执行一次 run-task），不按“某日漏跑”过滤。`--target-date` 仅写入 replay_records 便于审计，不参与 provider 或按日补发逻辑。
- **backfill**：补发，不写 dedupe 记录。
- **rerun**：正式重跑，可写 dedupe；加 `--force` 可跳过去重判断。

```bash
# 单任务
./scripts/replay.sh --tasks examples/tasks.content.example.json --task <task_id> --mode backfill
./scripts/replay.sh --tasks examples/tasks.content.example.json --task <task_id> --mode rerun --force --dry-run
# 全部任务
./scripts/replay.sh --tasks examples/tasks.content.example.json --mode rerun
```

## Healthcheck

```bash
./scripts/healthcheck.sh
./scripts/healthcheck.sh --json
```

检查：配置合法、DB 可读写、cron 块是否存在、最近 24h 成功率、providers 存在、归档目录可写。

## 历史与去重清理

- **historyRetentionDays**（config）：runs 表建议保留天数。
- **dedupeRetentionDays**（config，默认 90）：去重记录保留天数，超期可删以控制表大小与查询性能。

```bash
# 仅清理 dedupe_records（默认 90 天前）
./scripts/cleanup.sh
# 指定天数与 dry-run
./scripts/cleanup.sh --dedupe-days 60 --dry-run
# 同时清理 runs 表（按 historyRetentionDays）
./scripts/cleanup.sh --runs
./scripts/cleanup.sh --dedupe-days 90 --runs --dry-run
```

建议通过 cron 定期执行（如每周一次）：`0 3 * * 0 cd <skill_root> && ./scripts/cleanup.sh --runs`。

## 可选：JSON 日志

设置 `PUSH_LOG_FORMAT=json` 时，log_info / log_error 输出单行 JSON（含 ts、level、run_id、task_id、message），便于集中采集。run-task 会导出 PUSH_RUN_ID、PUSH_TASK_ID，便于关联。

## Market 任务说明（占位）

当前 `market-price.sh` / `market-news.sh` 为**占位实现**，未接入真实行情与新闻源。生产使用前必须：
- 接入可信真值源（价格、涨跌、来源 URL、时间戳），且不用 Tavily 等作为唯一真值；
- 无真值时应返回“数据不可用”，不得编造价格；
- 在 validate-payload 中校验来源、时间戳与 stale。

## 如何增加新 task

1. 在现有或新 tasks JSON 的 `tasks[]` 中增加一项。
2. 填写 id、name、type、provider、enabled、cron、channel、target 等。
3. 若 type=content，填写 content_kind、content_source_type、dedupe_strategy、render_strategy 及可选 source_config、archive_enabled。
4. 运行 `validate-config.sh`（设置 PUSH_TASKS_FILE 指向该文件）。
5. 若使用 cron，执行 `sync-cron.sh --tasks <path>`。

**说明**：`config/tasks.schema.json` 为结构参考，当前校验以 `validate-config.sh` 的脚本逻辑为准；若需严格 JSON Schema 校验可自行接入 ajv 等工具。

## 如何增加新 content_kind

1. 在 task 配置中设置 `content_kind`（及 content_source_type、dedupe_strategy、render_strategy）。
2. 新增 `scripts/providers/content/<kind>.sh`：从 stdin 读 task JSON，向 stdout 输出单行 JSON，包含 title、topic_key、content、source_summary、content_kind。
3. 可选：在 `templates/content/<kind>/` 下添加模板。
4. 无需修改 run-task.sh、DB 表结构或 content.sh 的 if/else（content.sh 为 dispatcher，按名字调用 `<kind>.sh`）。

## 如何增加新 provider

1. 在 `scripts/providers/` 下新增 `<name>.sh`，从 stdin 读 task JSON，向 stdout 输出与类型相符的 payload（如 content 类需 title、topic_key、content、source_summary、content_kind）。
2. 在 tasks 中将 `provider` 设为该名字。
3. `validate-config.sh` 会检查 provider 文件是否存在。
