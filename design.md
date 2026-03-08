````markdown
# OpenClaw Push Orchestrator Skill 实施指令版（供 Coding Agent 直接执行）

## 1. 任务名称

实现一个 OpenClaw Skill：`push-orchestrator`

---

## 2. 任务目标

请实现一个**独立、通用、可分享、可长期维护、支持内容类型扩展**的 OpenClaw Skill：`push-orchestrator`。

该 Skill 用于统一管理定时推送任务，包括：

- 提醒类任务
- 内容推荐类任务
- 市场简报类任务
- 运维与测试类任务

本实现不考虑兼容旧方案，不做迁移包装层，直接交付一套**产品化完整新实现**。

---

## 3. 设计原则（必须遵守）

### 3.1 不考虑旧方案迁移
- 不兼容旧 cron
- 不兼容旧 dedupe 文件
- 不兼容旧 Markdown 扫描逻辑作为主状态
- 新 skill 必须是独立、自包含的新实现

### 3.2 一步到位
首版直接实现长期可维护版本，不做最小可用简化。

必须首版实现：
- 配置驱动
- provider 架构
- SQLite 主状态层
- 任务级并发锁
- 统一发送器
- 去重策略
- 运行历史
- replay
- payload 校验
- healthcheck
- 内容归档
- 文档
- examples / profiles
- 内容类型扩展机制

### 3.3 核心 skill 必须通用化
不得和以下内容强耦合：

- 某个固定 OpenClaw 路径
- 某个固定 Telegram target
- 某个固定 workspace 路径
- 某个固定个人偏好
- 某个固定内容类别
- 某个固定任务名

所有这类信息都必须配置化。

### 3.4 配置用文件，状态用 SQLite
系统必须采用三层分离：

#### 文件层
保存：
- 默认配置
- schema
- profiles
- examples
- 模板
- provider / handler 脚本
- 文档

#### SQLite 层
保存：
- 任务快照
- 去重记录
- 运行历史
- runtime state
- replay 记录
- failure stats
- content archive 索引

#### 归档层
保存：
- 导出的消息内容
- 历史归档文件
- 人工查看文件

### 3.5 任务执行类型与内容类型分离
必须把这两个概念分开：

#### 任务执行类型 `type`
表示任务执行流程语义：
- `reminder`
- `content`
- `market`
- `ops`
- `test`

#### 内容类型 `content_kind`
表示内容领域：
- `book`
- `musical`
- `startup_idea`
- `coffee`
- `ai_news`
- `poem`
- `movie`
- `podcast`
- `rss_digest`
- `custom_prompt`
- 其他未来扩展类型

不得只依赖 `type=content` 做所有内容分支。

### 3.6 内容来源类型必须可扩展
新增字段：

#### `content_source_type`
表示内容来自哪里：
- `template`
- `script`
- `prompt`
- `api`
- `rss`
- `db`
- `file`
- `hybrid`

不得把所有内容都写死成单一生成方式。

---

## 4. 必须创建的目录与文件

请在以下目录下完整实现 skill：

