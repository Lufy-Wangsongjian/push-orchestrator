---
name: push-orchestrator
description: 统一管理定时推送任务（提醒、内容推荐、市场简报、运维与测试），供 OpenClaw 使用。配置驱动、SQLite 主状态、provider 架构、去重与归档。使用当用户需要配置或执行定时推送、replay、healthcheck、或扩展内容类型时。
---

# Push Orchestrator

## 目标

统一管理定时推送任务：提醒、内容推荐、市场简报、运维与测试。配置驱动，主状态存 SQLite，发送命令与目标均配置化，可与 OpenClaw 的 `message send` 等能力配合使用。

## 核心特性

- **配置驱动**：任务由外部 tasks JSON 定义，无硬编码任务。
- **Provider 架构**：`run-task.sh` 只做编排；内容由 provider（reminder、content、market-brief 等）生成。
- **Content 分发**：`type=content` 时由 `providers/content.sh` 按 `content_kind` 分发到 `providers/content/<kind>.sh`，不写死 if/else。
- **SQLite 主状态**：`state/push.db` 存任务快照、runs、去重、runtime_state、content_archive、replay、failure_stats。
- **去重**：基于 `dedupe_records`，支持 hash、topic_cooldown、hash_topic、window 等。
- **统一发送**：`send.sh` 从配置读取 `sendCommand`，仅当解析到 `message_id` 视为成功。
- **Replay**：支持 `--mode backfill|rerun`、`--force`、`--dry-run`。
- **Healthcheck**：支持文本与 `--json` 输出。
- **内容归档**：`archive_enabled` 时按 `content_kind`/`archive_category` 写入 `state/content_archive/` 并记入 DB。

## 单实例边界

当前按单机单实例设计：任务级 flock 锁，不支持多实例共享同一 SQLite。

## 配置方式

- **默认配置**：`config/default.json`（timezone、stateDbPath、sendCommand、defaultChannel、defaultTarget、retryPolicy、lockDir、contentArchiveDir 等）。
- **sendCommand**：建议写**相对 skill 根的路径**（如 `scripts/openclaw-send-wrapper.sh`），脚本会自动拼上当前 skill 根目录，这样**安装到任意 agent 的 workspace 都能用**，无需写死绝对路径。
- **Telegram 发送账号**：不写死。wrapper 会根据 `PUSH_WORKSPACE` 读 `openclaw.json`，找到该 workspace 对应的 agent，再查其 Telegram binding 的 `accountId`，作为 `openclaw message send --account` 使用。若设置了 `PUSH_SEND_ACCOUNT` 则优先使用。这样「当前 agent 对应哪个 Telegram bot，就用哪个账号发」。
- **Workspace 推导**：约定 skill 安装在 **`<workspace>/skills/<skill-name>`**（如 `workspace-pusher/skills/push-orchestrator`）。脚本据此推导 workspace：父目录为 `skills` 时 workspace = `SKILL_ROOT/../..`；若在 `<workspace>/.agents/skills/` 下（如 npx skills add 安装）则自动用 `SKILL_ROOT/../../..`。若已设置 `OPENCLAW_WORKSPACE` 则优先使用。
- **Tasks**：独立 JSON 文件，含 `tasks[]`，每项含 id、name、type、provider、cron、channel、target 等；`type=content` 时需 content_kind、content_source_type、dedupe_strategy、render_strategy。
- **Profiles**：`config/profiles/*.sample.json` 为示例，指向 example tasks 文件，非运行前提。

## Tasks 文件说明

- 必填：id、name、type、provider、enabled。
- type 合法值：reminder、content、market、ops、test。
- content 任务额外：content_kind、content_source_type、dedupe_strategy、render_strategy；可选 content_handler、template_path、source_config、metadata。
- dedupe.mode：none、window、hash、topic_cooldown、hash_topic。

## 内容类型扩展

新增内容类型时只需：
1. 在 task 配置中增加 `content_kind`（及 content_source_type、dedupe_strategy 等）。
2. 新增 `scripts/providers/content/<kind>.sh`，从 stdin 读 task JSON，输出 JSON：title、topic_key、content、source_summary、content_kind。
3. 可选：在 `templates/content/<kind>/` 下加模板。
4. 无需改 `run-task.sh` 主流程与 DB 主结构。

## 常用命令

```bash
# 从 skill 根目录执行（或设置 PUSH_SKILL_ROOT）
SKILL_ROOT="$(pwd)"

# 初始化 DB
./scripts/init-db.sh

# 校验配置与 tasks
PUSH_TASKS_FILE=./examples/tasks.content.example.json ./scripts/validate-config.sh

# 手动跑单个任务（dry-run 不真正发送）
./scripts/run-task.sh --tasks examples/tasks.content.example.json --task content-book --dry-run

# 同步 cron（仅管理 push-orchestrator 块）
./scripts/sync-cron.sh --tasks examples/tasks.content.example.json

# Replay
./scripts/replay.sh --tasks examples/tasks.content.example.json --task content-book --mode rerun --dry-run

# 历史与去重清理（可选，建议定期 cron）
./scripts/cleanup.sh --runs
./scripts/cleanup.sh --dedupe-days 90 --dry-run

# 健康检查
./scripts/healthcheck.sh
./scripts/healthcheck.sh --json
```

**路径**：`--tasks` 可为相对路径（相对 skill 根）或绝对路径；sync-cron 写入 cron 时会使用 tasks 的绝对路径。

## 错误码与退出码

脚本退出码与下表错误码一致（0=成功，非 0 即对应错误码，便于监控与脚本判断）。

## 错误码

| 码 | 名称 | 含义 |
|----|------|------|
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
| 11 | PROVIDER_FAILED | provider/handler 执行失败 |
| 12 | INTERNAL_ERROR | 内部错误 |

可选：设置 `PUSH_LOG_FORMAT=json` 时，日志输出单行 JSON（含 run_id、task_id、stage 等），便于集中采集。

## 更多文档

- 运维与扩展：`docs/OPERATIONS.md`
- 故障排查：`docs/TROUBLESHOOTING.md`
- 数据模型：`docs/DATA_MODEL.md`
- 发布与限制：`docs/RELEASE.md`
