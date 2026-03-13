#!/usr/bin/env bash
set -e

task_json=$(cat)
kind="book"
title=$(echo "$task_json" | jq -r '.source_config.title // "📚 每日书籍推荐"')
topic_key="book:$(date '+%Y-%m-%d')"

content=$(python3 - << 'PY'
import json, os, re, sqlite3, hashlib, datetime
skill_root='/root/.openclaw/workspace-pusher/.agents/skills/push-orchestrator'
db=f'{skill_root}/state/push.db'
pool='/root/.openclaw/workspace-pusher/projects/data/pools/books.json'
if not os.path.exists(pool):
    print('今日书籍推荐：资料源不可用，请稍后重试。'); raise SystemExit
arr=json.load(open(pool,encoding='utf-8'))

seen=set()
if os.path.exists(db):
    conn=sqlite3.connect(db)
    rows=conn.execute("select title from dedupe_records where content_kind='book' and title is not null").fetchall()
    conn.close()
    for r in rows:
        if r and r[0]: seen.add(r[0].strip())

cands=[]
for x in arr:
    raw=(x.get('title') or '').strip()
    clean=re.sub(r'\s*#\d+$','',raw)
    core=clean.split('(')[0].replace('《','').replace('》','').strip()
    if core and core not in seen and clean not in seen and f"《{core}》" not in seen:
        cands.append((clean, x))

if not cands:
    print('今日书籍推荐：数据库去重后无可用候选，请扩充资料源。'); raise SystemExit

seed=str(datetime.date.today())
name,obj=cands[int(hashlib.sha256(seed.encode()).hexdigest(),16)%len(cands)]
a=obj.get('author','Unknown'); y=obj.get('year',''); c=obj.get('category',''); s=obj.get('summary','')

print(f"""📚 今日书籍推荐（数据库去重）
{name}
作者：{a}｜年份：{y}｜主题：{c}

为什么今天值得读：
{s}

深度阅读路径：
1) 先看目录与前言，建立全书地图（10分钟）
2) 记录3条最反直觉观点，并写一句“为什么它可能是对的”
3) 选1条做48小时实验，明天复盘结果

延伸问题：
- 这本书最可能纠正你哪种思维偏差？
- 如果只能保留一个方法论，你会留哪一个，为什么？
""")
PY
)

source_summary="book_db_dedupe"
jq -n \
  --arg title "$title" \
  --arg topic_key "$topic_key" \
  --arg content "$content" \
  --arg source_summary "$source_summary" \
  --arg content_kind "$kind" \
  '{title:$title, topic_key:$topic_key, content:$content, source_summary:$source_summary, content_kind:$content_kind}'
