# Push Orchestrator 运维与操作

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

```bash
./scripts/sync-cron.sh --tasks examples/tasks.content.example.json
# 仅预览
./scripts/sync-cron.sh --tasks examples/tasks.content.example.json --dry-run
```

只管理以 `# push-orchestrator begin` / `# push-orchestrator end` 包裹的 crontab 块，幂等。

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

```bash
# 单任务
./scripts/replay.sh --tasks examples/tasks.content.example.json --task <task_id> --mode backfill
./scripts/replay.sh --tasks examples/tasks.content.example.json --task <task_id> --mode rerun --force --dry-run
# 全部任务
./scripts/replay.sh --tasks examples/tasks.content.example.json --mode rerun
```

- **backfill**：补发，不写 dedupe 记录。
- **rerun**：正式重跑，可写 dedupe；加 `--force` 可跳过去重判断。

## Healthcheck

```bash
./scripts/healthcheck.sh
./scripts/healthcheck.sh --json
```

检查：配置合法、DB 可读写、cron 块是否存在、最近 24h 成功率、providers 存在、归档目录可写。

## 如何增加新 task

1. 在现有或新 tasks JSON 的 `tasks[]` 中增加一项。
2. 填写 id、name、type、provider、enabled、cron、channel、target 等。
3. 若 type=content，填写 content_kind、content_source_type、dedupe_strategy、render_strategy 及可选 source_config、archive_enabled。
4. 运行 `validate-config.sh`（设置 PUSH_TASKS_FILE 指向该文件）。
5. 若使用 cron，执行 `sync-cron.sh --tasks <path>`。

## 如何增加新 content_kind

1. 在 task 配置中设置 `content_kind`（及 content_source_type、dedupe_strategy、render_strategy）。
2. 新增 `scripts/providers/content/<kind>.sh`：从 stdin 读 task JSON，向 stdout 输出单行 JSON，包含 title、topic_key、content、source_summary、content_kind。
3. 可选：在 `templates/content/<kind>/` 下添加模板。
4. 无需修改 run-task.sh、DB 表结构或 content.sh 的 if/else（content.sh 为 dispatcher，按名字调用 `<kind>.sh`）。

## 如何增加新 provider

1. 在 `scripts/providers/` 下新增 `<name>.sh`，从 stdin 读 task JSON，向 stdout 输出与类型相符的 payload（如 content 类需 title、topic_key、content、source_summary、content_kind）。
2. 在 tasks 中将 `provider` 设为该名字。
3. `validate-config.sh` 会检查 provider 文件是否存在。
