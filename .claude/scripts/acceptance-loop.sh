#!/bin/bash
# acceptance-loop.sh
# Step 5 验收闭环：AC提取 → 引擎感知跳过 → 逐条验证 → 失败分级修复 → 收敛循环 → 报告生成
# 遵循 feature-develop-loop.sh 的 bash 编排模式
#
# 用法: bash .claude/scripts/acceptance-loop.sh <version_id> <feature_name> [max_rounds]
# 示例: bash .claude/scripts/acceptance-loop.sh v0.0.3 cooking-system
#       bash .claude/scripts/acceptance-loop.sh v0.0.3 cooking-system 3
#
# 前置条件:
#   - claude CLI 可用
#   - engine-result.md 已生成（auto-work 或 dev-workflow 执行完成后）
#   - idea.md 含 ## 确认方案 > ### 验收标准

set -euo pipefail

# ══════════════════════════════════════
# 参数解析
# ══════════════════════════════════════

VERSION_ID="${1:?用法: $0 <version_id> <feature_name> [max_rounds]}"
FEATURE_NAME="${2:?用法: $0 <version_id> <feature_name> [max_rounds]}"
MAX_ROUNDS="${3:-5}"

FEATURE_DIR="docs/version/${VERSION_ID}/${FEATURE_NAME}"
IDEA_FILE="${FEATURE_DIR}/idea.md"
ENGINE_RESULT="${FEATURE_DIR}/engine-result.md"
AC_JSON="${FEATURE_DIR}/acceptance-criteria.json"
AC_HISTORY="${FEATURE_DIR}/acceptance-history.tsv"
BUG_MAP="${FEATURE_DIR}/acceptance-bug-map.md"
REPORT_FILE="${FEATURE_DIR}/acceptance-report.md"

# 校验
if [ ! -f "$IDEA_FILE" ]; then
    echo "ERROR: ${IDEA_FILE} not found"
    exit 1
fi

if ! grep -q '### 验收标准' "$IDEA_FILE" 2>/dev/null; then
    echo "ERROR: ${IDEA_FILE} 中未找到 '### 验收标准' 章节"
    exit 1
fi

echo "══════════════════════════════════════"
echo "  Acceptance Loop 验收闭环"
echo "  功能: ${VERSION_ID}/${FEATURE_NAME}"
echo "  最大轮次: ${MAX_ROUNDS}"
echo "══════════════════════════════════════"

# ══════════════════════════════════════
# 指标采集（复用 AUTO_WORK_METRICS_FILE）
# ══════════════════════════════════════

run_claude_ac() {
    local desc="$1"
    shift
    local prompt="$1"
    shift
    local extra_args=("$@")

    local tmp_json
    tmp_json=$(mktemp)

    claude -p "$prompt" --output-format json "${extra_args[@]}" > "$tmp_json" 2>/dev/null
    local exit_code=$?

    if [ -f "$tmp_json" ] && [ -s "$tmp_json" ]; then
        local result_text
        result_text=$(cat "$tmp_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',''))" 2>/dev/null || echo "")

        # 写入共享指标文件
        if [ -n "${AUTO_WORK_METRICS_FILE:-}" ]; then
            python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    m = {
        'input_tokens': d.get('usage',{}).get('input_tokens',0),
        'output_tokens': d.get('usage',{}).get('output_tokens',0),
        'cache_read': d.get('usage',{}).get('cache_read_input_tokens',0),
        'cache_write': d.get('usage',{}).get('cache_creation_input_tokens',0),
        'cost': d.get('total_cost_usd',0),
        'duration_ms': d.get('duration_api_ms',0) or d.get('duration_ms',0),
        'desc': sys.argv[2]
    }
    with open(sys.argv[3], 'a') as f:
        f.write(json.dumps(m) + '\n')
except: pass
" "$tmp_json" "$desc" "$AUTO_WORK_METRICS_FILE" 2>/dev/null || true
        fi

        echo "$result_text"
    else
        cat "$tmp_json" 2>/dev/null || true
    fi

    rm -f "$tmp_json"
    return $exit_code
}

