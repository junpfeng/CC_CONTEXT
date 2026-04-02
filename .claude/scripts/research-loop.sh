#!/bin/bash
# research-loop.sh
# 自动迭代调研 + Review 循环，每轮启动新 Claude 实例防止上下文污染
#
# 用法: bash .claude/scripts/research-loop.sh <topic> [max_rounds]
# 示例: bash .claude/scripts/research-loop.sh ecs-architecture
#
# 前置条件:
#   - claude CLI 可用
#   - 从项目根目录运行

set -euo pipefail

# ══════════════════════════════════════
# 指标采集
# ══════════════════════════════════════

claude_tracked() {
    local desc="$1"; shift
    local prompt="$1"; shift
    local extra_args=("$@")
    local tmp_json; tmp_json=$(mktemp)

    claude -p "$prompt" --output-format json "${extra_args[@]}" > "$tmp_json" 2>/dev/null
    local exit_code=$?

    if [ -f "$tmp_json" ] && [ -s "$tmp_json" ]; then
        local result_text
        result_text=$(cat "$tmp_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',''))" 2>/dev/null || echo "")

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
# 参数解析
# ══════════════════════════════════════

TOPIC="${1:?用法: $0 <topic> [max_rounds]}"
MAX_ROUNDS="${2:-4}"

RESEARCH_DIR="docs/research/${TOPIC}"
RESULT_FILE="${RESEARCH_DIR}/research-result.md"
REVIEW_FILE="${RESEARCH_DIR}/research-review-report.md"
LOG_FILE="${RESEARCH_DIR}/research-iteration-log.md"

# 确保目录存在
mkdir -p "$RESEARCH_DIR"

echo "══════════════════════════════════════"
echo "  Research 迭代循环"
echo "  主题: ${TOPIC}"
echo "  最大轮次: ${MAX_ROUNDS}"
echo "══════════════════════════════════════"

# ══════════════════════════════════════
# 初始化日志
# ══════════════════════════════════════

cat > "$LOG_FILE" << 'EOF'
# 调研迭代日志

| 轮次 | 操作 | Critical | Important | Nice-to-have | 可靠度 | 状态 |
|------|------|----------|-----------|--------------|--------|------|
EOF

PREV_TOTAL=-1
CRITICAL=0
IMPORTANT=0
NICE=0
RELIABILITY=0
REASON=""

# ══════════════════════════════════════
# 主循环
# ══════════════════════════════════════

for ROUND in $(seq 1 "$MAX_ROUNDS"); do
    echo ""
    echo "══════════════════════════════════════"
    echo "  轮次 ${ROUND} / ${MAX_ROUNDS}"
    echo "══════════════════════════════════════"

    if [ $((ROUND % 2)) -eq 1 ]; then
        # ── 奇数轮: 调研 ──

        if [ "$ROUND" -eq 1 ]; then
            echo "[Round $ROUND] 执行调研..."

            PROMPT="读取 .claude/commands/research/do.md 中的完整工作流程，按照其中的步骤执行。

参数（已解析，直接使用）：
- topic: ${TOPIC}
- 调研目录: ${RESEARCH_DIR}
- 输出文件: ${RESULT_FILE}

自动化模式特殊规则：
1. 参数解析：跳过，直接使用上面的参数
2. 第一步（明确调研范围）：如果 ${RESEARCH_DIR}/idea.md 存在，以其内容为调研需求，跳过 AskUserQuestion。如果不存在，以 topic '${TOPIC}' 作为调研主题描述，自主决定调研深度为'深入对比'
3. 第五步（与用户讨论）：跳过，不要询问用户
4. 完成所有步骤后直接结束，不要中途停下来"

        else
            echo "[Round $ROUND] 修复调研报告（基于上轮 Review）..."

            PROMPT="你的任务是根据 Review 报告修复调研报告。

请读取以下文件：
1. ${REVIEW_FILE} — 上一轮的 Review 报告
2. ${RESULT_FILE} — 当前调研报告
3. 如果 ${RESEARCH_DIR}/research-result/ 子目录存在，也读取其中的所有子文件
4. 如果 ${RESEARCH_DIR}/idea.md 存在，读取以了解原始需求

修复规则：
- 逐个修复 Review 报告中的 Critical 和 Important 问题
- 对于需要补充信息的问题，使用 WebSearch/WebFetch 搜索后补充
- 在修改处添加 <!-- [迭代${ROUND}修复] 原因 --> 注释
- 只修复报告中列出的问题，不要添加额外内容
- Nice-to-have 问题可以顺手修复，但不强制
- 修复完成后，确保报告整体逻辑自洽，新增内容与原内容不矛盾"
        fi

        claude_tracked "调研/修复 Round $ROUND" "$PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" | tail -20
        echo "| $ROUND | 调研/修复 | - | - | - | - | done |" >> "$LOG_FILE"

    else
        # ── 偶数轮: Review 调研报告 ──

        echo "[Round $ROUND] Review 调研报告..."

        PROMPT="读取 .claude/commands/research/review.md 中的完整工作流程，按照其中的步骤执行。

参数（已解析，直接使用）：
- topic: ${TOPIC}
- 调研目录: ${RESEARCH_DIR}

自动化模式特殊规则：
1. 参数解析：跳过，直接使用上面的参数
2. 完成 Review 后，将完整的 Review 报告写入文件 ${REVIEW_FILE}（覆盖之前的报告）
3. 在报告文件的最后一行，必须追加以下格式的元数据（用于脚本自动解析，不要遗漏）：
   <!-- counts: critical=X important=Y nice=Z reliability=R -->
   其中 X/Y/Z 替换为实际问题数量，R 替换为决策可靠度星数（1-5 的整数）
4. 跳过第五步（交互式修复），不要询问用户如何处理，直接结束"

        claude_tracked "调研 Review Round $ROUND" "$PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" | tail -20

        # 解析 Review 结果
        if [ -f "$REVIEW_FILE" ]; then
            COUNTS_LINE=$(grep -o 'counts: critical=[0-9]* important=[0-9]* nice=[0-9]* reliability=[0-9]*' "$REVIEW_FILE" 2>/dev/null | tail -1 || echo "")
            if [ -n "$COUNTS_LINE" ]; then
                CRITICAL=$(echo "$COUNTS_LINE" | sed 's/.*critical=\([0-9]*\).*/\1/')
                IMPORTANT=$(echo "$COUNTS_LINE" | sed 's/.*important=\([0-9]*\).*/\1/')
                NICE=$(echo "$COUNTS_LINE" | sed 's/.*nice=\([0-9]*\).*/\1/')
                RELIABILITY=$(echo "$COUNTS_LINE" | sed 's/.*reliability=\([0-9]*\).*/\1/')
            else
                echo "WARNING: 无法解析 Review 报告中的 counts 元数据"
                echo "报告文件末尾内容:"
                tail -5 "$REVIEW_FILE"
                CRITICAL=999
                IMPORTANT=999
                NICE=0
                RELIABILITY=0
            fi
        else
            echo "WARNING: Review 报告文件未生成: ${REVIEW_FILE}"
            CRITICAL=999
            IMPORTANT=999
            NICE=0
            RELIABILITY=0
        fi

        CURRENT_TOTAL=$((CRITICAL + IMPORTANT))
        echo "| $ROUND | Review | $CRITICAL | $IMPORTANT | $NICE | $RELIABILITY | done |" >> "$LOG_FILE"
        echo "Review 结果: Critical=$CRITICAL, Important=$IMPORTANT, Nice=$NICE, 可靠度=$RELIABILITY/5"

        # ── 收敛判断 ──

        # 条件1: 质量达标
        if [ "$CRITICAL" -eq 0 ] && [ "$IMPORTANT" -le 1 ]; then
            REASON="质量达标"
            echo "PASS: $REASON (Critical=0, Important<=1)"
            break
        fi

        # 条件2: 可靠度达标
        if [ "$RELIABILITY" -ge 4 ]; then
            REASON="可靠度达标"
            echo "PASS: $REASON (可靠度=${RELIABILITY}/5 >= 4)"
            break
        fi

        # 条件3: 稳定不变（陷入循环）
        if [ "$PREV_TOTAL" -ge 0 ] && [ "$CURRENT_TOTAL" -eq "$PREV_TOTAL" ]; then
            REASON="稳定不变"
            echo "WARN: $REASON (问题总数未减少: $CURRENT_TOTAL)"
            break
        fi

        PREV_TOTAL=$CURRENT_TOTAL
    fi
done

# 如果循环自然结束
if [ -z "$REASON" ]; then
    REASON="达到上限"
fi

# ══════════════════════════════════════
# 写入总结
# ══════════════════════════════════════

cat >> "$LOG_FILE" << EOF

## 总结
- 总轮次：$ROUND
- 终止原因：$REASON
- 最终状态：Critical=$CRITICAL, Important=$IMPORTANT, Nice-to-have=$NICE
- 决策可靠度：$RELIABILITY/5
EOF

echo ""
echo "══════════════════════════════════════"
echo "  调研迭代完成"
echo "══════════════════════════════════════"
echo "  轮次: $ROUND"
echo "  终止原因: $REASON"
echo "  最终质量: Critical=$CRITICAL, Important=$IMPORTANT"
echo "  决策可靠度: $RELIABILITY/5"
echo "  调研报告: $RESULT_FILE"
echo "  迭代日志: $LOG_FILE"
echo "══════════════════════════════════════"
