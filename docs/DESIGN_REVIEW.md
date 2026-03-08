# Push Orchestrator 设计评审：缺陷与优化空间

## 一、设计缺陷与风险

### 1. 失败时未写入 failure_stats

**现状**：`run-task.sh` 在 provider 失败、payload 非法、发送失败、锁失败时直接 exit，未调用 `db_upsert_failure_stat`。

**影响**：healthcheck / 运维无法依赖 `failure_stats` 做“最近失败 Top N”或按错误码聚合。

**建议**：在任意失败分支退出前，按 `(date_bucket, task_id, content_kind, error_code)` 调用 `db_upsert_failure_stat`；或在 run-task.sh 顶层用 trap 在非 0 退出时统一写一条失败统计。

---

### 2. 失败时未更新 runtime_state

**现状**：仅在成功路径更新 `runtime_state`。任务连续失败时，`last_status` / `last_error_*` 仍是上一次结果。

**影响**：运维看 runtime_state 会误判“上次成功”，不利于告警与排障。

**建议**：在发送失败、provider 失败等分支写 DB 后，同样调用 `db_upsert_runtime_state(..., "failed", ..., error_code, error_message)`。

---

### 3. send.sh 重试退避未按配置使用

**现状**：`config/default.json` 有 `retryPolicy.backoffSeconds: [2, 6, 15]`，但 `send.sh` 用固定 `PUSH_SEND_BACKOFF="2 6 15"` 且只取第一个数：`read -r sec _ <<< "$backoff"`，导致每次重试都 sleep 2 秒。

**影响**：重试退避未真正递增，可能加重下游压力。

**建议**：从 default.json 读 backoff 数组，或按 attempt 索引取 backoff[attempt-1]；在 send.sh 中按 attempt 选择本次 sleep 秒数。

---

### 4. sync-cron.sh 的 RUN_SCRIPT 与工作目录

**现状**：cron 行写为 `$cron $RUN_SCRIPT --tasks $TASKS_FILE --task $id`。`RUN_SCRIPT` 为绝对路径，`run-task.sh` 用 `BASH_SOURCE` 解析 SKILL_ROOT，不依赖当前工作目录。

**风险**：若用户把 skill 装在多路径（如复制一份改 tasks），cron 里 TASKS_FILE 是相对路径，可能指向错误文件；且不同 crontab 用户/环境可能没有 PUSH_SKILL_ROOT。

**建议**：sync-cron 写入 cron 时，将 `--tasks` 改为绝对路径（基于当前 SKILL_ROOT），或文档明确“cron 仅支持单 skill 实例、tasks 路径相对 skill 根”。可选：在 run-task 开头若发现 tasks 文件不存在，尝试用脚本目录反推 SKILL_ROOT 再拼一次路径。

---

### 5. dedupe_records 无清理策略

**现状**：去重记录只增不删，长期运行会无限增长。

**影响**：hash 去重永远生效（符合预期），但 topic_cooldown 会查越来越多行；且磁盘与查询变慢。

**建议**：增加“保留窗口”（如只保留 N 天或按 content_kind 保留条数），由定时任务或 healthcheck 侧脚本定期 DELETE；或在 design 中明确“需定期清理 dedupe_records（见 OPERATIONS）”。

---

### 6. cooldown_until 存的是“时间”还是“epoch”

**现状**：`db_insert_dedupe` 传入的 `cooldown_until` 来自 `cooldown_until_epoch`（秒级 epoch）。`db_dedupe_topic_cooldown_hit` 用 `CAST(cooldown_until AS INTEGER) > $now_epoch` 比较。

**风险**：若某处误传 ISO 时间字符串，比较会错或报错。

**建议**：表/文档约定 `cooldown_until` 一律为 epoch 秒（或统一 ISO）；写入前归一化，避免混用。

---

### 7. 路径注入与 sql_escape 覆盖不全

**现状**：`db.sh` 用 `sql_escape` 仅处理单引号，且部分字段直接拼进 SQL。

