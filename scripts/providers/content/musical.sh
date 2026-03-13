#!/usr/bin/env bash
set -e

task_json=$(cat)
kind="musical"
title=$(echo "$task_json" | jq -r '.source_config.title // "🎭 每日经典音乐剧推荐"')
topic_key="musical:$(date '+%Y-%m-%d')"

content=$(python3 - << 'PY'
import json, os, re, sqlite3, hashlib, datetime
skill_root='/root/.openclaw/workspace-pusher/.agents/skills/push-orchestrator'
db=f'{skill_root}/state/push.db'
curated='/root/.openclaw/workspace-pusher/projects/data/pools/musicals_curated.json'
pool2='/root/.openclaw/workspace-pusher/projects/data/pools/musicals.json'

seen=set()
if os.path.exists(db):
    conn=sqlite3.connect(db)
    rows=conn.execute("select title from dedupe_records where content_kind='musical' and title is not null").fetchall()
    conn.close()
    for r in rows:
        if r and r[0]:
            seen.add(r[0].strip())

obj=None
kind=''
if os.path.exists(curated):
    arr=json.load(open(curated,encoding='utf-8'))
    for x in arr:
        zh=(x.get('title_zh') or '').strip()
        en=(x.get('title_en') or '').strip()
        full=f"《{zh}》"
        if zh and zh not in seen and en not in seen and full not in seen:
            obj=x; kind='curated'; break

if obj is None and os.path.exists(pool2):
    arr2=json.load(open(pool2,encoding='utf-8'))
    cands=[]
    for x in arr2:
        t=(x.get('title') or '').strip()
        clean=re.sub(r'\s*#\d+$','',t)
        core=clean.split('(')[0].replace('《','').replace('》','').strip()
        if clean and clean not in seen and core not in seen and f"《{core}》" not in seen:
            cands.append(x)
    if cands:
        seed=str(datetime.date.today())
        obj=cands[int(hashlib.sha256(seed.encode()).hexdigest(),16)%len(cands)]
        kind='pool'

if obj is None:
    print('今日音乐剧推荐：数据库去重后无可用候选，请扩充资料源。')
    raise SystemExit

if kind=='curated':
    zh=obj.get('title_zh','未知作品'); en=obj.get('title_en','Unknown'); y=obj.get('year','')
    creator=obj.get('creator','')
    hook=obj.get('hook','')
    analysis='\n'.join([f"{i+1}. {v}" for i,v in enumerate(obj.get('analysis',[])[:3])]) or '暂无'
    songs='\n'.join([f"• {v}" for v in obj.get('songs',[])[:4]]) or '暂无'
    print(f"""🎭 今日音乐剧推荐（数据库去重）
《{zh}》 {en} ({y})
创作者：{creator}

一句话推荐：
{hook}

看点：
{analysis}

先听这几首：
{songs}
""")
else:
    t=obj.get('title','未知作品'); y=obj.get('year','')
    comp=obj.get('composer','')
    desc=obj.get('desc','')
    raw=obj.get('songs') or []
    if isinstance(raw,str):
        items=[s.strip(' •') for s in raw.splitlines() if s.strip()]
    else:
        items=[str(s).strip(' •') for s in raw if str(s).strip()]
    songs='\n'.join([f"• {v}" for v in items[:4]]) or '暂无'
    print(f"""🎭 今日音乐剧推荐（数据库去重）
{t} ({y})
作曲/主创：{comp}

一句话推荐：
{desc}

先听这几首：
{songs}
""")
PY
)

source_summary="musical_db_dedupe"
jq -n \
  --arg title "$title" \
  --arg topic_key "$topic_key" \
  --arg content "$content" \
  --arg source_summary "$source_summary" \
  --arg content_kind "$kind" \
  '{title:$title, topic_key:$topic_key, content:$content, source_summary:$source_summary, content_kind:$content_kind}'
