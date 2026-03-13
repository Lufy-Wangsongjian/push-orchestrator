#!/usr/bin/env bash
set -e

task_json=$(cat)
kind="startup_idea"
title=$(echo "$task_json" | jq -r '.source_config.title // "🚀 每日 AI 创业想法"')
topic_key="startup:$(date '+%Y-%m-%d')"

content=$(python3 - << 'PY'
import os,re,sqlite3,hashlib,datetime,itertools
skill_root='/root/.openclaw/workspace-pusher/.agents/skills/push-orchestrator'
db=f'{skill_root}/state/push.db'

seen=set()
if os.path.exists(db):
    conn=sqlite3.connect(db)
    rows=conn.execute("select title from dedupe_records where content_kind='startup_idea' and title is not null").fetchall()
    conn.close()
    for r in rows:
        if r and r[0]: seen.add(r[0].strip())

verticals=['跨境电商','餐饮连锁','独立诊所','SaaS销售','物流仓配','教育培训','保险经代','律所服务']
workflows=['客服质检','线索分层','报价生成','续费预警','排班优化','现金流预测','合规审查','知识库问答']
angles=['多智能体协作','RAG检索增强','语音交互','工作流自动化','异常检测','A/B策略优化']

ideas=[]
for v,w,a in itertools.product(verticals,workflows,angles):
    name=f"{v}{w}AI Copilot"
    if name in seen: continue
    ideas.append((name,v,w,a))

if not ideas:
    print('今日创业想法：数据库去重后无可用候选，请扩展生成维度。'); raise SystemExit

seed=str(datetime.date.today())
name,v,w,a=ideas[int(hashlib.sha256(seed.encode()).hexdigest(),16)%len(ideas)]

print(f"""🚀 今日 AI 创业想法（数据库去重）
{name}
定位：{v}场景下的{w}，技术路线偏向{a}

核心痛点：
{v}团队在{w}上依赖人工经验，响应慢、质量不稳定、数据无法复用。

产品方案：
- 数据层：接入 CRM/工单/财务/聊天记录，形成统一语义层
- 决策层：AI 给出“建议 + 置信度 + 可解释理由”
- 执行层：一键触发动作（通知、建单、回访、复盘）

MVP 路线（2周）：
1) 先做单场景闭环（只覆盖一个高频流程）
2) 只追一个北极星指标（如处理时长下降%）
3) 用10个真实客户对照验证 ROI

关键风险：
- 数据接入成本高于预期
- 一线团队不信任自动建议

首月指标：
- 激活率、周留存、建议采纳率、人工时长节省
""")
PY
)

source_summary="startup_db_dedupe"
jq -n \
  --arg title "$title" \
  --arg topic_key "$topic_key" \
  --arg content "$content" \
  --arg source_summary "$source_summary" \
  --arg content_kind "$kind" \
  '{title:$title, topic_key:$topic_key, content:$content, source_summary:$source_summary, content_kind:$content_kind}'