**风险**：若 task_id / content_hash 等来自不可信输入且含 `\` 或控制字符，虽不会直接 SQL 注入，但可能引发异常或异常存储；极端情况下若有其他拼接点遗漏，存在理论风险。

**建议**：保持“仅信任 config/tasks”的假设，在文档中写明“tasks 与 config 为受信输入”；如有从外部读入的字段，再做严格校验或参数化（如用 sqlite3 的 -separator 与逐列读入减少拼接）。

---

### 8. market 真值层与 design 不一致

**现状**：design 要求“market 真值层 / 摘要层分离”“Tavily 仅用于新闻、不可作唯一真值”“无真值须返回数据不可用”。当前 `market-price.sh` / `market-news.sh` 为占位，未接入真实 API。

**影响**：上线前必须接入真实数据源并校验 payload（来源 URL、时间戳、stale）；否则易触犯“不得编造价格”的约束。

**建议**：在 RELEASE.md / OPERATIONS 中明确“market 为占位，生产前必须替换并做真值/摘要分离与校验”。

---

## 二、优化空间

### 1. 配置与 tasks 路径解析统一

**现状**：`--tasks` 可为相对路径；若用户传绝对路径，`PUSH_TASKS_FILE="$SKILL_ROOT/$TASKS_FILE"` 会拼错。

**建议**：若 `$TASKS_FILE` 已是绝对路径则直接使用，否则拼 `$SKILL_ROOT/$TASKS_FILE`。

---

### 2. run-task 中 provider 执行两次的可读性

**现状**：在“需要做 dedupe”分支先跑一次 provider 拿 payload，若未命中再“复用 payload”；在 else 分支再跑一次 provider。逻辑正确但阅读成本略高。

**建议**：可统一为“先执行 provider 一次，再根据 FORCE/backfill/dedupe_mode 决定是否做 hash/topic 检查；若命中则 exit，否则继续”。这样只在一处调 provider，逻辑更直观。

---

### 3. 日志与可观测性

**现状**：日志以 log_info/log_error 为主，无结构化（如 JSON）或 request_id/run_id 贯穿。

**建议**：可选增加“运行日志模式”：输出 JSON 行（含 run_id、task_id、stage、duration_ms、error_code），便于集中采集与告警。

---

### 4. validate-config 与 schema 的深度

**现状**：validate-config 检查 task 存在、id 唯一、type=content 必填字段、provider/handler 存在；未用 tasks.schema.json 做 JSON Schema 校验。

**建议**：若需严格符合 schema，可增加一步 `ajv` 或 `jq`+schema 的校验；或在文档中说明“schema 仅作参考，当前以脚本校验为准”。

---

### 5. 历史数据保留与清理

**现状**：design 有 `historyRetentionDays`，但 init-db、run-task、replay 均未使用；runs 表会一直增长。

**建议**：增加定时或按需清理：删除 `started_at` 早于 (now - historyRetentionDays) 的 runs；可选对 dedupe_records 做窗口清理（见上）。

---

### 6. 内容归档路径的可移植性

**现状**：`content_path` 存绝对路径（如 `$PUSH_CONTENT_ARCHIVE_DIR/book/arch-xxx.md`）。若 skill 迁移到另一台机或换目录，索引会失效。

**建议**：要么存相对路径（相对 contentArchiveDir），读取时再拼；要么在文档中说明“归档目录不建议迁移，迁移需重写 content_archive.content_path 或重新归档”。

---

### 7. replay 的 target_date 未真正参与逻辑

**现状**：replay.sh 支持 `--target-date`，但未传给 run-task.sh；run-task 也未根据 target_date 做“按日回放”的语义（如只补某天漏跑）。

**影响**：replay 目前等价于“再跑一遍任务”，与“按日期补发”的常见理解有差距。

**建议**：若需“按日 replay”，可在 run-task 增加 `--target-date`，provider 或 payload 生成时使用该日期（如数据源按日拉取）；否则在文档中明确“当前 replay 为整任务重跑，不按日期过滤”。

---

### 8. 错误码与退出码的对应

**现状**：设计文档定义了 0–12 错误码，run-task 各分支 exit 1/2/3/8/10/11 等，与错误码表一致。

**建议**：在 SKILL.md / TROUBLESHOOTING 中列一张“退出码 ↔ 错误码”表，便于脚本和监控统一处理。

---

## 三、小结

**已在本轮实现中修复：**

- **失败时写入 failure_stats 与 runtime_state**：run-task.sh 在锁失败、provider 失败、payload 非法、发送失败时统一通过 `record_failure_and_exit` 写入 runs、runtime_state、failure_stats。
- **send.sh 退避按 attempt 使用配置**：重试时按 `backoff_arr[attempt-1]` 取秒数，支持 config 中的 `retryPolicy.backoffSeconds: [2, 6, 15]`（通过 PUSH_SEND_BACKOFF 传入）。

| 类别       | 项数 | 建议优先级 |
|------------|------|------------|
| 设计缺陷   | 8    | 高：failure_stats/runtime_state 写入失败路径；中：send 退避、dedupe 清理、cooldown 类型、market 占位 |
| 优化空间   | 8    | 中：路径解析、历史清理、归档可移植性；低：日志结构化、replay target_date 语义、schema 校验 |

**本轮优化已全部完成：** 路径解析（绝对/相对、sync-cron 写绝对路径）、run-task 单次 provider 调用、cleanup.sh（dedupe + runs 清理）、cooldown_until 文档约定为 epoch 秒、受信输入与 market 占位说明、归档 content_path 存相对路径、replay 语义与退出码表、PUSH_LOG_FORMAT=json、validate-config schema 说明。详见 OPERATIONS / TROUBLESHOOTING / DATA_MODEL / RELEASE / SKILL。
