# Push Orchestrator 发布与限制

## 版本说明

- 首版为产品化完整实现：配置驱动、provider 架构、SQLite 主状态、去重、replay、healthcheck、归档、内容类型扩展机制。
- 不兼容旧 cron/旧 dedupe 文件/旧 Markdown 扫描逻辑；无迁移包装层。

## 已知限制

- **单实例**：按单机单实例设计，不支持多实例共享同一 SQLite。
- **market 真值**：`market-price.sh` / `market-news.sh` 为占位实现，需接入真实数据源方可作为唯一真值/摘要来源。
- **send 接口**：发送层假定 sendCommand 接受 channel、target，且 stdout 可解析出 message_id；若 OpenClaw 接口不同，需在 send.sh 或外层适配。
- **cron 同步**：sync-cron.sh 依赖 crontab 与 `# push-orchestrator begin/end` 块；若使用其他调度器需自行维护调用 run-task.sh。

## 回滚方法

- 配置与 tasks 为文件，回滚即用旧文件覆盖并重新 sync-cron（若用 cron）。
- DB：若有备份，可替换 state/push.db；否则只能保留当前状态，历史 runs/dedupe 会丢失。
- 脚本：用版本控制回退 scripts/ 与 config/ 后重新执行 validate-config 与必要时的 init-db。

## 扩展建议

- 新增内容类型：仅新增 content handler 与 task 配置，见 OPERATIONS.md。
- 新增 provider：新增 providers/<name>.sh 并在 tasks 中引用。
- 多通道：channels.schema 已预留；发送层可按 channel 选择不同 sendCommand 或适配器（需改 send.sh 或 lib/senders.sh）。
