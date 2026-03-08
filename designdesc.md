````markdown
# OpenClaw Push Orchestrator Skill 设计终稿（产品化完整版 · 内容类型扩展增强版）

## 1. 文档目的

本文档定义一个全新的 OpenClaw Skill：`push-orchestrator`。

该 Skill 用于统一管理定时推送任务，包括：

- 提醒类
- 内容推荐类
- 市场简报类
- 运维与测试类

本方案不以兼容旧方案为目标，而是直接按“可长期维护、可扩展、可分享”的产品化思路进行设计。  
其目标是形成一个独立、自包含、通用化的推送编排能力，并且能够在未来自然扩展到更多推送内容类型，而不破坏主框架。

本文档可用于：

- 内部架构评审
- 提供给 coding agent 实施
- 作为长期维护与对外分享的正式设计基线

---

## 2. 顶层设计目标

### 2.1 独立性
- 不依赖旧推送脚本
- 不依赖旧状态文件
- 不依赖某个固定个人目录结构
- 可独立初始化、启停和上线

### 2.2 通用性
- 不与某个固定用户强耦合
- 不与某个固定个人内容偏好强耦合
- 不与某个固定 OpenClaw CLI 路径强耦合
- 通过配置支持不同任务、不同通道、不同目标用户、不同内容类型

### 2.3 完整性
首版直接实现长期可维护版本，而不是最小可用版本：
- 配置驱动
- provider 架构
- SQLite 主状态层
- 去重
- 回放
- 健康检查
- 归档
- 文档
- 内容类型扩展机制

### 2.4 可分享
未来应可提供给他人使用，因此必须具备：
- examples
- sample profiles
- 可配置的发送命令
- 可配置的数据路径
- 与个人任务解耦的核心能力层

### 2.5 内容扩展性
系统必须支持未来新增各种推送内容类型，例如：
- `book`
- `musical`
- `startup_idea`
- `coffee`
- `ai_news`
- `poem`
- `movie`
- `podcast`
- `education_tip`
- `rss_digest`
- `custom_prompt`
- 其他未来扩展类型

新增内容类型时，不应要求修改主编排流程。

---

## 3. 核心设计原则

### 3.1 配置用文件，状态用数据库
系统采用三层分离：

#### 文件层
保存：
- 默认配置
- tasks schema
- channel schema
- profiles
- example task 文件
- 模板
- 脚本
- 文档

#### SQLite 层
保存：
- 任务快照
- 去重记录
- 执行历史
- runtime state
- replay 记录
- failure 统计
- 内容归档索引

#### 归档层
保存：
- 导出的历史内容
- 消息归档
- 人工查看文件

### 3.2 核心能力与个人任务分离
skill 核心只提供通用能力：

- 调度
- 执行
- 去重
- 发送
- replay
- healthcheck
- provider 接口
- 状态管理
- 内容扩展机制

个人任务如 books / musicals / startup / coffee 等，只作为：
- example task
- sample profile
- 示例模板
- 示例 handler

### 3.3 任务执行类型与内容类型分离
必须把以下两个维度分开：

#### A. 任务执行类型 `type`
表示任务执行流程语义：
- `reminder`
- `content`
- `market`
- `ops`
- `test`

#### B. 内容类型 `content_kind`
表示内容领域本身，例如：
- `book`
- `musical`
- `startup_idea`
- `coffee`
- `ai_news`
- `poem`
- `custom_prompt`

这样系统可以在不改变主执行流程的前提下，持续增加新的内容领域。

### 3.4 内容来源类型分离
对 `type=content` 的任务，还应通过 `content_source_type` 表示内容来源方式，例如：

- `template`
- `script`
- `prompt`
- `api`
- `rss`
- `db`
- `file`
- `hybrid`

这样可以支持未来更多生成方式，而不仅限于单一脚本逻辑。