# ══════════════════════════════════════
# 阶段 5.0 + 5.1：读取引擎结果 & 提取 AC 清单
# ══════════════════════════════════════

echo ""
echo "── 5.0 读取引擎执行概要 ──"

ENGINE_TYPE="unknown"
ENGINE_COMPILE="unknown"
ENGINE_RUNTIME="unknown"

if [ -f "$ENGINE_RESULT" ]; then
    ENGINE_TYPE=$(grep '引擎:' "$ENGINE_RESULT" 2>/dev/null | sed 's/.*引擎: //' | tr -d '[:space:]' || echo "unknown")
    ENGINE_COMPILE=$(grep '编译状态:' "$ENGINE_RESULT" 2>/dev/null | sed 's/.*编译状态: //' | tr -d '[:space:]' || echo "unknown")
    ENGINE_RUNTIME=$(grep '运行时验证:' "$ENGINE_RESULT" 2>/dev/null | sed 's/.*运行时验证: //' || echo "unknown")
    echo "引擎: ${ENGINE_TYPE}, 编译: ${ENGINE_COMPILE}, 运行时: ${ENGINE_RUNTIME}"
else
    echo "WARNING: ${ENGINE_RESULT} 不存在，所有验证将完整执行"
fi

echo ""
echo "── 5.1 提取验收标准 ──"

if [ -f "$AC_JSON" ]; then
    echo "验收标准已提取，跳过（${AC_JSON}）"
else
    # 提取 ### 验收标准 到 ### 或 ## 之前的内容
    AC_RAW=$(sed -n '/### 验收标准/,/^##\|^###/{/^##\|^###/!p}' "$IDEA_FILE" 2>/dev/null | head -50)

    if [ -z "$AC_RAW" ]; then
        echo "ERROR: 无法从 idea.md 提取验收标准内容"
        exit 1
    fi

    AC_EXTRACT_PROMPT="将以下验收标准列表转换为 JSON 数组。每条标准一个对象。

验收标准原文：
${AC_RAW}