```text
/root/.openclaw/workspace/skills/push-orchestrator/
  SKILL.md
  config/
    default.json
    tasks.schema.json
    channels.schema.json
    profiles/
      personal.sample.json
      reminder.sample.json
      market.sample.json
      content.sample.json
  templates/
    reminders/
    content/
      book/
      musical/
      startup_idea/
      coffee/
      ai_news/
      poem/
      custom_prompt/
    market/
  scripts/
    init-db.sh
    validate-config.sh
    sync-cron.sh
    run-task.sh
    send.sh
    validate-payload.sh
    replay.sh
    healthcheck.sh
    providers/
      reminder.sh
      content.sh
      market-price.sh
      market-news.sh
      market-brief.sh
      ops.sh
      test.sh
      content/
        book.sh
        musical.sh
        startup_idea.sh
        coffee.sh
        ai_news.sh
        poem.sh
        custom_prompt.sh
    lib/
      db.sh
      locks.sh
      task.sh
      logging.sh
      time.sh
      senders.sh
      content.sh
  state/
    push.db
    run_history_export/
    content_archive/
    README.md
  examples/
    tasks.personal.example.json
    tasks.market.example.json
    tasks.reminder.example.json
    tasks.content.example.json
  docs/
    OPERATIONS.md
    TROUBLESHOOTING.md
    RELEASE.md
    DATA_MODEL.md
````

---

## 5. 必须实现的总体能力

### 5.1 配置驱动

所有任务必须由外部 tasks 文件定义，不得在脚本里写死任务。

### 5.2 provider 架构

`run-task.sh` 只负责编排。
具体内容生成由 provider 负责。

### 5.3 content provider 必须是 dispatcher

`providers/content.sh` 不得通过大量 `if/elif` 写死不同内容类型。
它必须作为 **dispatcher**，根据 `content_kind` 分发到具体 handler：

* `providers/content/book.sh`
* `providers/content/musical.sh`
* `providers/content/startup_idea.sh`
* `providers/content/coffee.sh`
* `providers/content/ai_news.sh`
* `providers/content/poem.sh`
* `providers/content/custom_prompt.sh`

### 5.4 SQLite 主状态层

核心运行态不得使用 JSON 文件作为主存储。
必须使用 SQLite：`state/push.db`

### 5.5 通道与命令配置化

发送命令必须从配置读取，不得硬编码固定 OpenClaw 路径。

### 5.6 内容类型扩展能力必须首版支持

系统必须允许未来新增新内容类型时，做到：

* 不改主编排流程
* 最少改动 schema
* 新增 handler 即可接入
* DB 和 archive 能记录该内容类型
* 模板能按类型管理
* 去重策略能按类型细化

---

## 6. 配置与 schema 要求

### 6.1 `config/default.json`

必须至少包含：

```json
{
  "timezone": "Asia/Shanghai",
  "workspaceRoot": ".",
  "stateDbPath": "./state/push.db",
  "sendCommand": "openclaw message send",
  "defaultChannel": "telegram",
  "defaultTarget": "",
  "retryPolicy": {
    "maxAttempts": 3,
    "backoffSeconds": [2, 6, 15]
  },
  "historyRetentionDays": 30,
  "lockDir": "/tmp/push-orchestrator/locks",
  "staleTaskFactor": 2,
  "contentArchiveDir": "./state/content_archive",
  "runHistoryExportDir": "./state/run_history_export"
}
```

### 6.2 `config/tasks.schema.json`

每个 task 至少支持以下字段：

* `id`
* `name`
* `description`
* `enabled`
* `type`
* `provider`
* `severity`
* `cron`
* `channel`
* `target`
* `timeout_seconds`
* `retry_policy_override`
* `notification_policy`
* `dedupe.mode`
* `dedupe.window_minutes`
* `dedupe.topic_key`
* `dedupe.cooldown_days`
* `requires_realtime`
* `source_priority`
* `archive_enabled`
* `archive_category`
* `tags`

### 对于 `type=content`，必须额外支持：

* `content_kind`
* `content_source_type`
* `render_strategy`
* `dedupe_strategy`
* `content_handler`（可选，默认等于 `content_kind`）
* `template_path`（可选）
* `source_config`（对象，支持不同 source 类型）
* `metadata`（对象，预留扩展）

### type 合法值

* `reminder`
* `content`
* `market`
* `ops`
* `test`

### content_source_type 合法值

* `template`
* `script`
* `prompt`
* `api`
* `rss`
* `db`
* `file`
* `hybrid`

### dedupe.mode 合法值

* `none`
* `window`
* `hash`
* `topic_cooldown`
* `hash_topic`

### dedupe_strategy 合法值

* `none`
* `hash`
* `topic_cooldown`
* `hash_topic`
* `window`

### severity 合法值

* `high`
* `medium`
* `low`

### 6.3 `config/channels.schema.json`

定义发送通道 schema，至少允许未来支持多通道。

### 6.4 `config/profiles/*.json`

至少提供：

* `personal.sample.json`
* `reminder.sample.json`
* `market.sample.json`
* `content.sample.json`

这些文件作为示例配置，不得成为 skill 的运行前提。

---

## 7. examples 文件要求

必须提供：

```text
examples/
  tasks.personal.example.json
  tasks.market.example.json
  tasks.reminder.example.json
  tasks.content.example.json
```

要求：

* 用于展示典型内容任务如何配置
* 可以包含 books / musicals / startup / coffee / ai_news 等示例
* 但 skill 核心逻辑不得依赖这些具体名字才能运行

---

## 8. 数据库必须一步到位实现

数据库路径：

```text
state/push.db
```

初始化脚本：

```text
scripts/init-db.sh
```

### 8.1 必须创建的数据表

#### 1）`tasks`

增加以下字段：

* `id`
* `name`
* `type`
* `content_kind`
* `provider`
* `severity`
* `enabled`
* `cron_expr`
* `channel`
* `target`
* `archive_category`
* `config_json`
* `updated_at`

#### 2）`runs`

增加以下字段：

* `run_id`
* `task_id`
* `type`
* `content_kind`
* `trigger_type`
* `mode`
* `status`
* `error_code`
* `error_message`
* `started_at`
* `finished_at`
* `duration_ms`
* `message_id`
* `payload_hash`
* `data_timestamp`
* `source_summary`

#### 3）`dedupe_records`

增加以下字段：

* `id`
* `task_id`
* `type`
* `content_kind`
* `content_hash`
* `topic_key`
* `title`
* `source`
* `sent_at`
* `cooldown_until`
* `mode`

#### 4）`runtime_state`

* `task_id`
* `type`
* `content_kind`
* `last_status`
* `last_run_at`
* `last_message_id`
* `last_error_code`
* `last_error_message`
* `last_duration_ms`

#### 5）`content_archive`

* `archive_id`
* `task_id`
* `content_kind`
* `archive_category`
* `topic`
* `title`
* `content_path`
* `source_summary`
* `created_at`
* `sent_at`

#### 6）`replay_records`

* `replay_id`
* `task_id`
* `content_kind`
* `target_date`
* `mode`
* `force_flag`
* `status`
* `created_at`

#### 7）`failure_stats`

* `date_bucket`
* `task_id`
* `content_kind`
* `error_code`
* `count`

### 8.2 索引要求

必须建立索引：

* `runs(task_id)`
* `runs(started_at)`
* `runs(content_kind)`
* `dedupe_records(task_id)`
* `dedupe_records(content_hash)`
* `dedupe_records(topic_key)`
* `dedupe_records(content_kind)`
* `runtime_state(task_id)`
* `failure_stats(date_bucket)`

---

## 9. 脚本实现要求

### 9.1 `scripts/init-db.sh`

职责：

* 初始化 DB
* 创建表和索引
* 幂等执行

### 9.2 `scripts/validate-config.sh`

职责：

* 校验 default 配置
* 校验 tasks 文件
* 校验 profiles
* 校验 channels 配置
* 校验 schema
* 校验 provider / content handler 是否存在
* 校验 task id 唯一
* 校验 DB / archive 目录可创建
* 对 `type=content` 的任务，校验：

  * `content_kind`
  * `content_source_type`
  * `dedupe_strategy`
  * `render_strategy`

### 9.3 `scripts/sync-cron.sh`

调用方式：

```bash
sync-cron.sh --tasks ./examples/tasks.content.example.json
```

职责：

* 根据指定 tasks 文件同步 cron
* 幂等
* 支持 dry-run
* 只管理自己的 cron block

### 9.4 `scripts/run-task.sh`

调用方式：

```bash
run-task.sh --tasks <tasks_file> --task <task_id> [--mode normal|backfill|rerun] [--force] [--dry-run]
```

执行流程：

1. 解析参数
2. 加载 default 配置 + 指定 tasks 文件
3. 执行 `validate-config.sh`
4. 执行 `init-db.sh`（若 DB 不存在）
5. 设置 `TZ=Asia/Shanghai`
6. 获取任务级锁
7. 读取 task 配置
8. 执行 dedupe 判断
9. 按 `provider` 调用 provider
10. 若 `type=content`，由 `providers/content.sh` 再按 `content_kind` 分发到 handler
11. 执行 `validate-payload.sh`
12. 若非 dry-run，调用 `send.sh`
13. 写入 DB：

* tasks
* runs
* runtime_state
* dedupe_records（若成功且应写入）
* replay_records（若 replay）
* content_archive（若开启）

14. 释放锁

要求：

* `run-task.sh` 不得直接写死 books / musicals / coffee 等逻辑
* 只能依赖 task 配置与 provider / handler 机制

### 9.5 `scripts/send.sh`

职责：

* 从 `sendCommand` 读取命令
* 统一发送
* 支持 retry
* 输出标准 JSON

成功定义：

1. 命令退出码为 0
2. 成功解析 `message_id`

### 9.6 `scripts/validate-payload.sh`

职责：

* 发送前校验 payload

#### 对 `type=content`

必须校验：

* content 非空
* title / topic_key 存在（若适用）
* 内容适配对应 `content_kind`
* 渲染策略完成

#### 对 `type=market`

必须校验：

* 来源 URL
* 数据时间戳
* stale
* 真值来源可信

### 9.7 `scripts/replay.sh`

必须支持：

* `--mode backfill`
* `--mode rerun`
* `--force`
* `--dry-run`

### 9.8 `scripts/healthcheck.sh`

检查项至少包括：

1. 配置合法
2. DB 可读写
3. cron 是否同步
4. 最近 24h 成功率
5. 最近失败 Top N
6. stale tasks
7. provider 是否存在
8. content handler 是否存在
9. archive 目录是否可写

---

## 10. lib 层必须实现

### 10.1 `lib/db.sh`

职责：

* SQLite 读写封装
* 写 runs / dedupe / runtime / replay / archive / failure stats

### 10.2 `lib/locks.sh`

职责：

* flock 封装
* 锁路径与超时

### 10.3 `lib/task.sh`

职责：

* 从 tasks 文件解析 task
* 读取 `content_kind` / `content_source_type` 等字段
* task 快照写入 DB

### 10.4 `lib/logging.sh`

职责：

* 标准日志输出
* JSON 输出辅助

### 10.5 `lib/time.sh`

职责：

* 时区统一
* 时间格式与 stale 判断

### 10.6 `lib/senders.sh`

职责：

* sendCommand 构造
* message_id 解析

### 10.7 `lib/content.sh`

职责：

* content handler 分发
* content 类型合法性检查
* 渲染策略与来源类型辅助逻辑

---

## 11. provider / handler 接口要求

### 11.1 `providers/content.sh`

必须作为 dispatcher：

* 根据 `content_kind` 选择 handler
* 根据 `content_source_type` 与 `source_config` 协调生成
* 不得写成一个越来越长的 if/else 大脚本

### 11.2 必须提供的 handler 示例

至少实现：

* `providers/content/book.sh`
* `providers/content/musical.sh`
* `providers/content/startup_idea.sh`
* `providers/content/coffee.sh`
* `providers/content/ai_news.sh`
* `providers/content/poem.sh`
* `providers/content/custom_prompt.sh`

每个 handler 至少返回：

* `title`
* `topic_key`
* `content`
* `source_summary`
* `content_kind`

### 11.3 `providers/market-price.sh`

获取真值行情数据。

### 11.4 `providers/market-news.sh`

获取市场新闻摘要。

### 11.5 `providers/market-brief.sh`

合并真值与新闻生成最终市场简报。

### 11.6 `providers/reminder.sh`

生成提醒类消息。

### 11.7 `providers/ops.sh`

生成 monitor / maintenance / test_push 消息。

### 11.8 `providers/test.sh`

提供测试 stub。

---

## 12. 去重策略要求

主去重逻辑必须基于 SQLite `dedupe_records`。

### 12.1 reminder

* 默认 `none`
* 支持短防抖

### 12.2 content

默认推荐 `hash_topic`

规则：

* `content_hash` 相同 => 严格重复
* `topic_key` 在冷却期内 => 近似重复

不同 `content_kind` 允许未来使用不同去重策略。

### 12.3 market

默认 `window`

* 防窗口内重复
* stale 由 payload 校验负责

---

## 13. 内容归档要求

当 `archive_enabled=true`：

1. 最终内容写入：

   ```text
   state/content_archive/
   ```

2. 路径应按 `content_kind` 或 `archive_category` 分目录，例如：

   ```text
   state/content_archive/book/
   state/content_archive/coffee/
   state/content_archive/ai_news/
   ```

3. 在 `content_archive` 表中写索引

---

## 14. 标准错误码（必须统一）

| 错误码 | 名称                  | 含义                    |
| --- | ------------------- | --------------------- |
| 0   | SUCCESS             | 成功                    |
| 1   | CONFIG_INVALID      | 配置错误                  |
| 2   | LOCK_ACQUIRE_FAILED | 锁失败                   |
| 3   | DEDUPE_HIT          | 去重命中                  |
| 4   | DATA_UNAVAILABLE    | 数据不可用                 |
| 5   | STALE_DATA          | 数据过期                  |
| 6   | SOURCE_UNTRUSTED    | 来源不可信                 |
| 7   | SEND_TIMEOUT        | 发送超时                  |
| 8   | SEND_REJECTED       | 无 message_id / 被拒绝    |
| 9   | DB_WRITE_FAILED     | DB 写入失败               |
| 10  | PAYLOAD_INVALID     | payload 非法            |
| 11  | PROVIDER_FAILED     | provider/handler 执行失败 |
| 12  | INTERNAL_ERROR      | 内部错误                  |

---

## 15. 新增内容类型的扩展要求

必须在文档与实现中支持以下标准扩展流程：

新增一个内容类型时，应只需要：

1. 在 task 配置中新增 `content_kind`

2. 新增对应 handler 文件，例如：

   ```text
   providers/content/travel.sh
   ```

3. 新增模板目录（如需要）：

   ```text
   templates/content/travel/
   ```

4. 如有特殊去重规则，只在配置或 handler 内定义

5. 无需修改 `run-task.sh` 主流程

6. 无需修改 DB 主结构

---

## 16. 测试要求

至少覆盖：

1. 配置校验失败
2. DB 初始化成功
3. content hash 去重命中
4. topic cooldown 命中
5. market 无数据
6. market stale data
7. send 无 message_id
8. replay backfill
9. replay rerun
10. sync-cron 幂等
11. 并发执行同一任务
12. content archive 写入
13. content handler 分发正确
14. 新增 content_kind 后无需改主流程

---

## 17. 必须交付的文档

### `SKILL.md`

必须包含：

* 目标
* 核心特性
* 单实例边界
* 配置方式
* tasks 文件说明
* 内容类型扩展机制
* DB 说明
* 常用命令
* 错误码

### `docs/OPERATIONS.md`

必须包含：

* 初始化数据库
* 配置 tasks 文件
* 同步 cron
* 手工运行任务
* replay
* healthcheck
* 如何增加新 task
* 如何增加新 content_kind
* 如何增加新 provider

### `docs/TROUBLESHOOTING.md`

必须包含：

* 常见错误码
* 如何查 DB
* 如何处理锁问题
* 如何定位 provider / handler 失败
* 如何定位 send 失败
* 如何处理 archive 问题

### `docs/RELEASE.md`

必须包含：

* 版本说明
* 已知限制
* 回滚方法
* 扩展建议

### `docs/DATA_MODEL.md`

必须包含：

* 表结构
* 字段说明
* 索引说明
* `content_kind` 相关字段说明
* 典型查询示例

---

## 18. 完成定义（DoD）

以下必须全部满足：

1. skill 可独立初始化
2. `push.db` 可成功初始化
3. 主状态写入 SQLite
4. tasks 由外部文件驱动
5. `sendCommand` / `target` / `channel` 可配置
6. `run-task.sh` 只做编排
7. 去重基于 SQLite
8. content 支持 `hash + topic cooldown`
9. market 实现真值层 / 摘要层分离
10. `content.sh` 是 dispatcher，不是大 if/else
11. 新增 `content_kind` 时无需改主流程
12. `send.sh` 仅在拿到 `message_id` 时视为成功
13. replay 支持 backfill / rerun / force / dry-run
14. healthcheck 支持文本与 JSON
15. archive 可按 `content_kind` 正常写入
16. examples / profiles 完整
17. 文档完整可读

---

## 19. coding agent 回复格式要求

请按以下结构回复：

### A. 修改文件列表

### B. 初始化与启用步骤

### C. 示例运行命令

### D. 测试结果

### E. 已知限制与建议

```
```