### 3.5 编排层与生成层分离
- `run-task.sh` 只做编排
- provider 只做内容或数据生成
- `validate-payload.sh` 只做发送前校验
- `send.sh` 只做通道发送
- DB 层只做状态写入和查询

### 3.6 单实例边界
当前版本按**单机单实例**设计：
- 支持任务级锁
- 不支持多个实例共享同一 SQLite 状态库做分布式执行

---

## 4. 目录结构

```text
skills/push-orchestrator/
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

## 5. 配置模型

### 5.1 `config/default.json`

建议字段如下：

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

关键要求：

* `sendCommand` 必须配置化
* 不允许在核心逻辑中写死 OpenClaw CLI 路径
* `defaultTarget` 可以为空，由具体 task 文件决定

### 5.2 task 配置模型

具体 task 必须由外部 tasks 文件定义。

每个 task 至少包含：

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

对于 `type=content`，还必须支持：

* `content_kind`
* `content_source_type`
* `render_strategy`
* `dedupe_strategy`
* `content_handler`
* `template_path`
* `source_config`
* `metadata`

### 5.3 schema

必须提供：

* `tasks.schema.json`
* `channels.schema.json`

### 5.4 profiles 与 examples

必须提供 sample profile 与 example tasks，用于帮助他人快速上手，但 skill 不应依赖这些文件才能运行。

---

## 6. 任务类型与内容类型模型

### 6.1 执行类型 `type`

* `reminder`
* `content`
* `market`
* `ops`
* `test`

该字段决定执行流程与校验要求。

### 6.2 内容类型 `content_kind`

仅对 `type=content` 生效，用于描述内容领域，例如：

* `book`
* `musical`
* `startup_idea`
* `coffee`
* `ai_news`
* `poem`
* `custom_prompt`

未来新增内容类型时，应只需新增 handler 和配置，而无需修改主流程。

### 6.3 内容来源类型 `content_source_type`

用于描述内容来自哪里：

* `template`
* `script`
* `prompt`
* `api`
* `rss`
* `db`
* `file`
* `hybrid`

### 6.4 渲染策略 `render_strategy`

用于描述如何渲染最终消息，例如：

* `template`
* `markdown`
* `digest`
* `summary`

### 6.5 去重策略 `dedupe_strategy`

用于描述内容类的去重方式，例如：

* `none`
* `hash`
* `topic_cooldown`
* `hash_topic`
* `window`

---

## 7. 状态层设计

主状态层采用 SQLite：

```text
state/push.db
```

该数据库是 skill 的唯一主状态来源。

---

## 8. 数据模型

### 8.1 `tasks`

用于保存任务快照与元信息。

建议字段：

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

### 8.2 `runs`

用于保存任务执行历史。

建议字段：

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

### 8.3 `dedupe_records`

用于保存去重记录。

建议字段：

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

### 8.4 `runtime_state`

用于保存最近一次执行结果。

建议字段：

* `task_id`
* `type`
* `content_kind`
* `last_status`
* `last_run_at`
* `last_message_id`
* `last_error_code`
* `last_error_message`
* `last_duration_ms`

### 8.5 `content_archive`

用于保存内容归档索引。

建议字段：

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

### 8.6 `replay_records`

用于保存补发与重跑记录。

建议字段：

* `replay_id`
* `task_id`
* `content_kind`
* `target_date`
* `mode`
* `force_flag`
* `status`
* `created_at`

### 8.7 `failure_stats`

用于保存失败聚合统计。

建议字段：

* `date_bucket`
* `task_id`
* `content_kind`
* `error_code`
* `count`

---

## 9. 索引策略

必须至少建立以下索引：

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

## 10. 初始化与配置校验

### 10.1 `init-db.sh`

职责：

* 初始化数据库
* 创建表与索引
* 幂等执行

### 10.2 `validate-config.sh`

职责：

* 校验 default 配置
* 校验 tasks 文件
* 校验 channels 配置
* 校验 profiles
* 校验 schema
* 校验 provider 与 content handler 是否存在
* 校验数据库与归档目录是否可创建
* 校验 `type=content` 的扩展字段

---

## 11. 调度与执行

### 11.1 `sync-cron.sh`

职责：

* 根据指定 tasks 文件同步 cron
* 管理 skill 自己的 cron block
* 保持幂等
* 支持 dry-run

### 11.2 `run-task.sh`

职责：

* 作为统一执行入口
* 只负责编排，不负责具体内容生成

调用方式：

```bash
run-task.sh --tasks <tasks_file> --task <task_id> [--mode normal|backfill|rerun] [--force] [--dry-run]
```

执行流程：

1. 解析参数
2. 加载配置与 tasks 文件
3. 校验配置
4. 初始化 DB（若不存在）
5. 设置时区
6. 获取任务锁
7. 执行 dedupe 判断
8. 调用 provider
9. 若 `type=content`，由 `providers/content.sh` 根据 `content_kind` 分发到 handler
10. 校验 payload
11. 发送
12. 写入 DB
13. 释放锁

---

## 12. Provider 架构与内容扩展机制

### 12.1 Provider 列表

* `reminder.sh`
* `content.sh`
* `market-price.sh`
* `market-news.sh`
* `market-brief.sh`
* `ops.sh`
* `test.sh`

### 12.2 Content Dispatcher

`providers/content.sh` 必须作为 dispatcher，而不是一个不断膨胀的单体脚本。

它的职责是：

* 读取 `content_kind`
* 读取 `content_source_type`
* 选择合适的内容 handler
* 统一返回标准 payload

### 12.3 Content Handlers

至少提供以下 handler 示例：

* `providers/content/book.sh`
* `providers/content/musical.sh`
* `providers/content/startup_idea.sh`
* `providers/content/coffee.sh`
* `providers/content/ai_news.sh`
* `providers/content/poem.sh`
* `providers/content/custom_prompt.sh`

每个 handler 至少应返回：

* `title`
* `topic_key`
* `content`
* `source_summary`
* `content_kind`

### 12.4 内容类型扩展标准

未来新增一种内容类型时，标准步骤应为：

1. 在 task 配置中新增 `content_kind`
2. 新增对应 handler
3. 如有需要，新增模板目录
4. 配置其 `content_source_type`、`render_strategy`、`dedupe_strategy`
5. 不需要修改 `run-task.sh` 主流程
6. 不需要修改 DB 主结构

---

## 13. 去重策略

去重必须依赖 SQLite 中的 `dedupe_records`，而不是扫描 Markdown 文件。

### 13.1 reminder

* 默认不过滤
* 允许极短防抖

### 13.2 content

建议默认使用：

* `hash_topic`

即同时检查：

* `content_hash`
* `topic_key`
* `cooldown_days`

规则：

* hash 相同视为严格重复
* 同 topic 在冷却期内视为近似重复

不同 `content_kind` 允许未来使用不同策略。

### 13.3 market

建议默认使用：

* `window`

同时对 freshness 进行校验。

---

## 14. 市场数据真实性机制

市场任务必须严格区分：

### 14.1 真值层

由 `market-price.sh` 负责：

* 获取可信行情数据
* 返回价格、涨跌、来源 URL、时间戳

### 14.2 摘要层

由 `market-news.sh` 负责：

* 获取新闻背景
* 返回摘要和来源链接

### 14.3 渲染层

由 `market-brief.sh` 负责：

* 合并真值与摘要
* 生成最终消息

要求：

* Tavily 只能用于新闻检索，不可作为唯一真值来源
* 若无可信真值数据，必须返回“数据不可用”
* 不允许编造价格或涨跌

---

## 15. Payload 校验

`validate-payload.sh` 负责：

### content / reminder / ops

* 非空校验
* 长度校验
* 标题 / topic_key 校验（若适用）
* `content_kind` 一致性校验
* `render_strategy` 完整性校验

### market

* 来源校验
* URL 校验
* 数据时间戳校验
* stale 校验
* “有数值但无来源”拦截

---

## 16. 发送策略

`send.sh` 负责统一发送。
发送命令由配置 `sendCommand` 指定。

### 发送成功定义

仅当以下条件同时成立时视为成功：

1. 发送命令退出码为 0
2. 成功解析到 `message_id`

否则视为失败。

---

## 17. replay 设计

`replay.sh` 必须支持：

* `backfill`
* `rerun`
* `force`
* `dry-run`

### backfill

* 仅补发
* 不新增 dedupe 记录
* 写入 `runs` 与 `replay_records`

### rerun

* 作为正式重新执行
* 可新增 dedupe 记录
* 若未加 `--force`，仍执行 dedupe 判断

---

## 18. 健康检查

`healthcheck.sh` 必须支持：

* 文本输出
* JSON 输出

检查项包括：

* 配置是否合法
* DB 是否可读写
* cron 是否同步
* 最近 24h 成功率
* 最近失败 Top N
* stale tasks
* provider 是否存在
* content handler 是否存在
* 归档目录是否可写

---

## 19. 内容归档

当 task 配置 `archive_enabled=true` 时，应将最终内容写入：

```text
state/content_archive/
```

并按 `content_kind` 或 `archive_category` 分目录，例如：

```text
state/content_archive/book/
state/content_archive/coffee/
state/content_archive/ai_news/
```

同时在 `content_archive` 表中写入索引记录。

说明：

* 归档文件用于人工查看
* 检索与去重主逻辑仍基于 DB

---

## 20. 标准错误码

| 错误码 | 名称                  | 含义                      |
| --- | ------------------- | ----------------------- |
| 0   | SUCCESS             | 成功                      |
| 1   | CONFIG_INVALID      | 配置错误                    |
| 2   | LOCK_ACQUIRE_FAILED | 锁获取失败                   |
| 3   | DEDUPE_HIT          | 去重命中                    |
| 4   | DATA_UNAVAILABLE    | 数据不可用                   |
| 5   | STALE_DATA          | 数据过期                    |
| 6   | SOURCE_UNTRUSTED    | 来源不可信                   |
| 7   | SEND_TIMEOUT        | 发送超时                    |
| 8   | SEND_REJECTED       | 无 message_id 或发送被拒绝     |
| 9   | DB_WRITE_FAILED     | 数据库写入失败                 |
| 10  | PAYLOAD_INVALID     | payload 非法              |
| 11  | PROVIDER_FAILED     | provider / handler 执行失败 |
| 12  | INTERNAL_ERROR      | 内部错误                    |

---

## 21. 文档要求

必须提供：

* `SKILL.md`
* `docs/OPERATIONS.md`
* `docs/TROUBLESHOOTING.md`
* `docs/RELEASE.md`
* `docs/DATA_MODEL.md`

并完整描述：

* 配置方式
* tasks 用法
* 内容类型扩展方式
* DB 结构
* 常见问题
* 运维命令
* 错误码
* 单实例边界

---

## 22. 完成定义（DoD）

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
10. `content.sh` 是 dispatcher，而不是大 if/else
11. 新增 `content_kind` 时无需改主流程
12. `send.sh` 仅在拿到 `message_id` 时视为成功
13. replay 支持 backfill / rerun / force / dry-run
14. healthcheck 支持文本与 JSON
15. archive 可按 `content_kind` 正常写入
16. examples / profiles 完整
17. 文档完整可读

---

## 23. 最终结论

`push-orchestrator` 应作为一个全新的、产品化的 OpenClaw Skill 来实现，而不是旧脚本体系的兼容包装层。

其最终架构应采用：

* 文件配置层
* SQLite 主状态层
* provider + content dispatcher + handlers 架构
* 可配置发送适配层
* examples / profiles 分层
* 可归档、可 replay、可 healthcheck 的完整能力体系
* 明确的内容类型扩展机制

该版本适合作为长期维护、对外分享与持续扩展的正式设计基线。

```
```
