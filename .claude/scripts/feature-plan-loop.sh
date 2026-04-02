#!/bin/bash
# feature-plan-loop.sh
# 自动迭代 Plan 创建 + Review 循环，每轮启动新 Claude 实例防止上下文污染
#
# 用法: bash .claude/scripts/feature-plan-loop.sh <version_id> <feature_name> [max_rounds]
# 示例: bash .claude/scripts/feature-plan-loop.sh v0.0.2-mvp login-system
#
# 前置条件:
#   - claude CLI 可用
#   - 从项目根目录运行

set -euo pipefail

# ══════════════════════════════════════
# 指标采集（写入 AUTO_WORK_METRICS_FILE 供父进程汇总）
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

VERSION_ID="${1:?用法: $0 <version_id> <feature_name> [max_rounds]}"
FEATURE_NAME="${2:?用法: $0 <version_id> <feature_name> [max_rounds]}"
MAX_ROUNDS="${3:-7}"

FEATURE_DIR="docs/version/${VERSION_ID}/${FEATURE_NAME}"
PLAN_FILE="${FEATURE_DIR}/plan.json"
LOG_FILE="${FEATURE_DIR}/plan-iteration-log.md"
REVIEW_FILE="${FEATURE_DIR}/plan-review-report.md"

# 校验：优先 feature.json，兼容旧的 feature.md
if [ ! -f "${FEATURE_DIR}/feature.json" ] && [ ! -f "${FEATURE_DIR}/feature.md" ]; then
    echo "ERROR: ${FEATURE_DIR}/feature.json (or feature.md) not found"
    exit 1
fi

# ══════════════════════════════════════
# 阶段标记：确保 hook 级 AskUserQuestion 硬拦截生效
# ══════════════════════════════════════
echo "autonomous" > /tmp/.claude_phase

echo "══════════════════════════════════════"
echo "  Feature Plan 迭代循环"
echo "  功能: ${VERSION_ID}/${FEATURE_NAME}"
echo "  最大轮次: ${MAX_ROUNDS}"
echo "══════════════════════════════════════"

# ══════════════════════════════════════
# 初始化日志
# ══════════════════════════════════════

cat > "$LOG_FILE" << 'EOF'
# Plan 迭代日志

| 轮次 | 操作 | Critical | Important | Nice-to-have | 状态 |
|------|------|----------|-----------|--------------|------|
EOF

PREV_TOTAL=-1
CRITICAL=0
IMPORTANT=0
NICE=0
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
        # ── 奇数轮: 创建/修复 Plan ──

        if [ "$ROUND" -eq 1 ]; then
            echo "[Round $ROUND] 创建 Plan..."

            PROMPT="读取 .claude/commands/feature/plan-creator.md 中的完整工作流程，按照其中的 5 个步骤执行。

参数（已解析，直接使用）：
- version_id: ${VERSION_ID}
- feature_name: ${FEATURE_NAME}
- FEATURE_DIR: ${FEATURE_DIR}

自动化模式特殊规则：
1. 第二步（需求澄清）：不要向用户提问。改为自主决策——根据 feature.json（或 feature.md）、项目宪法（P1GoServer/.claude/constitution.md 和 freelifeclient/.claude/constitution.md）、现有代码上下文自行判断。不确定的决策标注 [自主决策]。
2. 第三步（方案摘要确认）：直接继续下一步，不等待用户确认。
3. 完成所有步骤后直接结束，不要中途停下来。"

        else
            echo "[Round $ROUND] 修复 Plan（基于上轮 Review）..."

            PROMPT="你的任务是根据 Review 报告修复 Plan。

请读取以下文件：
1. ${REVIEW_FILE} — 上一轮的 Review 报告
2. ${PLAN_FILE} — 当前 Plan（JSON 格式）
3. 如果 ${FEATURE_DIR}/plan/ 子目录存在，也读取其中的所有 .json 子文件