输出格式（纯 JSON，无 markdown 代码块）：
[
  {\"id\": \"AC-01\", \"text\": \"标准描述\", \"type\": \"compile|code_exist|runtime|data|protocol\"}
]

type 判定规则：
- compile: 涉及编译通过、构建成功
- code_exist: 涉及新增文件/接口/协议消息存在性
- runtime: 涉及客户端视觉/交互/UI/动画/运行时行为
- data: 涉及配置表/持久化/数据正确性
- protocol: 涉及跨端通信/协议消息字段一致性

只输出 JSON，不要其他文字。"

    AC_RESULT=$(run_claude_ac "AC提取" "$AC_EXTRACT_PROMPT" --allowedTools "Read" --max-turns 3)

    # 提取 JSON（可能包含在 markdown 代码块中）
    echo "$AC_RESULT" | python3 -c "
import sys, json, re
text = sys.stdin.read()
# 尝试直接解析
try:
    data = json.loads(text)
    print(json.dumps(data, ensure_ascii=False, indent=2))
    sys.exit(0)
except: pass
# 尝试从 markdown 代码块提取
match = re.search(r'\`\`\`(?:json)?\s*\n(.*?)\n\`\`\`', text, re.DOTALL)
if match:
    try:
        data = json.loads(match.group(1))
        print(json.dumps(data, ensure_ascii=False, indent=2))
        sys.exit(0)
    except: pass
# 尝试找第一个 [ 到最后一个 ]
match = re.search(r'\[.*\]', text, re.DOTALL)
if match:
    try:
        data = json.loads(match.group(0))
        print(json.dumps(data, ensure_ascii=False, indent=2))
        sys.exit(0)
    except: pass
print('[]')
sys.exit(1)
" > "$AC_JSON" 2>/dev/null

    AC_COUNT=$(python3 -c "import json; print(len(json.load(open('$AC_JSON'))))" 2>/dev/null || echo "0")

    if [ "$AC_COUNT" -eq 0 ]; then
        echo "ERROR: AC 提取失败，无有效条目"
        exit 1
    fi

    echo "提取 ${AC_COUNT} 条验收标准 → ${AC_JSON}"
fi

# ══════════════════════════════════════
# 阶段 5.2：引擎感知跳过策略
# ══════════════════════════════════════

echo ""
echo "── 5.2 应用引擎感知跳过策略 ──"

# 生成跳过标记文件
SKIP_FILE="${FEATURE_DIR}/acceptance-skip.json"
python3 -c "
import json, sys

ac = json.load(open('${AC_JSON}'))
engine_compile = '${ENGINE_COMPILE}'
engine_runtime = '${ENGINE_RUNTIME}'.strip()

for item in ac:
    item['skip'] = False
    item['skip_reason'] = ''

    # 编译类：引擎已 PASS 则跳过
    if item['type'] == 'compile' and engine_compile == 'PASS':
        item['skip'] = True
        item['skip_reason'] = 'PASS(inherited from engine)'

    # 运行时类：引擎 PASS 则继承，SKIPPED 则完整执行
    if item['type'] == 'runtime':
        if 'PASS' in engine_runtime and 'SKIPPED' not in engine_runtime:
            item['skip'] = True
            item['skip_reason'] = 'PASS(inherited from engine runtime)'

json.dump(ac, open('${SKIP_FILE}', 'w'), ensure_ascii=False, indent=2)

skip_count = sum(1 for x in ac if x['skip'])
exec_count = len(ac) - skip_count
print(f'跳过 {skip_count} 条, 执行 {exec_count} 条')
" 2>/dev/null || echo "WARNING: 跳过策略生成失败，将完整执行所有 AC"

# 如果 skip 文件生成失败，用原始 AC 文件
if [ ! -f "$SKIP_FILE" ]; then
    cp "$AC_JSON" "$SKIP_FILE"
fi

# ══════════════════════════════════════
# 初始化历史追踪
# ══════════════════════════════════════

if [ ! -f "$AC_HISTORY" ]; then
    echo -e "ac_id\tround\tstatus\tevidence\tfail_streak" > "$AC_HISTORY"
fi

# ══════════════════════════════════════
# 阶段 5.3-5.4：验收 + 修复 循环
# ══════════════════════════════════════

for AC_ROUND in $(seq 1 "$MAX_ROUNDS"); do
    echo ""
    echo "══════════════════════════════════════"
    echo "  验收轮次 ${AC_ROUND} / ${MAX_ROUNDS}"
    echo "══════════════════════════════════════"

    # ── 5.3 执行验收 ──
    echo "[Round $AC_ROUND] 执行验收..."

    VERIFY_PROMPT="你是验收测试执行者。逐条验证以下验收标准。

验收标准（JSON）：
$(cat "$SKIP_FILE")

功能方案：读取 ${IDEA_FILE} 的 ## 确认方案 章节了解功能设计。

验证规则：
- skip=true 的条目直接标记为 PASS，使用 skip_reason 作为 evidence
- 对每条非 skip 的条目，按 type 执行对应验证：
  - compile: 服务端执行 cd P1GoServer && make build；客户端通过 python3 scripts/mcp_call.py console-get-logs '{\"logType\":\"Error\",\"count\":20}' 检查编译错误
  - code_exist: grep/glob 搜索关键符号（函数名、消息类型、文件路径），确认存在
  - runtime: 通过 Unity MCP 操作验证（Play 模式 → 登录 → 执行操作 → 截图 → 检查日志）
  - data: 检查配置表内容（grep 或 Excel MCP）、检查 bin/config 生成产物
  - protocol: 对比 old_proto/ 定义与双端实现的消息字段
- 验收只做判定，不做修复

输出格式（纯 JSON，无 markdown 代码块）：
[
  {\"id\": \"AC-01\", \"status\": \"PASS\", \"evidence\": \"make build 退出码 0\", \"files_involved\": []},
  {\"id\": \"AC-02\", \"status\": \"FAIL\", \"evidence\": \"函数 Foo.Bar() 未找到\", \"files_involved\": [\"path/to/file.go\"]}
]

只输出 JSON 结果。"

    VERIFY_RESULT=$(run_claude_ac "验收执行 R${AC_ROUND}" "$VERIFY_PROMPT" --allowedTools "Read,Bash,Grep,Glob,ToolSearch" --max-turns 30)

    # 解析验证结果
    RESULT_FILE="${FEATURE_DIR}/acceptance-result-r${AC_ROUND}.json"
    echo "$VERIFY_RESULT" | python3 -c "
import sys, json, re
text = sys.stdin.read()
try:
    data = json.loads(text)
except:
    match = re.search(r'\[.*\]', text, re.DOTALL)
    if match:
        try: data = json.loads(match.group(0))
        except: data = []
    else:
        data = []
json.dump(data, open(sys.argv[1], 'w'), ensure_ascii=False, indent=2)
" "$RESULT_FILE" 2>/dev/null

    # 统计 PASS/FAIL
    PASS_COUNT=$(python3 -c "import json; d=json.load(open('$RESULT_FILE')); print(sum(1 for x in d if x.get('status')=='PASS'))" 2>/dev/null || echo "0")
    FAIL_COUNT=$(python3 -c "import json; d=json.load(open('$RESULT_FILE')); print(sum(1 for x in d if x.get('status')=='FAIL'))" 2>/dev/null || echo "0")
    TOTAL_COUNT=$(python3 -c "import json; print(len(json.load(open('$RESULT_FILE'))))" 2>/dev/null || echo "0")

    echo "验收结果: PASS=${PASS_COUNT}, FAIL=${FAIL_COUNT}, 总计=${TOTAL_COUNT}"

    # 更新历史追踪
    python3 -c "
import json
results = json.load(open('$RESULT_FILE'))
with open('$AC_HISTORY', 'a') as f:
    for r in results:
        # 读取上轮 fail_streak
        streak = 0
        try:
            with open('$AC_HISTORY') as h:
                for line in h:
                    parts = line.strip().split('\t')
                    if len(parts) >= 5 and parts[0] == r['id']:
                        streak = int(parts[4]) if r.get('status') == 'FAIL' else 0
        except: pass
        if r.get('status') == 'FAIL':
            streak += 1
        f.write(f\"{r['id']}\t${AC_ROUND}\t{r.get('status','UNKNOWN')}\t{r.get('evidence','')[:200]}\t{streak}\n\")
" 2>/dev/null || true

    # ── 全部 PASS → 跳到报告生成 ──
    if [ "$FAIL_COUNT" -eq 0 ]; then
        echo "ALL PASS: 所有验收标准通过！"
        break
    fi

    # ── 5.4 失败分级与修复 ──
    echo "[Round $AC_ROUND] 失败分级与修复..."

    # 分级：TRIVIAL vs COMPLEX
    python3 -c "
import json

results = json.load(open('$RESULT_FILE'))
history_streaks = {}
try:
    with open('$AC_HISTORY') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 5:
                history_streaks[parts[0]] = int(parts[4])
except: pass

trivial = []
complex_items = []

for r in results:
    if r.get('status') != 'FAIL':
        continue
    streak = history_streaks.get(r['id'], 0)
    files_count = len(r.get('files_involved', []))
    rtype = r.get('type', '')

    # TRIVIAL 条件：首次失败 + ≤3文件 + 代码存在性/数据类
    is_trivial = (
        streak <= 1
        and files_count <= 3
        and rtype in ('code_exist', 'data')
    )

    if is_trivial:
        trivial.append(r)
    else:
        complex_items.append(r)

print(f'TRIVIAL: {len(trivial)}, COMPLEX: {len(complex_items)}')
json.dump({'trivial': trivial, 'complex': complex_items}, open('${FEATURE_DIR}/acceptance-classified-r${AC_ROUND}.json', 'w'), ensure_ascii=False, indent=2)
" 2>/dev/null

    TRIVIAL_COUNT=$(python3 -c "import json; d=json.load(open('${FEATURE_DIR}/acceptance-classified-r${AC_ROUND}.json')); print(len(d['trivial']))" 2>/dev/null || echo "0")
    COMPLEX_COUNT=$(python3 -c "import json; d=json.load(open('${FEATURE_DIR}/acceptance-classified-r${AC_ROUND}.json')); print(len(d['complex']))" 2>/dev/null || echo "0")

    echo "分级: TRIVIAL=${TRIVIAL_COUNT}, COMPLEX=${COMPLEX_COUNT}"

    # ── 5.4.0 TRIVIAL 内联修复 ──
    if [ "$TRIVIAL_COUNT" -gt 0 ]; then
        echo "[Round $AC_ROUND] TRIVIAL 内联修复..."

        TRIVIAL_ITEMS=$(python3 -c "
import json
d = json.load(open('${FEATURE_DIR}/acceptance-classified-r${AC_ROUND}.json'))
for t in d['trivial']:
    print(f\"- [{t['id']}] {t['evidence']} (files: {', '.join(t.get('files_involved', []))})\")
" 2>/dev/null)

        TRIVIAL_FIX_PROMPT="以下验收项失败，请快速修复：

${TRIVIAL_ITEMS}

功能方案参考：${IDEA_FILE}

修复规则：
- 最多读 200 行代码、改 3 个文件
- 只修复列出的问题，不做其他改动
- 修复后用 grep 验证修复生效
- 如果超出能力范围，不要强行修复，直接说明原因"

        run_claude_ac "TRIVIAL修复 R${AC_ROUND}" "$TRIVIAL_FIX_PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob" --max-turns 15 | tail -10
    fi

    # ── 5.4.1-5.4.2 COMPLEX 修复（通过 dev-debug 独立进程） ──
    if [ "$COMPLEX_COUNT" -gt 0 ]; then
        echo "[Round $AC_ROUND] COMPLEX 修复（启动 dev-debug 独立进程）..."

        # 生成/更新 acceptance-bug-map.md
        python3 -c "
import json

classified = json.load(open('${FEATURE_DIR}/acceptance-classified-r${AC_ROUND}.json'))
complex_items = classified['complex']

lines = ['# 验收失败 → Bug 映射', '', '| AC 编号 | 描述 | 文件 | 状态 |', '|---------|------|------|------|']
for c in complex_items:
    files = ', '.join(c.get('files_involved', []))
    lines.append(f\"| {c['id']} | {c['evidence'][:80]} | {files} | OPEN |\")

lines.append('')
lines.append(f'功能方案：${IDEA_FILE}')
lines.append(f'Bug 目录：docs/bugs/${VERSION_ID}/${FEATURE_NAME}/')

with open('${BUG_MAP}', 'w') as f:
    f.write('\n'.join(lines))
" 2>/dev/null

        COMPLEX_FIX_PROMPT="读取 ${BUG_MAP} 获取待修复的验收失败项。

上下文：
- 功能方案：${IDEA_FILE}（含 ## 确认方案）
- 开发日志：${FEATURE_DIR}/develop-log.md（如存在）

要求：
1. 对每个 OPEN 状态的失败项，自主诊断根因并修复
2. 每修复一个后验证编译通过（Go: cd P1GoServer && make build，Unity: python3 scripts/mcp_call.py console-get-logs）
3. 运行时类问题必须通过 MCP 操作验证（Play → 操作 → 截图）
4. 修复完成后更新 ${BUG_MAP} 中的状态为 FIXED 或 UNFIXED"

        run_claude_ac "COMPLEX修复 R${AC_ROUND}" "$COMPLEX_FIX_PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" --max-turns 60 | tail -15
    fi

    # ── 5.4.3 检查是否有连续 FAIL ≥3 的 AC 项 ──
    python3 -c "
import json
try:
    history = {}
    with open('$AC_HISTORY') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 5 and parts[0].startswith('AC-'):
                history[parts[0]] = int(parts[4])
    for ac_id, streak in history.items():
        if streak >= 3:
            print(f'⚠️  {ac_id} 连续 FAIL {streak} 次（验收标准疑似歧义）')
except: pass
" 2>/dev/null

done

# ══════════════════════════════════════
# 阶段 5.5：生成验收报告
# ══════════════════════════════════════

echo ""
echo "── 5.5 生成验收报告 ──"

# 找到最后一轮的结果
LAST_ROUND=$AC_ROUND
LAST_RESULT="${FEATURE_DIR}/acceptance-result-r${LAST_ROUND}.json"

# 如果 TRIVIAL/COMPLEX 修复后没有重新验证，用最后一轮结果
# 对于修复后的项，状态可能已改变，需要重新验证
if [ "$FAIL_COUNT" -gt 0 ] && [ "$LAST_ROUND" -lt "$MAX_ROUNDS" ]; then
    # 修复后执行一次快速重验（只验 FAIL 项）
    echo "修复后快速重验 FAIL 项..."
    RVERIFY_PROMPT="只重新验证以下之前失败的验收项（已执行修复）：

$(python3 -c "
import json
r = json.load(open('$LAST_RESULT'))
for x in r:
    if x.get('status') == 'FAIL':
        print(f\"- {x['id']}: {x['text'] if 'text' in x else x.get('evidence','')}\")
" 2>/dev/null)

验证方法与之前相同。只输出这些项的结果 JSON。"

    RVERIFY_RESULT=$(run_claude_ac "重验FAIL项" "$RVERIFY_PROMPT" --allowedTools "Read,Bash,Grep,Glob,ToolSearch" --max-turns 20)

    # 合并重验结果到最终结果
    python3 -c "
import json, re, sys
# 读取原始结果
original = json.load(open('$LAST_RESULT'))
# 解析重验结果
text = sys.stdin.read()
try:
    recheck = json.loads(text)
except:
    match = re.search(r'\[.*\]', text, re.DOTALL)
    recheck = json.loads(match.group(0)) if match else []

# 合并：用重验结果覆盖
recheck_map = {r['id']: r for r in recheck if 'id' in r}
for item in original:
    if item['id'] in recheck_map:
        item['status'] = recheck_map[item['id']].get('status', item['status'])
        item['evidence'] = recheck_map[item['id']].get('evidence', item['evidence'])

json.dump(original, open('${FEATURE_DIR}/acceptance-result-final.json', 'w'), ensure_ascii=False, indent=2)
" <<< "$RVERIFY_RESULT" 2>/dev/null

    LAST_RESULT="${FEATURE_DIR}/acceptance-result-final.json"
fi

# 生成报告
python3 -c "
import json, sys
from datetime import datetime

results = json.load(open('$LAST_RESULT'))
pass_count = sum(1 for r in results if r.get('status') == 'PASS')
fail_count = sum(1 for r in results if r.get('status') == 'FAIL')
total = len(results)

# 检查连续 FAIL ≥ MAX_ROUNDS 的标记为 UNRESOLVED
history_streaks = {}
try:
    with open('$AC_HISTORY') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 5 and parts[0].startswith('AC-'):
                history_streaks[parts[0]] = int(parts[4])
except: pass

unresolved_count = 0
for r in results:
    if r.get('status') == 'FAIL' and history_streaks.get(r['id'], 0) >= ${MAX_ROUNDS}:
        r['status'] = 'UNRESOLVED'
        unresolved_count += 1

# 重新统计
pass_count = sum(1 for r in results if r.get('status') == 'PASS')
fail_count = sum(1 for r in results if r.get('status') == 'FAIL')

lines = []
lines.append('═══════════════════════════════════════════════')
lines.append('  验收报告：${FEATURE_NAME}')
lines.append('  版本：${VERSION_ID}')
lines.append('  引擎：${ENGINE_TYPE}')
lines.append('  验收轮次：${LAST_ROUND}')
lines.append('═══════════════════════════════════════════════')
lines.append('')
lines.append('## 验收标准')
lines.append('')

for r in results:
    status = r.get('status', 'UNKNOWN')
    evidence = r.get('evidence', '')
    line = f'[{status}] {r[\"id\"]}: {evidence[:120]}'
    lines.append(line)

lines.append('')
lines.append('## 结论')
lines.append('')
lines.append(f'通过率: {pass_count}/{total}')

if fail_count == 0 and unresolved_count == 0:
    lines.append('结论: 全部通过')
elif unresolved_count > 0:
    lines.append(f'结论: 有 {unresolved_count} 项 UNRESOLVED（{MAX_ROUNDS} 轮修复未收敛）')
else:
    lines.append(f'结论: 部分通过，遗留 {fail_count} 项 FAIL')

# Bug 追踪
try:
    with open('$BUG_MAP') as f:
        bug_content = f.read()
    if 'OPEN' in bug_content or 'FIXED' in bug_content:
        lines.append('')
        lines.append('## Bug 追踪')
        lines.append('')
        lines.append(f'Bug 映射表: ${BUG_MAP}')
except: pass

with open('$REPORT_FILE', 'w') as f:
    f.write('\n'.join(lines))

print(f'验收报告已生成: $REPORT_FILE')
print(f'通过率: {pass_count}/{total}')
if fail_count > 0 or unresolved_count > 0:
    print(f'FAIL: {fail_count}, UNRESOLVED: {unresolved_count}')
" 2>/dev/null

# ══════════════════════════════════════
# P1-2 接口：验收失败 → 规则反馈（预留）
# ══════════════════════════════════════

FINAL_FAIL=$(python3 -c "import json; d=json.load(open('$LAST_RESULT')); print(sum(1 for x in d if x.get('status') in ('FAIL','UNRESOLVED')))" 2>/dev/null || echo "0")

if [ "$FINAL_FAIL" -gt 0 ]; then
    echo ""
    echo "── 验收失败规则反馈 ──"

    FAIL_ITEMS=$(python3 -c "
import json
d = json.load(open('$LAST_RESULT'))
for x in d:
    if x.get('status') in ('FAIL', 'UNRESOLVED'):
        print(f\"- [{x['id']}] {x.get('evidence','')[:100]}\")
" 2>/dev/null)

    EXISTING_RULES=$(ls .claude/rules/auto-work-lesson-*.md 2>/dev/null | while read f; do echo "- $(basename "$f")"; done)

    META_PROMPT="你是工作流优化专家。以下验收项在多轮修复后仍然失败：

${FAIL_ITEMS}

功能方案：${IDEA_FILE}

已有规则：
${EXISTING_RULES:-无}

分析这些失败的根因模式。如果发现可以在编码阶段预防的系统性模式（如命名遗漏、注册遗漏、配置遗漏等），
生成一条新规则写入 .claude/rules/auto-work-lesson-{下一个编号}.md（参考已有 lesson 的格式：触发条件 + 规则内容 + 来源）。

如果失败仅是个案性的实现遗漏（非系统性），输出 NO_NEW_RULES。"

    run_claude_ac "验收Meta-Review" "$META_PROMPT" --allowedTools "Read,Write,Grep,Glob" --max-turns 10 | tail -10
fi

# ══════════════════════════════════════
# 总结
# ══════════════════════════════════════

echo ""
echo "══════════════════════════════════════"
echo "  Acceptance Loop 完成"
echo "══════════════════════════════════════"
echo "  轮次: ${AC_ROUND}"
echo "  报告: ${REPORT_FILE}"
if [ -f "$BUG_MAP" ]; then
    echo "  Bug映射: ${BUG_MAP}"
fi
echo "══════════════════════════════════════"
