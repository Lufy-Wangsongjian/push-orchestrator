# Push Orchestrator State

此目录由 push-orchestrator 使用，存放运行时状态与归档。

- **push.db**：SQLite 主状态库（任务快照、执行历史、去重记录、运行时状态、归档索引等）。由 `scripts/init-db.sh` 创建。
- **run_history_export/**：运行历史导出目录（可选）。
- **content_archive/**：内容归档目录；当任务配置 `archive_enabled: true` 时，按 `content_kind`/`archive_category` 分子目录存放导出的消息内容。

请勿在未备份的情况下删除 `push.db`；如需重置，可删除后重新执行 `init-db.sh`。