修复规则：
- 逐个修复 Review 报告中的 Critical 和 Important 问题
- 在修改处添加 <!-- [迭代${ROUND}修复] 原因 --> 注释
- 只修复报告中列出的问题，不要添加额外功能或重构
- Nice-to-have 问题可以顺手修复，但不强制
- 修复后对照 P1GoServer/.claude/constitution.md 和 freelifeclient/.claude/constitution.md 做快速合宪性自检"
        fi

        if [ "$ROUND" -eq 1 ]; then
            PLAN_MAX_TURNS=60
        else
            PLAN_MAX_TURNS=30
        fi
        claude_tracked "Plan 创建/修复 Round $ROUND" "$PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" --max-turns "$PLAN_MAX_TURNS" | tail -20
        echo "| $ROUND | 创建/修复 | - | - | - | done |" >> "$LOG_FILE"

    else
        # ── 偶数轮: Review Plan ──

        echo "[Round $ROUND] Review Plan..."

        PROMPT="读取 .claude/commands/feature/plan-review.md 中的完整工作流程，按照其中的步骤执行。

参数（已解析，直接使用）：
- version_id: ${VERSION_ID}
- feature_name: ${FEATURE_NAME}
- FEATURE_DIR: ${FEATURE_DIR}

自动化模式特殊规则：
1. 完成 Review 后，将完整的 Review 报告写入文件 ${REVIEW_FILE}（覆盖之前的报告）
2. 在报告文件的最后一行，必须追加以下格式的元数据（用于脚本自动解析，不要遗漏）：
   <!-- counts: critical=X important=Y nice=Z -->
   其中 X/Y/Z 替换为实际问题数量
3. 跳过第四步（交互式修复），不要询问用户如何处理，直接结束"

        claude_tracked "Plan Review Round $ROUND" "$PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" --max-turns 25 | tail -20

        # 解析 Review 结果
        if [ -f "$REVIEW_FILE" ]; then
            COUNTS_LINE=$(grep -o 'counts: critical=[0-9]* important=[0-9]* nice=[0-9]*' "$REVIEW_FILE" 2>/dev/null | tail -1 || echo "")
            if [ -n "$COUNTS_LINE" ]; then
                CRITICAL=$(echo "$COUNTS_LINE" | sed 's/.*critical=\([0-9]*\).*/\1/')
                IMPORTANT=$(echo "$COUNTS_LINE" | sed 's/.*important=\([0-9]*\).*/\1/')
                NICE=$(echo "$COUNTS_LINE" | sed 's/.*nice=\([0-9]*\).*/\1/')
            else
                echo "WARNING: 无法解析 Review 报告中的 counts 元数据"
                echo "报告文件末尾内容:"
                tail -5 "$REVIEW_FILE"
                CRITICAL=999
                IMPORTANT=999
                NICE=0
            fi
        else
            echo "WARNING: Review 报告文件未生成: ${REVIEW_FILE}"
            CRITICAL=999
            IMPORTANT=999
            NICE=0
        fi

        CURRENT_TOTAL=$((CRITICAL + IMPORTANT))
        echo "| $ROUND | Review | $CRITICAL | $IMPORTANT | $NICE | done |" >> "$LOG_FILE"
        echo "Review 结果: Critical=$CRITICAL, Important=$IMPORTANT, Nice=$NICE"

        # ── 收敛判断 ──

        if [ "$CRITICAL" -eq 0 ] && [ "$IMPORTANT" -le 2 ]; then
            REASON="质量达标"
            echo "PASS: $REASON (Critical=0, Important<=2)"
            break
        fi

        if [ "$PREV_TOTAL" -ge 0 ] && [ "$CURRENT_TOTAL" -eq "$PREV_TOTAL" ]; then
            REASON="稳定不变"
            echo "WARN: $REASON (问题总数未减少: $CURRENT_TOTAL)"
            break
        fi

        # O5: Critical 已清零且 Round≥4 时，Important 不再改善则停止（防止为 Important 无限循环）
        if [ "$ROUND" -ge 4 ] && [ "$CRITICAL" -eq 0 ] && [ "$PREV_TOTAL" -ge 0 ] && [ "$CURRENT_TOTAL" -ge "$PREV_TOTAL" ]; then
            REASON="Critical已清零，Important趋于稳定，停止迭代"
            echo "WARN: $REASON (Important=$IMPORTANT, 当前总分=$CURRENT_TOTAL >= 上轮=$PREV_TOTAL)"
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
EOF

echo ""
echo "══════════════════════════════════════"
echo "  Plan 迭代完成"
echo "══════════════════════════════════════"
echo "  轮次: $ROUND"
echo "  终止原因: $REASON"
echo "  最终质量: Critical=$CRITICAL, Important=$IMPORTANT"
echo "  Plan 文件: $PLAN_FILE"
echo "  迭代日志: $LOG_FILE"
echo "══════════════════════════════════════"
