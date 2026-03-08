# Git 提交说明

当前环境若未安装 **Xcode 命令行工具**，`git` 可能无法使用。安装后再执行下列命令即可完成提交。

## 安装 Xcode 命令行工具（若未安装）

在终端执行：

```bash
xcode-select --install
```

按提示完成安装后，再执行下方命令。

## 提交步骤

```bash
cd /Users/lufy/Documents/Projects/Skills/push-orchestrator

# 初始化仓库（若尚未初始化）
git init

# 添加文件
git add .gitignore SKILL.md config/ scripts/ state/README.md examples/ templates/ docs/ design.md designdesc.md

# 提交
git add -A
git status   # 确认无多余文件（state/push.db 已被 .gitignore 排除）
git commit -m "feat: push-orchestrator skill for OpenClaw

- Config-driven tasks, SQLite state, provider + content dispatcher
- Scripts: init-db, validate-config, run-task, send, sync-cron, replay, healthcheck
- Lib: db, locks, task, logging, time, senders, content
- Providers: reminder, content (dispatcher), market-*, ops, test
- Content handlers: book, musical, startup_idea, coffee, ai_news, poem, custom_prompt
- Docs: OPERATIONS, TROUBLESHOOTING, RELEASE, DATA_MODEL, DESIGN_REVIEW
- Failure path: record failure_stats and runtime_state; send backoff by attempt"
```

## 忽略内容说明

`.gitignore` 已配置忽略：

- `state/push.db`、`state/content_archive/` 等运行时/归档目录
- `config/local.json`、`*.local.json` 等本地覆盖

如需把 `state/push.db` 纳入版本控制（不推荐），可从 `.gitignore` 中移除对应行。
