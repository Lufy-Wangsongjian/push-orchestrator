# TOOLS.md - OpenClaw Integration

This skill is designed to be used with **OpenClaw** as the orchestration layer for scheduled pushes (reminders, content, market briefs, ops checks, tests).

It documents how to wire `push-orchestrator` into your OpenClaw workspace.

---

## 1. Installation in OpenClaw

### 1.1 Install via skills CLI (recommended)

From your OpenClaw workspace (e.g. `/root/.openclaw/workspace-pusher`):

```bash
cd /root/.openclaw/workspace-pusher
npx skills add Lufy-Wangsongjian/push-orchestrator@push-orchestrator -y
```

This will create a symlink at:

- `<workspace>/skills/push-orchestrator` → actual files under `.agents/skills/push-orchestrator`

Scripts in this repo assume the skill root is that directory (either real or symlink).

### 1.2 Manual install (alternative)

Clone this repo somewhere on disk, then copy it into your workspace:

```bash
cd /root/.openclaw
git clone https://github.com/Lufy-Wangsongjian/push-orchestrator.git
cp -a push-orchestrator /root/.openclaw/workspace-pusher/skills/
```

Now the skill root is:

```bash
/root/.openclaw/workspace-pusher/skills/push-orchestrator
```

---

## 2. Workspace + Telegram binding

In OpenClaw, agents are defined in `openclaw.json`. For example, the `pusher` agent might look like:

```jsonc
{
  "id": "pusher",
  "workspace": "/root/.openclaw/workspace-pusher",
  "agentDir": "/root/.openclaw/agents/pusher/agent"
}
```

Channel bindings connect that agent to a Telegram account:

```jsonc
"bindings": [
  {
    "agentId": "pusher",
    "match": {
      "channel": "telegram",
      "accountId": "pusher"
    }
  }
]
```

The OpenClaw integration scripts in this repo use:

- `PUSH_WORKSPACE` (or `OPENCLAW_WORKSPACE`) to know **which agent workspace** they belong to
- `openclaw.json` to resolve the **Telegram accountId** for that agent

If you only need generic CLI usage (not OpenClaw), you can ignore this and call `run-task.sh` directly.

---

## 3. Recommended wiring in an OpenClaw workspace

Inside a specific OpenClaw workspace (e.g. `workspace-pusher`):

1. **Skill root**: ensure you have
   - `skills/push-orchestrator` (real dir or symlink to `.agents/skills/push-orchestrator`)
2. **Cron / scripts**: use small shell wrappers in `workspace-*/scripts/` to call:
   - `skills/push-orchestrator/scripts/run-task.sh` for scheduled tasks
   - `skills/push-orchestrator/scripts/send-now.sh` for "send one now" commands from bots / agents
3. **Environment**:
   - Set `PUSH_SKILL_ROOT` or run from the skill root when debugging
   - Set `OPENCLAW_WORKSPACE` or let the scripts derive it from the skill root path

Example (cron line inside the workspace machine):

```cron
0 8 * * * cd /root/.openclaw/workspace-pusher/skills/push-orchestrator \
  && ./scripts/run-task.sh --tasks config/tasks.daily.json --task remind-morning >> /tmp/push-orchestrator.log 2>&1
```

---

## 4. Files you might want to customize per workspace

- `config/default.json`
  - `timezone` (default `Asia/Shanghai`)
  - `sendCommand` (e.g. `openclaw message send` or a wrapper script)
  - `defaultChannel`, `defaultTarget`
- `config/tasks.*.json`
  - Task ids, crons, channels and targets for your own reminder / content / market flows

Keep these as workspace-specific (not shared across all agents) if different workspaces need different schedules.

---

## 5. Safety notes

- This skill assumes **single-node, single-instance** SQLite usage; do not point multiple OpenClaw instances at the same `state/push.db` unless you know what you're doing.
- When wiring into OpenClaw cron, always test new tasks with `--dry-run` first:

```bash
./scripts/run-task.sh --tasks config/tasks.daily.json --task remind-morning --dry-run
```

