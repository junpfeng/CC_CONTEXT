#!/bin/bash
# auto-work-loop.sh
# 全自动工作流：需求 → feature.json → plan.json → 任务拆分 → 波次并行开发+提交
# 串联 feature-plan-loop.sh 和 feature-develop-loop.sh，一键完成从需求到代码
# 波次串行开发，按依赖拓扑排序逐个执行
#
# 用法: bash .claude/scripts/auto-work-loop.sh <version_id> <feature_name> [requirement]
# 示例:
#   bash .claude/scripts/auto-work-loop.sh v0.0.3 cooking-system                    # 从 idea.md 读取需求
#   bash .claude/scripts/auto-work-loop.sh v0.0.3 cooking-system "额外补充需求"      # idea.md + 补充
#   bash .claude/scripts/auto-work-loop.sh v0.0.3 cooking-system "完整需求描述"      # 无 idea.md 时
#
# 前置条件:
#   - claude CLI 可用
#   - 从项目根目录运行

set -euo pipefail

# ══════════════════════════════════════
# 全局计量与仪表盘
# ══════════════════════════════════════

TOTAL_INPUT_TOKENS=0
TOTAL_OUTPUT_TOKENS=0
TOTAL_CACHE_READ_TOKENS=0
TOTAL_CACHE_WRITE_TOKENS=0
TOTAL_COST_USD=0
TOTAL_AGENTS=0
TOTAL_API_DURATION_MS=0
CURRENT_STAGE=""
CURRENT_TASK=""
GLOBAL_START_TIME=$(date +%s)

# 共享指标文件：子脚本（feature-develop-loop.sh 等）也可以追加指标到此文件
# 格式: 每行一个 JSON 对象 {"input_tokens":N,"output_tokens":N,"cache_read":N,"cache_write":N,"cost":F,"duration_ms":N}
# auto-work-loop 在关键节点汇总此文件
export AUTO_WORK_METRICS_FILE=""  # 在目录初始化后设置

# 格式化数字：1234567 → 1,234,567
format_number() {
    printf "%'d" "$1" 2>/dev/null || echo "$1"
}

# 格式化耗时秒数为 HH:MM:SS
format_duration() {
    local secs=$1
    printf "%02d:%02d:%02d" $((secs/3600)) $((secs%3600/60)) $((secs%60))
}

# 格式化美元金额
format_cost() {
    printf "\$%.4f" "$1" 2>/dev/null || echo "\$$1"
}

# 运行 claude -p 并收集指标
# 用法: run_claude <description> <prompt> [extra_args...]
# 输出: 文本结果写到 stdout，指标更新全局变量
# 返回值: claude 退出码
run_claude() {
    local desc="$1"
    shift
    local prompt="$1"
    shift
    local extra_args=("$@")

    TOTAL_AGENTS=$((TOTAL_AGENTS + 1))
    local agent_num=$TOTAL_AGENTS

    echo "  ┌─ Agent #${agent_num}: ${desc}"
    echo "  │  启动时间: $(date '+%H:%M:%S')"

    local tmp_json
    tmp_json=$(mktemp)

    # 调用 claude -p，用 --output-format json 获取完整指标
    claude -p "$prompt" --output-format json "${extra_args[@]}" > "$tmp_json" 2>/dev/null
    local exit_code=$?

    # 解析 JSON 指标
    if [ -f "$tmp_json" ] && [ -s "$tmp_json" ]; then
        local input_t output_t cache_r cache_w cost_usd duration_ms result_text

        input_t=$(cat "$tmp_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('usage',{}).get('input_tokens',0))" 2>/dev/null || echo "0")
        output_t=$(cat "$tmp_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('usage',{}).get('output_tokens',0))" 2>/dev/null || echo "0")
        cache_r=$(cat "$tmp_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('usage',{}).get('cache_read_input_tokens',0))" 2>/dev/null || echo "0")
        cache_w=$(cat "$tmp_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('usage',{}).get('cache_creation_input_tokens',0))" 2>/dev/null || echo "0")
        cost_usd=$(cat "$tmp_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('total_cost_usd',0))" 2>/dev/null || echo "0")
        duration_ms=$(cat "$tmp_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('duration_api_ms',0) or d.get('duration_ms',0))" 2>/dev/null || echo "0")
        result_text=$(cat "$tmp_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',''))" 2>/dev/null || echo "")

        TOTAL_INPUT_TOKENS=$((TOTAL_INPUT_TOKENS + input_t))
        TOTAL_OUTPUT_TOKENS=$((TOTAL_OUTPUT_TOKENS + output_t))
        TOTAL_CACHE_READ_TOKENS=$((TOTAL_CACHE_READ_TOKENS + cache_r))
        TOTAL_CACHE_WRITE_TOKENS=$((TOTAL_CACHE_WRITE_TOKENS + cache_w))
        # cost 用 awk 做浮点累加
        TOTAL_COST_USD=$(echo "$TOTAL_COST_USD $cost_usd" | awk '{printf "%.6f", $1 + $2}')
        TOTAL_API_DURATION_MS=$((TOTAL_API_DURATION_MS + duration_ms))

        local all_tokens=$((input_t + output_t + cache_r + cache_w))
        local duration_s=$((duration_ms / 1000))
        echo "  │  Token: in=$(format_number $input_t) out=$(format_number $output_t) cache_r=$(format_number $cache_r) cache_w=$(format_number $cache_w)"
        echo "  │  费用: $(format_cost "$cost_usd")  耗时: ${duration_s}s"
        echo "  └─ Agent #${agent_num} 完成"

        # 输出文本结果
        echo "$result_text"
    else
        echo "  │  WARNING: 无法解析 JSON 输出"
        echo "  └─ Agent #${agent_num} 完成 (无指标)"
        # 回退：直接输出原始内容
        cat "$tmp_json" 2>/dev/null || true
    fi

    rm -f "$tmp_json"

    # 更新仪表盘
    update_dashboard

    return $exit_code
}

# 运行 claude -p（仅捕获最后 N 行文本结果，兼容需要解析输出的场景）
# 用法: RESULT=$(run_claude_capture <description> <prompt> [extra_args...])
run_claude_capture() {
    local desc="$1"
    shift
    local prompt="$1"
    shift
    local extra_args=("$@")

    TOTAL_AGENTS=$((TOTAL_AGENTS + 1))
    local agent_num=$TOTAL_AGENTS

    echo "  ┌─ Agent #${agent_num}: ${desc}" >&2
    echo "  │  启动时间: $(date '+%H:%M:%S')" >&2

    local tmp_json
    tmp_json=$(mktemp)

    claude -p "$prompt" --output-format json "${extra_args[@]}" > "$tmp_json" 2>/dev/null
    local exit_code=$?

    if [ -f "$tmp_json" ] && [ -s "$tmp_json" ]; then
        local input_t output_t cache_r cache_w cost_usd duration_ms result_text

        input_t=$(cat "$tmp_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('usage',{}).get('input_tokens',0))" 2>/dev/null || echo "0")
        output_t=$(cat "$tmp_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('usage',{}).get('output_tokens',0))" 2>/dev/null || echo "0")
        cache_r=$(cat "$tmp_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('usage',{}).get('cache_read_input_tokens',0))" 2>/dev/null || echo "0")
        cache_w=$(cat "$tmp_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('usage',{}).get('cache_creation_input_tokens',0))" 2>/dev/null || echo "0")
        cost_usd=$(cat "$tmp_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('total_cost_usd',0))" 2>/dev/null || echo "0")
        duration_ms=$(cat "$tmp_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('duration_api_ms',0) or d.get('duration_ms',0))" 2>/dev/null || echo "0")
        result_text=$(cat "$tmp_json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',''))" 2>/dev/null || echo "")

        TOTAL_INPUT_TOKENS=$((TOTAL_INPUT_TOKENS + input_t))
        TOTAL_OUTPUT_TOKENS=$((TOTAL_OUTPUT_TOKENS + output_t))
        TOTAL_CACHE_READ_TOKENS=$((TOTAL_CACHE_READ_TOKENS + cache_r))
        TOTAL_CACHE_WRITE_TOKENS=$((TOTAL_CACHE_WRITE_TOKENS + cache_w))
        TOTAL_COST_USD=$(echo "$TOTAL_COST_USD $cost_usd" | awk '{printf "%.6f", $1 + $2}')
        TOTAL_API_DURATION_MS=$((TOTAL_API_DURATION_MS + duration_ms))

        local duration_s=$((duration_ms / 1000))
        echo "  │  Token: in=$(format_number $input_t) out=$(format_number $output_t) cache_r=$(format_number $cache_r)" >&2
        echo "  │  费用: $(format_cost "$cost_usd")  耗时: ${duration_s}s" >&2
        echo "  └─ Agent #${agent_num} 完成" >&2

        # 输出到 stdout 供调用方捕获
        echo "$result_text"
    else
        echo "  └─ Agent #${agent_num} 完成 (无指标)" >&2
        cat "$tmp_json" 2>/dev/null || true
    fi

    rm -f "$tmp_json"
    update_dashboard >&2

    return $exit_code
}

# 更新仪表盘文件（可被 tail -f 实时监控）
update_dashboard() {
    [ -z "${DASHBOARD_FILE:-}" ] && return

    local now=$(date +%s)
    local elapsed=$((now - GLOBAL_START_TIME))
    local total_all_tokens=$((TOTAL_INPUT_TOKENS + TOTAL_OUTPUT_TOKENS + TOTAL_CACHE_READ_TOKENS + TOTAL_CACHE_WRITE_TOKENS))

    cat > "$DASHBOARD_FILE" << DASHBOARD_EOF
╔══════════════════════════════════════════════════════════════╗
║              Auto-Work 实时仪表盘                             ║
╠══════════════════════════════════════════════════════════════╣
║  版本: ${VERSION_ID}  功能: ${FEATURE_NAME}
║  运行时间: $(format_duration $elapsed)  更新: $(date '+%H:%M:%S')
╠══════════════════════════════════════════════════════════════╣
║  ▸ 当前阶段: ${CURRENT_STAGE:-初始化}
║  ▸ 当前任务: ${CURRENT_TASK:-无}
╠══════════════════════════════════════════════════════════════╣
║  📊 Agent 统计
║    启动总数: ${TOTAL_AGENTS}
║    API 总耗时: $(format_duration $((TOTAL_API_DURATION_MS / 1000)))
╠══════════════════════════════════════════════════════════════╣
║  🔤 Token 消耗
║    输入 Token:     $(printf "%12s" "$(format_number $TOTAL_INPUT_TOKENS)")
║    输出 Token:     $(printf "%12s" "$(format_number $TOTAL_OUTPUT_TOKENS)")
║    缓存读取:       $(printf "%12s" "$(format_number $TOTAL_CACHE_READ_TOKENS)")
║    缓存写入:       $(printf "%12s" "$(format_number $TOTAL_CACHE_WRITE_TOKENS)")
║    ─────────────────────────────
║    Token 总计:     $(printf "%12s" "$(format_number $total_all_tokens)")
╠══════════════════════════════════════════════════════════════╣
║  💰 费用: $(format_cost "$TOTAL_COST_USD")
╠══════════════════════════════════════════════════════════════╣
║  📋 任务进度: Keep=${COMPLETED_TASKS:-0} Discard=${DISCARDED_TASKS:-0} / 总计=${TOTAL_TASKS:-?}
║  🌊 波次: ${WAVE_NUM:-?}/${WAVE_TOTAL:-?}
╚══════════════════════════════════════════════════════════════╝
DASHBOARD_EOF
}

# 汇总子脚本写入的指标文件（feature-develop-loop.sh 等通过 AUTO_WORK_METRICS_FILE 追加）
aggregate_sub_metrics() {
    [ -z "${AUTO_WORK_METRICS_FILE:-}" ] && return
    [ ! -f "$AUTO_WORK_METRICS_FILE" ] && return
    [ ! -s "$AUTO_WORK_METRICS_FILE" ] && return

    # 读取所有行，累加到全局变量
    local sub_input sub_output sub_cache_r sub_cache_w sub_cost sub_duration sub_count
    sub_input=$(python3 -c "
import json, sys
total = 0
for line in open(sys.argv[1]):
    line = line.strip()
    if line:
        try: total += json.loads(line).get('input_tokens', 0)
        except: pass
print(total)
" "$AUTO_WORK_METRICS_FILE" 2>/dev/null || echo "0")

    sub_output=$(python3 -c "
import json, sys
total = 0
for line in open(sys.argv[1]):
    line = line.strip()
    if line:
        try: total += json.loads(line).get('output_tokens', 0)
        except: pass
print(total)
" "$AUTO_WORK_METRICS_FILE" 2>/dev/null || echo "0")

    sub_cache_r=$(python3 -c "
import json, sys
total = 0
for line in open(sys.argv[1]):
    line = line.strip()
    if line:
        try: total += json.loads(line).get('cache_read', 0)
        except: pass
print(total)
" "$AUTO_WORK_METRICS_FILE" 2>/dev/null || echo "0")

    sub_cache_w=$(python3 -c "
import json, sys
total = 0
for line in open(sys.argv[1]):
    line = line.strip()
    if line:
        try: total += json.loads(line).get('cache_write', 0)
        except: pass
print(total)
" "$AUTO_WORK_METRICS_FILE" 2>/dev/null || echo "0")

    sub_cost=$(python3 -c "
import json, sys
total = 0.0
for line in open(sys.argv[1]):
    line = line.strip()
    if line:
        try: total += json.loads(line).get('cost', 0.0)
        except: pass
print(f'{total:.6f}')
" "$AUTO_WORK_METRICS_FILE" 2>/dev/null || echo "0")

    sub_duration=$(python3 -c "
import json, sys
total = 0
for line in open(sys.argv[1]):
    line = line.strip()
    if line:
        try: total += json.loads(line).get('duration_ms', 0)
        except: pass
print(total)
" "$AUTO_WORK_METRICS_FILE" 2>/dev/null || echo "0")

    sub_count=$(python3 -c "
import sys
count = 0
for line in open(sys.argv[1]):
    if line.strip(): count += 1
print(count)
" "$AUTO_WORK_METRICS_FILE" 2>/dev/null || echo "0")

    # 累加到全局（注意：这些是子进程额外产生的，不和 run_claude 重复）
    TOTAL_INPUT_TOKENS=$((TOTAL_INPUT_TOKENS + sub_input))
    TOTAL_OUTPUT_TOKENS=$((TOTAL_OUTPUT_TOKENS + sub_output))
    TOTAL_CACHE_READ_TOKENS=$((TOTAL_CACHE_READ_TOKENS + sub_cache_r))
    TOTAL_CACHE_WRITE_TOKENS=$((TOTAL_CACHE_WRITE_TOKENS + sub_cache_w))
    TOTAL_COST_USD=$(echo "$TOTAL_COST_USD $sub_cost" | awk '{printf "%.6f", $1 + $2}')
    TOTAL_API_DURATION_MS=$((TOTAL_API_DURATION_MS + sub_duration))
    TOTAL_AGENTS=$((TOTAL_AGENTS + sub_count))

    # 清空已汇总的指标（避免重复计算）
    > "$AUTO_WORK_METRICS_FILE"

    echo "  [指标汇总] 子进程 +${sub_count} agents, +$(format_number $((sub_input + sub_output + sub_cache_r + sub_cache_w))) tokens, +$(format_cost "$sub_cost")"
    update_dashboard
}

# 打印阶段分隔条（含累计指标摘要）
print_stage_header() {
    local stage_name="$1"
    CURRENT_STAGE="$stage_name"
    CURRENT_TASK=""

    local now=$(date +%s)
    local elapsed=$((now - GLOBAL_START_TIME))
    local total_all_tokens=$((TOTAL_INPUT_TOKENS + TOTAL_OUTPUT_TOKENS + TOTAL_CACHE_READ_TOKENS + TOTAL_CACHE_WRITE_TOKENS))

    echo ""
    echo "══════════════════════════════════════════════════════════════"
    echo "  ${stage_name}"
    echo "──────────────────────────────────────────────────────────────"
    echo "  ⏱ 已运行 $(format_duration $elapsed) │ 🤖 ${TOTAL_AGENTS} agents │ 🔤 $(format_number $total_all_tokens) tokens │ 💰 $(format_cost "$TOTAL_COST_USD")"
    echo "══════════════════════════════════════════════════════════════"

    update_dashboard
}

# ── 元审查 Agent：分析工作过程中的反复错误，持久化改进规则 ──
# 在每个波次结束后调用，分析 results.tsv 和迭代日志，提取可改进的模式
# 改进规则写入 .claude/rules/ 或 .claude/memory/，后续 auto-work 自动加载
META_REVIEW_COUNTER=0
run_meta_review() {
    META_REVIEW_COUNTER=$((META_REVIEW_COUNTER + 1))

    # 多信号触发：任一条件满足即运行（纯 bash 判断，零 token 成本）
    local discard_count=${DISCARDED_TASKS:-0}
    local total_results=0
    if [ -f "$RESULTS_FILE" ]; then
        total_results=$(tail -n +2 "$RESULTS_FILE" | wc -l)
    fi

    local should_trigger=false

    # 信号 1：有 discard（原有条件）
    if [ "$discard_count" -gt 0 ]; then
        should_trigger=true
    fi

    # 信号 2：results.tsv 超过 3 行（有重试）
    if [ "$total_results" -ge 3 ]; then
        should_trigger=true
    fi

    # 信号 3：任何 task 触达 max fix rounds（attempt 列 >= 3）
    if [ -f "$RESULTS_FILE" ]; then
        local max_attempt=$(tail -n +2 "$RESULTS_FILE" | awk -F'\t' '{print $4}' | sort -n | tail -1)
        if [ "${max_attempt:-0}" -ge 3 ]; then
            should_trigger=true
        fi
    fi

    # 信号 4：同类编译错误出现 ≥2 次（grep iteration logs 中的 error/CS/go build 关键模式）
    local error_pattern_count=0
    for log in "${FEATURE_DIR}"/develop-iteration-log-*.md; do
        [ -f "$log" ] || continue
        # 提取常见编译错误模式（CS 错误码或 Go 编译错误）
        error_pattern_count=$((error_pattern_count + $(grep -c 'error CS[0-9]\{4\}\|cannot use\|undefined:\|does not implement' "$log" 2>/dev/null || echo 0)))
    done
    if [ "$error_pattern_count" -ge 2 ]; then
        should_trigger=true
    fi

    # 信号 5：同类 review issue 出现 ≥2 次（grep review reports 中重复的 HIGH/CRITICAL 关键词）
    local review_issue_repeats=0
    if [ -d "${FEATURE_DIR}" ]; then
        # 提取所有 HIGH/CRITICAL 行，统计重复出现的问题关键词
        local issue_lines=$(grep -h 'CRITICAL\|HIGH' "${FEATURE_DIR}"/develop-review-report-*.md "${FEATURE_DIR}"/review-round-*/review-*.md 2>/dev/null | sort | uniq -d | wc -l)
        review_issue_repeats=${issue_lines:-0}
    fi
    if [ "$review_issue_repeats" -ge 1 ]; then
        should_trigger=true
    fi

    if [ "$should_trigger" = false ]; then
        return 0
    fi

    echo ""
    echo "──────────────────────────────────────────────────────────────"
    echo "  [Meta-Review] 分析工作过程，提取改进规则 (#${META_REVIEW_COUNTER})"
    echo "──────────────────────────────────────────────────────────────"

    # 收集迭代日志（最近的几个任务）
    local recent_logs=""
    for log in $(ls "${FEATURE_DIR}"/develop-iteration-log-*.md 2>/dev/null | tail -3); do
        recent_logs="${recent_logs}
--- $(basename "$log") ---
$(tail -30 "$log")"
    done

    local results_content=""
    if [ -f "$RESULTS_FILE" ]; then
        # 上下文控制：只读最近 50 行，截断到 8KB
        results_content=$(tail -50 "$RESULTS_FILE" | cut -c1-8192)
    fi

    local review_reports=""
    for rpt in $(ls "${FEATURE_DIR}"/develop-review-report-*.md 2>/dev/null | tail -3); do
        # 上下文控制：每份报告只取最近 20 行，截断到 4KB
        review_reports="${review_reports}
--- $(basename "$rpt") ---
$(tail -20 "$rpt" | cut -c1-4096)"
    done

    local existing_rules=""
    if [ -d ".claude/rules" ]; then
        existing_rules=$(ls .claude/rules/*.md 2>/dev/null | head -20 | while read f; do echo "- $(basename "$f")"; done)
    fi

    local META_PROMPT="你是一个 AI 工作流优化专家。分析以下 auto-work 工作过程数据，找出反复出现的问题模式，并生成可持久化的改进规则。

## 工作数据

### results.tsv（任务结果追踪）
\`\`\`
${results_content}
\`\`\`

### 最近的开发迭代日志
\`\`\`
${recent_logs}
\`\`\`

### 最近的 Review 报告摘要
\`\`\`
${review_reports}
\`\`\`

### 已有的规则文件
${existing_rules:-无}

## 分析要求

### 结构化模式检测（逐项检查）

| 检测项 | 触发条件 | 分析方法 |
|--------|---------|---------|
| 编译错误聚类 | 同类错误码出现 ≥2 次 | 提取 CS/Go 错误码，按类型分组计数 |
| Review 问题聚类 | 同类 HIGH/CRITICAL 出现 ≥2 次 | 提取问题描述关键词，聚类去重 |
| Discard 原因聚类 | discard ≥1 | 按 results.tsv 的 reason 列分类 |
| Fix 轮次饱和 | 任何 task 的 attempt ≥3 | 定位哪些 task 反复修复未收敛 |
| 机械性违规残留 | 同类格式问题跨文件出现 | grep 已有 lesson 规则对应的模式 |

1. **逐项检测**：按上表逐项分析，输出每项的命中/未命中及具体数据
2. **根因分析**：为什么这些错误会反复出现？是提示词不够具体？是缺少上下文？是项目规范不清楚？
3. **规则生成**：仅对命中的检测项生成规则，未命中的跳过

## 输出规则

只在发现了**明确的、可操作的改进点**时才生成规则文件。不要生成模糊的建议。

规则文件写入 \`.claude/rules/auto-work-lesson-{编号}.md\`，格式：
\`\`\`markdown
---
description: 一行描述规则适用场景
globs:
alwaysApply: true
---

# {规则标题}

## 触发条件
{什么情况下需要遵循此规则}

## 规则内容
{具体要求，必须可执行、可验证}

## 来源
auto-work meta-review #${META_REVIEW_COUNTER}，基于 ${VERSION_ID}/${FEATURE_NAME} 的工作数据
\`\`\`

规则要求：
- 必须是具体、可操作的（不能是"注意质量"这种模糊建议）
- 必须基于实际观察到的反复错误（不是理论推导）
- 如果已有规则覆盖了这个问题，跳过不重复创建
- 每次最多生成 2 条规则（避免过度规则化）
- 如果没有发现值得持久化的问题，只输出 'NO_NEW_RULES' 即可

同时将分析摘要追加到 ${FEATURE_DIR}/meta-review.md（创建或追加）。

如果生成了新规则，还需追加到 \`docs/knowledge/consolidation-index.md\` 的 \`## Coding Rules\` section：
- 每条格式：\`- [lesson-NNN] {标题} → .claude/rules/auto-work-lesson-NNN.md\`
- 若 consolidation-index.md 不存在则跳过（不阻塞）"

    run_claude "Meta-Review #${META_REVIEW_COUNTER}" "$META_PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob" | tail -10

    echo "  [Meta-Review] 完成"
    echo "──────────────────────────────────────────────────────────────"
}

# ══════════════════════════════════════
# 参数解析
# ══════════════════════════════════════

VERSION_ID="${1:?用法: $0 <version_id> <feature_name> [requirement]}"
FEATURE_NAME="${2:?用法: $0 <version_id> <feature_name> [requirement]}"
USER_REQUIREMENT="${3:-}"

FEATURE_DIR="docs/version/${VERSION_ID}/${FEATURE_NAME}"
WORK_LOG="${FEATURE_DIR}/auto-work-log.md"
IDEA_FILE="${FEATURE_DIR}/idea.md"

# 创建目录
mkdir -p "$FEATURE_DIR"

# 初始化共享指标文件（子脚本可追加）
AUTO_WORK_METRICS_FILE="${FEATURE_DIR}/.metrics.jsonl"
export AUTO_WORK_METRICS_FILE
> "$AUTO_WORK_METRICS_FILE"

# ══════════════════════════════════════
# 合并需求来源：idea.md + 用户输入
# ══════════════════════════════════════

REQUIREMENT=""

if [ -f "$IDEA_FILE" ]; then
    IDEA_CONTENT=$(cat "$IDEA_FILE")
    echo "读取到 idea.md: ${IDEA_FILE}"
    REQUIREMENT="$IDEA_CONTENT"

    # idea.md schema 检查：验证必需章节
    if ! grep -q "## 核心需求" "$IDEA_FILE"; then
        echo "WARNING: idea.md 缺少 '## 核心需求' 章节（new-feature Step 2 应创建此章节）"
    fi
    if ! grep -q "## 确认方案" "$IDEA_FILE"; then
        echo "WARNING: idea.md 缺少 '## 确认方案' 章节（new-feature Step 3 应追加此章节）。将使用原始需求继续"
    fi
fi

if [ -n "$USER_REQUIREMENT" ]; then
    if [ -n "$REQUIREMENT" ]; then
        # 两者都有：idea.md 为基础，用户输入为补充
        REQUIREMENT="${REQUIREMENT}

---
补充需求：${USER_REQUIREMENT}"
        echo "合并用户补充需求"
    else
        # 仅有用户输入
        REQUIREMENT="$USER_REQUIREMENT"
    fi
fi

if [ -z "$REQUIREMENT" ]; then
    echo "ERROR: 未找到 ${IDEA_FILE} 且未提供需求描述"
    echo "请创建 ${IDEA_FILE} 或传入第三个参数"
    exit 1
fi

echo "══════════════════════════════════════════════════════════════"
echo "  Auto-Work 全自动流程（波次并行）"
echo "  版本: ${VERSION_ID}"
echo "  功能: ${FEATURE_NAME}"
echo "  需求来源: $([ -f "$IDEA_FILE" ] && echo 'idea.md' || echo '')$([ -f "$IDEA_FILE" ] && [ -n "$USER_REQUIREMENT" ] && echo ' + ' || echo '')$([ -n "$USER_REQUIREMENT" ] && echo '用户输入' || echo '')"
echo "  仪表盘: tail -f ${FEATURE_DIR}/dashboard.txt"
echo "══════════════════════════════════════════════════════════════"

# ══════════════════════════════════════
# 初始化总日志 + 仪表盘
# ══════════════════════════════════════

DASHBOARD_FILE="${FEATURE_DIR}/dashboard.txt"
IDEA_EXISTS="否"
[ -f "$IDEA_FILE" ] && IDEA_EXISTS="是"

cat > "$WORK_LOG" << EOF
# Auto-Work 全流程日志

- **版本**: ${VERSION_ID}
- **功能**: ${FEATURE_NAME}
- **idea.md**: ${IDEA_EXISTS}
- **补充需求**: ${USER_REQUIREMENT:-无}
- **启动时间**: $(date '+%Y-%m-%d %H:%M:%S')
- **模式**: 波次串行
- **实时仪表盘**: \`tail -f ${DASHBOARD_FILE}\`

| 阶段 | 状态 | 耗时 | 备注 |
|------|------|------|------|
EOF

# 初始化仪表盘
CURRENT_STAGE="初始化"
update_dashboard

# ══════════════════════════════════════
# 阶段 P0：记忆查询（从历史经验中提取可复用信息）
# ══════════════════════════════════════

print_stage_header "阶段 P0：记忆查询"

MEMORY_FILE="${FEATURE_DIR}/memory-context.txt"
MEMORY_CONTEXT=""

if [ -f "$MEMORY_FILE" ]; then
    MEMORY_CONTEXT=$(cat "$MEMORY_FILE")
    echo "记忆上下文已存在，跳过查询"
    echo "| 记忆查询 | 跳过（已存在） | 0s | $(wc -c < "$MEMORY_FILE") bytes |" >> "$WORK_LOG"
else
    P0_START=$(date +%s)

    MEMORY_PROMPT="你是项目记忆检索助手。从以下需求描述中提取 2-3 个核心关键词，然后在项目记忆和文档中搜索相关经验。

需求描述：
${REQUIREMENT}

搜索范围（按优先级）：
1. 项目记忆索引：读取项目根目录下能找到的 MEMORY.md（auto-memory 索引）
2. 已有经验规则：.claude/rules/auto-work-lesson-*.md
3. 领域知识文档：docs/knowledge/ 下与关键词相关的目录
4. 项目 CLAUDE.md 中提到的相关模块

输出要求（严格控制在 2000 字以内）：
- 如果找到相关经验：列出可复用的思路、需要避免的坑、相关模块的架构要点
- 如果未找到：输出 'NO_RELEVANT_MEMORY'
- 不要输出搜索过程，只输出结论"

    MEMORY_RESULT=$(run_claude_capture "记忆查询" "$MEMORY_PROMPT" --allowedTools "Read,Grep,Glob" --max-turns 5 2>/dev/null || echo "NO_RELEVANT_MEMORY")

    # 截断到 2000 字符，防止下游 prompt 膨胀
    MEMORY_CONTEXT=$(echo "$MEMORY_RESULT" | head -80 | cut -c1-2000)

    if echo "$MEMORY_CONTEXT" | grep -qi "NO_RELEVANT_MEMORY\|no relevant memory\|未找到"; then
        MEMORY_CONTEXT=""
        echo "未找到相关历史记忆"
    else
        echo "$MEMORY_CONTEXT" > "$MEMORY_FILE"
        echo "记忆查询完成，找到相关经验"
    fi

    P0_END=$(date +%s)
    P0_DURATION=$((P0_END - P0_START))
    echo "| 记忆查询 | 完成 | ${P0_DURATION}s | $([ -n "$MEMORY_CONTEXT" ] && echo "有经验" || echo "无") |" >> "$WORK_LOG"
fi

# 上下文控制：截断 REQUIREMENT 防止 prompt 膨胀（保留前 10KB）
REQUIREMENT_FULL="$REQUIREMENT"
REQUIREMENT=$(echo "$REQUIREMENT" | head -300 | cut -c1-10240)
if [ ${#REQUIREMENT_FULL} -gt 10240 ]; then
    echo "WARNING: REQUIREMENT 已截断 (${#REQUIREMENT_FULL} → 10240 chars)"
fi

# ══════════════════════════════════════
# 阶段零：需求分类（判断是否需要调研）
# ══════════════════════════════════════

STAGE0_START=$(date +%s)
print_stage_header "阶段零：需求分类"

CLASSIFY_FILE="${FEATURE_DIR}/classification.txt"

if [ -f "$CLASSIFY_FILE" ]; then
    WORK_TYPE=$(cat "$CLASSIFY_FILE" | tr -d '[:space:]')
    echo "分类结果已存在: ${WORK_TYPE}，跳过分类"
    echo "| 需求分类 | 跳过（已存在） | 0s | ${WORK_TYPE} |" >> "$WORK_LOG"
elif grep -q '## 确认方案' "${FEATURE_DIR}/idea.md" 2>/dev/null; then
    # /new-feature 已完成人工方案确认，跳过分类和调研
    WORK_TYPE="direct"
    echo "$WORK_TYPE" > "$CLASSIFY_FILE"
    echo "idea.md 含 '## 确认方案'（来自 /new-feature），直接分类为 direct，跳过调研"
    echo "| 需求分类 | 跳过（上游已确认） | 0s | direct |" >> "$WORK_LOG"
else
    CLASSIFY_PROMPT="你是一名资深全栈游戏开发工程师。请分析以下需求，判断它属于哪种工作类型。

需求内容：
${REQUIREMENT}
$([ -n "$MEMORY_CONTEXT" ] && echo "
历史经验参考（来自项目记忆）：
${MEMORY_CONTEXT}
")

请先阅读项目结构（CLAUDE.md）和相关代码，然后判断这个需求属于以下哪种类型：

**research（需要调研）**— 满足以下任一条件：
- 全新的系统/玩法设计，项目中没有类似实现可参考
- 需要对比多种技术方案才能做决策（如选择 ECS vs GameObject、选择同步方案等）
- 涉及不熟悉的第三方库/平台能力，需要先调查可行性
- 需求描述模糊，需要发散探索才能明确技术路线

**direct（直接开发）**— 满足以下任一条件：
- 在已有系统上修复 Bug
- 在已有系统上优化性能或重构
- 扩展已有功能（增加新的配置项、新的 UI 面板、新的消息类型等）
- 需求明确且项目中有高度相似的实现可参考
- 纯配置/数据层面的工作

判断规则：
1. 搜索项目代码，看是否已有相似系统可以参考
2. 如果需求涉及的所有技术点在项目中都有成熟模式，判定为 direct
3. 如果需求的核心技术路线不明确、或者需要在多个方案间做选型，判定为 research
4. 偏向 direct — 只有真正需要发散调研时才判定为 research

**只输出一个词：research 或 direct**，不要输出其他任何内容。"

    WORK_TYPE=$(run_claude_capture "需求分类" "$CLASSIFY_PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" | grep -oiE '(research|direct)' | tail -1 | tr '[:upper:]' '[:lower:]')

    # 默认为 direct（如果分类失败）
    if [ "$WORK_TYPE" != "research" ] && [ "$WORK_TYPE" != "direct" ]; then
        echo "WARNING: 分类结果异常 ('${WORK_TYPE}')，默认为 direct"
        WORK_TYPE="direct"
    fi

    echo "$WORK_TYPE" > "$CLASSIFY_FILE"

    STAGE0_END=$(date +%s)
    STAGE0_DURATION=$((STAGE0_END - STAGE0_START))
    echo "| 需求分类 | 完成 | ${STAGE0_DURATION}s | ${WORK_TYPE} |" >> "$WORK_LOG"
    echo "需求分类: ${WORK_TYPE} (${STAGE0_DURATION}s)"
fi

# ══════════════════════════════════════
# 阶段零-B：调研（仅 research 类型执行）
# ══════════════════════════════════════

if [ "$WORK_TYPE" = "research" ]; then
    STAGE0B_START=$(date +%s)
    print_stage_header "阶段零-B：技术调研"

    RESEARCH_DIR="docs/research/${FEATURE_NAME}"
    RESEARCH_RESULT="${RESEARCH_DIR}/research-result.md"

    if [ -f "$RESEARCH_RESULT" ]; then
        echo "调研报告已存在，跳过调研"
        echo "| 技术调研 | 跳过（已存在） | 0s | - |" >> "$WORK_LOG"
    else
        # 将需求写入 idea.md 供调研使用
        mkdir -p "$RESEARCH_DIR"
        if [ ! -f "${RESEARCH_DIR}/idea.md" ]; then
            echo "$REQUIREMENT" > "${RESEARCH_DIR}/idea.md"
        fi

        bash .claude/scripts/research-loop.sh "$FEATURE_NAME" 6
        RESEARCH_EXIT=$?
        aggregate_sub_metrics

        STAGE0B_END=$(date +%s)
        STAGE0B_DURATION=$((STAGE0B_END - STAGE0B_START))

        if [ $RESEARCH_EXIT -ne 0 ]; then
            echo "WARNING: 调研阶段异常 (exit=$RESEARCH_EXIT)，继续后续流程"
            echo "| 技术调研 | 异常 | ${STAGE0B_DURATION}s | exit=$RESEARCH_EXIT |" >> "$WORK_LOG"
        else
            echo "| 技术调研 | 完成 | ${STAGE0B_DURATION}s | ${RESEARCH_RESULT} |" >> "$WORK_LOG"
            echo "技术调研完成 (${STAGE0B_DURATION}s)"

            # 将调研结论追加到需求中，供后续阶段使用
            if [ -f "$RESEARCH_RESULT" ]; then
                REQUIREMENT="${REQUIREMENT}

---
技术调研结论（参考 ${RESEARCH_RESULT}）：
$(head -100 "$RESEARCH_RESULT")"
            fi
        fi
    fi
else
    echo ""
    echo "需求类型为 direct，跳过调研阶段"
    echo "| 技术调研 | 跳过（direct 类型） | 0s | - |" >> "$WORK_LOG"
fi

# ══════════════════════════════════════
# 阶段一：生成 feature.json
# ══════════════════════════════════════

STAGE1_START=$(date +%s)
print_stage_header "阶段一：生成 feature.json"

if [ -f "${FEATURE_DIR}/feature.json" ]; then
    echo "feature.json 已存在，跳过生成"
    echo "| 生成 feature.json | 跳过（已存在） | 0s | - |" >> "$WORK_LOG"
else
    PROMPT="你是一个资深游戏策划兼技术专家。请根据以下需求输入，生成一份 JSON 格式的功能需求文档。

需求输入：
${REQUIREMENT}
$([ -n "$MEMORY_CONTEXT" ] && echo "
历史经验参考（来自项目记忆，注意避免踩已知的坑）：
${MEMORY_CONTEXT}
")

请先阅读以下文件建立上下文：
1. 项目宪法：P1GoServer/.claude/constitution.md 和 freelifeclient/.claude/constitution.md
2. 项目概述：CLAUDE.md（只读概述部分）
3. 如果需求涉及已有系统，搜索相关代码了解现有实现

然后将需求文档写入 ${FEATURE_DIR}/feature.json，严格遵循以下 JSON Schema：

\`\`\`json
{
  \"name\": \"功能名称\",
  \"overview\": \"一段话描述功能目标和核心价值\",
  \"requirements\": [
    {
      \"id\": \"REQ-001\",
      \"category\": \"需求分类（如：核心玩法、UI交互、网络同步等）\",
      \"title\": \"需求标题\",
      \"description\": \"详细需求描述，必须是可实现、可验证的\",
      \"priority\": \"P0|P1|P2\",
      \"side\": \"client|server|both\",
      \"acceptance_criteria\": [
        \"具体的验收条件1\",
        \"具体的验收条件2\"
      ]
    }
  ],
  \"interaction_design\": {
    \"description\": \"用户如何使用这个功能的整体描述\",
    \"controls\": [\"操控方案条目\"],
    \"flows\": [\"交互流程条目\"]
  },
  \"technical_constraints\": [
    {
      \"category\": \"性能|网络|架构|资源\",
      \"description\": \"约束描述\"
    }
  ],
  \"dependencies\": [\"与现有系统的关系描述\"],
  \"notes\": [\"待确认项或补充说明，用 [待确认] 标注\"]
}
\`\`\`

规则：
- 基于需求描述扩展细节，但不要凭空捏造用户没提到的大功能
- 不确定的地方在 notes 数组中标注 [待确认]
- 考虑手游平台的性能约束
- 考虑 CS 架构下的前后端职责分工
- 每条 requirement 必须带 acceptance_criteria
- priority: P0=核心必做, P1=重要, P2=可选/后续迭代
- 输出必须是合法 JSON，直接写文件，不要向用户提问"

    run_claude "生成 feature.json" "$PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" | tail -20

    if [ ! -f "${FEATURE_DIR}/feature.json" ]; then
        echo "ERROR: feature.json 生成失败"
        echo "| 生成 feature.json | 失败 | - | 文件未生成 |" >> "$WORK_LOG"
        exit 1
    fi

    STAGE1_END=$(date +%s)
    STAGE1_DURATION=$((STAGE1_END - STAGE1_START))
    echo "| 生成 feature.json | 完成 | ${STAGE1_DURATION}s | agents=${TOTAL_AGENTS} cost=$(format_cost "$TOTAL_COST_USD") |" >> "$WORK_LOG"
    echo "feature.json 生成完成 (${STAGE1_DURATION}s)"
fi

# ══════════════════════════════════════
# 阶段二：Plan 迭代循环
# ══════════════════════════════════════

STAGE2_START=$(date +%s)
print_stage_header "阶段二：Plan 迭代循环"

if [ -f "${FEATURE_DIR}/plan.json" ]; then
    echo "plan.json 已存在，跳过 Plan 阶段"
    echo "| Plan 迭代 | 跳过（已存在） | 0s | - |" >> "$WORK_LOG"
else
    bash .claude/scripts/feature-plan-loop.sh "$VERSION_ID" "$FEATURE_NAME" 3
    PLAN_EXIT=$?
    aggregate_sub_metrics

    STAGE2_END=$(date +%s)
    STAGE2_DURATION=$((STAGE2_END - STAGE2_START))

    if [ $PLAN_EXIT -ne 0 ] || [ ! -f "${FEATURE_DIR}/plan.json" ]; then
        echo "ERROR: Plan 阶段失败"
        echo "| Plan 迭代 | 失败 | ${STAGE2_DURATION}s | exit=$PLAN_EXIT |" >> "$WORK_LOG"
        exit 1
    fi

    # 从 plan-iteration-log.md 提取最终状态
    PLAN_SUMMARY=""
    if [ -f "${FEATURE_DIR}/plan-iteration-log.md" ]; then
        PLAN_SUMMARY=$(tail -5 "${FEATURE_DIR}/plan-iteration-log.md" | grep "终止原因" || echo "")
    fi
    echo "| Plan 迭代 | 完成 | ${STAGE2_DURATION}s | ${PLAN_SUMMARY} |" >> "$WORK_LOG"
    echo "Plan 阶段完成 (${STAGE2_DURATION}s)"
fi

# ══════════════════════════════════════
# 阶段三：任务拆分
# ══════════════════════════════════════

STAGE3_START=$(date +%s)
print_stage_header "阶段三：任务拆分"

TASKS_DIR="${FEATURE_DIR}/tasks"

if [ -d "$TASKS_DIR" ] && ls "$TASKS_DIR"/task-*.md &>/dev/null; then
    TASK_COUNT=$(ls "$TASKS_DIR"/task-*.md 2>/dev/null | wc -l)
    echo "tasks/ 已存在（${TASK_COUNT} 个任务），跳过拆分"
    echo "| 任务拆分 | 跳过（已存在） | 0s | ${TASK_COUNT} 个任务 |" >> "$WORK_LOG"
else
    mkdir -p "$TASKS_DIR"

    PROMPT="你是一名资深全栈游戏开发工程师。请将技术方案拆分为可独立开发、验证、提交的任务。

请读取以下文件：
1. ${FEATURE_DIR}/plan.json — 技术方案（JSON 格式）
2. ${FEATURE_DIR}/feature.json — 功能需求（JSON 格式）
3. 如果 ${FEATURE_DIR}/plan/ 子目录存在，也读取其中的 .json 子文件

拆分规则：
- 每个任务必须是**可独立编译验证**的最小单元（做完这个任务后，代码能编译通过）
- 任务按依赖顺序排列（被依赖的在前）
- 粒度参考：一个任务通常包含 1-5 个文件的新增/修改
- 典型拆分维度：
  1. 协议定义 + 基础数据结构（Proto、枚举、常量）
  2. 服务端核心逻辑（Model、Service、Handler）
  3. 客户端 Manager + 核心逻辑
  4. 客户端 UI 面板
  5. 集成联调（状态机衔接、启动流程等）
- **并行友好**：尽量让服务端任务和客户端任务依赖同一个前置（如 Proto 定义），而非互相依赖，这样它们可以在同一波次并行开发

每个任务输出为独立文件 ${TASKS_DIR}/task-NN.md（NN 从 01 开始），格式：

\`\`\`markdown
---
name: 简短任务名（如：定义协议和数据结构）
status: pending
---

## 范围
- 新增: path/to/file1.go — 职责描述
- 新增: path/to/file2.cs — 职责描述
- 修改: path/to/existing.go — 修改描述

## 验证标准
- 服务端 make build 编译通过
- 客户端无 using/命名空间错误
- （其他具体验证点）

## 依赖
- 无 / 依赖 task-01
\`\`\`

同时生成 ${TASKS_DIR}/README.md 索引文件，列出所有任务的编号、名称、依赖关系。

注意：
- 不要把所有东西塞进一个任务
- 也不要拆得太细（单个文件不需要单独一个任务，除非该文件非常复杂）
- 确保每个任务完成后代码状态是健康的（能编译，不会有悬空引用）"

    run_claude "任务拆分" "$PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" | tail -20

    TASK_COUNT=$(ls "$TASKS_DIR"/task-*.md 2>/dev/null | wc -l)
    if [ "$TASK_COUNT" -eq 0 ]; then
        echo "ERROR: 任务拆分失败，未生成任何 task 文件"
        echo "| 任务拆分 | 失败 | - | 未生成 task 文件 |" >> "$WORK_LOG"
        exit 1
    fi

    STAGE3_END=$(date +%s)
    STAGE3_DURATION=$((STAGE3_END - STAGE3_START))
    echo "| 任务拆分 | 完成 | ${STAGE3_DURATION}s | ${TASK_COUNT} 个任务, agents=${TOTAL_AGENTS} |" >> "$WORK_LOG"
    echo "任务拆分完成：${TASK_COUNT} 个任务 (${STAGE3_DURATION}s)"
fi

# ══════════════════════════════════════
# 阶段四：任务开发（波次并行 + 原子化）
# ══════════════════════════════════════
#
# 核心策略：
# 1. 依赖分析：将任务拓扑排序为"波次"（wave），同一波次内的任务无互相依赖
# 2. 单任务波次：直接在主工作目录执行
# 3. 多任务波次：串行逐个执行
# 4. 每个任务走完整 develop+review 循环

STAGE4_START=$(date +%s)
print_stage_header "阶段四：任务开发（波次并行 + 原子化）"

TASK_FILES=$(ls "$TASKS_DIR"/task-*.md 2>/dev/null | sort)
TOTAL_TASKS=$(echo "$TASK_FILES" | wc -l)
COMPLETED_TASKS=0
FAILED_TASKS=0
DISCARDED_TASKS=0

PROJECT_ROOT="$(pwd)"

# ── 初始化 results.tsv（统一结果追踪）──
RESULTS_FILE="${FEATURE_DIR}/results.tsv"
if [ ! -f "$RESULTS_FILE" ]; then
    echo -e "phase\ttask_id\twave\tattempt\taction\tduration_s\tcompile_ok\treview_critical\treview_high\tdecision\treason" > "$RESULTS_FILE"
fi

# ── 公共函数：保存各仓库的 git 检查点 ──
save_git_checkpoint() {
    GIT_CKPT_CLIENT=""
    GIT_CKPT_SERVER=""
    GIT_CKPT_PROTO=""
    if [ -e "freelifeclient/.git" ]; then
        GIT_CKPT_CLIENT=$(git -C freelifeclient rev-parse HEAD 2>/dev/null || echo "")
    fi
    if [ -e "P1GoServer/.git" ]; then
        GIT_CKPT_SERVER=$(git -C P1GoServer rev-parse HEAD 2>/dev/null || echo "")
    fi
    if [ -e "old_proto/.git" ]; then
        GIT_CKPT_PROTO=$(git -C old_proto rev-parse HEAD 2>/dev/null || echo "")
    fi
}

# ── 公共函数：回滚到检查点（discard 机制）──
rollback_to_checkpoint() {
    echo "  [Discard] 回滚到 git 检查点..."
    if [ -n "$GIT_CKPT_CLIENT" ] && [ -e "freelifeclient/.git" ]; then
        git -C freelifeclient checkout . 2>/dev/null || true
        git -C freelifeclient clean -fd 2>/dev/null || true
        local CURR=$(git -C freelifeclient rev-parse HEAD 2>/dev/null || echo "")
        if [ "$CURR" != "$GIT_CKPT_CLIENT" ]; then
            git -C freelifeclient reset --hard "$GIT_CKPT_CLIENT" 2>/dev/null || true
        fi
    fi
    if [ -n "$GIT_CKPT_SERVER" ] && [ -e "P1GoServer/.git" ]; then
        git -C P1GoServer checkout . 2>/dev/null || true
        git -C P1GoServer clean -fd 2>/dev/null || true
        local CURR=$(git -C P1GoServer rev-parse HEAD 2>/dev/null || echo "")
        if [ "$CURR" != "$GIT_CKPT_SERVER" ]; then
            git -C P1GoServer reset --hard "$GIT_CKPT_SERVER" 2>/dev/null || true
        fi
    fi
    if [ -n "$GIT_CKPT_PROTO" ] && [ -e "old_proto/.git" ]; then
        git -C old_proto checkout . 2>/dev/null || true
        git -C old_proto clean -fd 2>/dev/null || true
        local CURR=$(git -C old_proto rev-parse HEAD 2>/dev/null || echo "")
        if [ "$CURR" != "$GIT_CKPT_PROTO" ]; then
            git -C old_proto reset --hard "$GIT_CKPT_PROTO" 2>/dev/null || true
        fi
    fi
    echo "  [Discard] 回滚完成"
}

# ── 公共函数：记录结果到 results.tsv ──
record_result() {
    local TASK_ID="$1"
    local WAVE="$2"
    local ATTEMPT="$3"
    local ACTION="$4"
    local DURATION="$5"
    local COMPILE_OK="$6"
    local R_CRITICAL="$7"
    local R_HIGH="$8"
    local DECISION="$9"
    local REASON="${10}"
    echo -e "P4\t${TASK_ID}\t${WAVE}\t${ATTEMPT}\t${ACTION}\t${DURATION}\t${COMPILE_OK}\t${R_CRITICAL}\t${R_HIGH}\t${DECISION}\t${REASON}" >> "$RESULTS_FILE"
}

# ══════════════════════════════════════
# 波次并行基础设施
# ══════════════════════════════════════

# ── 构建依赖波次（拓扑排序） ──
# 输出：.waves 文件，每行 "task-NN:wave_number" 或 "task-NN:skip"
build_task_waves() {
    local tasks_dir="$1"
    local waves_file="${FEATURE_DIR}/.waves"
    > "$waves_file"

    local all_tasks=$(ls "$tasks_dir"/task-*.md 2>/dev/null | sort | while read f; do basename "$f" .md; done)
    local total=$(echo "$all_tasks" | wc -w)
    local assigned=0
    local wave_num=0

    while [ $assigned -lt $total ]; do
        local wave_tasks=""
        local progress=false

        for task in $all_tasks; do
            # 跳过已分配的
            grep -q "^${task}:" "$waves_file" 2>/dev/null && continue

            local task_file="${tasks_dir}/${task}.md"

            # 跳过已完成/已丢弃
            if grep -q "status: completed\|status: discarded" "$task_file" 2>/dev/null; then
                echo "${task}:skip" >> "$waves_file"
                assigned=$((assigned + 1))
                progress=true
                continue
            fi

            # 解析依赖（从 ## 依赖 到下一个 ## 之间）
            local dep_section=$(sed -n '/^## 依赖/,/^## /p' "$task_file" 2>/dev/null | grep -v "^## ")
            local deps=$(echo "$dep_section" | grep -oE 'task-[0-9]+' 2>/dev/null || true)

            # 检查所有依赖是否已满足（在更早的波次中或已跳过）
            local deps_met=true
            for dep in $deps; do
                local dep_wave=$(grep "^${dep}:" "$waves_file" 2>/dev/null | head -1 | cut -d: -f2)
                if [ -z "$dep_wave" ]; then
                    deps_met=false
                    break
                fi
                if [ "$dep_wave" != "skip" ] && [ "$dep_wave" -ge "$wave_num" ]; then
                    deps_met=false
                    break
                fi
            done

            if $deps_met; then
                wave_tasks="$wave_tasks $task"
                echo "${task}:${wave_num}" >> "$waves_file"
                assigned=$((assigned + 1))
                progress=true
            fi
        done

        if [ -z "$wave_tasks" ] && ! $progress; then
            echo "WARNING: 可能存在循环依赖，剩余任务强制归入波次 $wave_num" >&2
            for task in $all_tasks; do
                grep -q "^${task}:" "$waves_file" 2>/dev/null || {
                    echo "${task}:${wave_num}" >> "$waves_file"
                    assigned=$((assigned + 1))
                }
            done
        fi

        wave_num=$((wave_num + 1))
    done

    echo "$waves_file"
}

# ── 获取指定波次的任务列表 ──
get_wave_tasks() {
    local waves_file="$1"
    local wave_num="$2"
    grep ":${wave_num}$" "$waves_file" 2>/dev/null | cut -d: -f1 | tr '\n' ' '
}

# ── 获取波次总数 ──
count_waves() {
    local waves_file="$1"
    grep -v ":skip$" "$waves_file" 2>/dev/null | cut -d: -f2 | sort -nu | wc -l
}


# ── 在主工作目录执行单个任务（含完整编译验证 + 提交） ──
run_task_sequential() {
    local TASK_FILE="$1"
    local TASK_BASENAME=$(basename "$TASK_FILE" .md)

    local TASK_START=$(date +%s)
    local TASK_NAME=$(grep "^name:" "$TASK_FILE" | sed 's/^name: *//' || echo "$TASK_BASENAME")
    CURRENT_TASK="${TASK_BASENAME}: ${TASK_NAME}"
    update_dashboard

    echo "[${TASK_BASENAME}] 保存 git 检查点..."
    save_git_checkpoint

    TASK_WAVE="${WAVE_NUM:-0}" bash .claude/scripts/feature-develop-loop.sh "$VERSION_ID" "$FEATURE_NAME" --task "$TASK_FILE"
    local DEV_EXIT=$?
    aggregate_sub_metrics

    local TASK_END=$(date +%s)
    local TASK_DURATION=$((TASK_END - TASK_START))

    if [ $DEV_EXIT -ne 0 ]; then
        echo "WARNING: ${TASK_BASENAME} 开发异常 (exit=$DEV_EXIT)"

        # 记录失败教训（CHANGELOG 模式：防止后续任务重复踩坑）
        local LESSON_FILE="${PROJECT_ROOT}/${FEATURE_DIR}/failure-lessons.md"
        local ITER_LOG="${PROJECT_ROOT}/${FEATURE_DIR}/develop-iteration-log-${TASK_BASENAME}.md"
        if [ -f "$ITER_LOG" ]; then
            echo -e "\n## ${TASK_BASENAME} 失败 (exit=$DEV_EXIT)\n" >> "$LESSON_FILE"
            echo "时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LESSON_FILE"
            tail -20 "$ITER_LOG" >> "$LESSON_FILE" 2>/dev/null || true
            echo "---" >> "$LESSON_FILE"
        fi

        rollback_to_checkpoint
        record_result "$TASK_BASENAME" "${WAVE_NUM:-0}" "1" "develop" "$TASK_DURATION" "false" "0" "0" "discard" "开发异常 exit=$DEV_EXIT"
        echo "| ${TASK_BASENAME} | 丢弃(Discard) | ${TASK_DURATION}s | exit=$DEV_EXIT, 已回滚 |" >> "$WORK_LOG"
        DISCARDED_TASKS=$((DISCARDED_TASKS + 1))
        sed -i "s/status: pending/status: discarded/" "$TASK_FILE" 2>/dev/null || true
        return 1
    fi

    # Keep：提交到 Git
    echo "[${TASK_BASENAME}] 提交变更到 Git（Keep）..."

    local COMMIT_PROMPT="请执行以下步骤提交代码：

1. 运行 git status 查看变更
2. 运行 git diff 查看具体修改
3. 如果有变更，用 git add 逐个添加相关文件（禁止 git add . 或 git add -A）
   - 排除 .env、credentials 等敏感文件
   - 排除 Docs/ 目录下的日志文件（develop-iteration-log.md、develop-review-report.md 等临时文件）
   - 包含所有代码文件变更（.go、.cs、.proto、.json 等）
   - 包含 plan 和 task 文件的变更
4. 用以下格式提交：

git commit -m \"\$(cat <<'COMMITEOF'
feat(${FEATURE_NAME}): ${TASK_NAME}

任务 ${TASK_BASENAME}：${TASK_NAME}
版本：${VERSION_ID}

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
COMMITEOF
)\"

5. 如果没有变更可提交，直接输出 'NO_CHANGES'
6. 如果 commit 成功，输出 'COMMIT_SUCCESS'"

    local COMMIT_RESULT=$(run_claude_capture "提交 ${TASK_BASENAME}" "$COMMIT_PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" | tail -10)
    echo "$COMMIT_RESULT"

    if echo "$COMMIT_RESULT" | grep -q "COMMIT_SUCCESS"; then
        record_result "$TASK_BASENAME" "${WAVE_NUM:-0}" "1" "develop+commit" "$TASK_DURATION" "true" "0" "0" "keep" "质量达标"
        echo "| ${TASK_BASENAME} | Keep+已提交 | ${TASK_DURATION}s | ${TASK_NAME} |" >> "$WORK_LOG"
    elif echo "$COMMIT_RESULT" | grep -q "NO_CHANGES"; then
        record_result "$TASK_BASENAME" "${WAVE_NUM:-0}" "1" "develop" "$TASK_DURATION" "true" "0" "0" "keep" "无变更"
        echo "| ${TASK_BASENAME} | Keep(无变更) | ${TASK_DURATION}s | ${TASK_NAME} |" >> "$WORK_LOG"
    else
        record_result "$TASK_BASENAME" "${WAVE_NUM:-0}" "1" "develop+commit" "$TASK_DURATION" "true" "0" "0" "keep" "提交异常"
        echo "| ${TASK_BASENAME} | Keep(提交异常) | ${TASK_DURATION}s | ${TASK_NAME} |" >> "$WORK_LOG"
    fi

    sed -i "s/status: pending/status: completed/" "$TASK_FILE" 2>/dev/null || true
    COMPLETED_TASKS=$((COMPLETED_TASKS + 1))
    echo "[${TASK_BASENAME}] Keep (${TASK_DURATION}s)"
    return 0
}

# ══════════════════════════════════════
# 波次执行主逻辑
# ══════════════════════════════════════

echo "[依赖分析] 构建任务波次..."
WAVES_FILE=$(build_task_waves "$TASKS_DIR")
WAVE_TOTAL=$(count_waves "$WAVES_FILE")
echo "[依赖分析] 共 ${WAVE_TOTAL} 个波次"

# 打印波次分配
echo ""
echo "波次分配:"
for wn in $(seq 0 $((WAVE_TOTAL - 1))); do
    wtasks=$(get_wave_tasks "$WAVES_FILE" "$wn")
    echo "  Wave ${wn}: ${wtasks}"
done
echo ""

for WAVE_NUM in $(seq 0 $((WAVE_TOTAL - 1))); do
    WAVE_TASKS=$(get_wave_tasks "$WAVES_FILE" "$WAVE_NUM")
    WAVE_TASK_COUNT=$(echo "$WAVE_TASKS" | wc -w)

    CURRENT_STAGE="阶段四/Wave ${WAVE_NUM}/${WAVE_TOTAL}"
    now=$(date +%s)
    elapsed=$((now - GLOBAL_START_TIME))
    total_all_tokens=$((TOTAL_INPUT_TOKENS + TOTAL_OUTPUT_TOKENS + TOTAL_CACHE_READ_TOKENS + TOTAL_CACHE_WRITE_TOKENS))
    echo ""
    echo "══════════════════════════════════════════════════════════════"
    echo "  Wave ${WAVE_NUM}/${WAVE_TOTAL}: ${WAVE_TASKS} (${WAVE_TASK_COUNT} 个任务)"
    echo "──────────────────────────────────────────────────────────────"
    echo "  ⏱ $(format_duration $elapsed) │ 🤖 ${TOTAL_AGENTS} agents │ 🔤 $(format_number $total_all_tokens) tokens │ 💰 $(format_cost "$TOTAL_COST_USD")"
    echo "  📋 任务: Keep=${COMPLETED_TASKS} Discard=${DISCARDED_TASKS} / ${TOTAL_TASKS}"
    echo "══════════════════════════════════════════════════════════════"
    update_dashboard

    if [ "$WAVE_TASK_COUNT" -eq 0 ]; then
        continue
    fi

    if [ "$WAVE_TASK_COUNT" -eq 1 ]; then
        # ── 单任务波次：直接在主工作目录执行（零额外开销） ──
        TASK_ID=$(echo "$WAVE_TASKS" | tr -d ' ')
        TASK_FILE="$TASKS_DIR/${TASK_ID}.md"

        if grep -q "status: completed\|status: discarded" "$TASK_FILE" 2>/dev/null; then
            echo "── ${TASK_ID} 已处理，跳过 ──"
            grep -q "status: completed" "$TASK_FILE" && COMPLETED_TASKS=$((COMPLETED_TASKS + 1))
            grep -q "status: discarded" "$TASK_FILE" && DISCARDED_TASKS=$((DISCARDED_TASKS + 1))
            continue
        fi

        echo "[Wave ${WAVE_NUM}] 单任务，主工作目录执行: ${TASK_ID}"
        run_task_sequential "$TASK_FILE"

    else
        # ── 多任务波次：串行执行 ──
        echo "[Wave ${WAVE_NUM}] 多任务串行: ${WAVE_TASKS}"

        for TASK_ID in $WAVE_TASKS; do
            TASK_FILE="$TASKS_DIR/${TASK_ID}.md"
            if grep -q "status: completed\|status: discarded" "$TASK_FILE" 2>/dev/null; then
                grep -q "status: completed" "$TASK_FILE" && COMPLETED_TASKS=$((COMPLETED_TASKS + 1))
                grep -q "status: discarded" "$TASK_FILE" && DISCARDED_TASKS=$((DISCARDED_TASKS + 1))
                continue
            fi
            echo "[Wave ${WAVE_NUM}] 串行执行: ${TASK_ID}"
            run_task_sequential "$TASK_FILE"
        done
    fi
    # ── 早期卡死检测：检查 stuck signal 并提前触发 Meta-Review ──
    STUCK_SIGNALS=$(ls "${FEATURE_DIR}/stuck-signal-"*.txt 2>/dev/null)
    if [ -n "$STUCK_SIGNALS" ]; then
        echo "  ⚠️  检测到卡死信号，提前触发 Meta-Review："
        for sf in $STUCK_SIGNALS; do
            echo "    $(cat "$sf")"
        done
        rm -f "${FEATURE_DIR}/stuck-signal-"*.txt
    fi

    # 波次结束后执行 Meta-Review（分析反复错误、持久化改进规则）
    run_meta_review

    # 波次间客户端冒烟测试（仅涉客户端变更时）
    WAVE_HAS_CS_CHANGES=false
    if [ "$COMPLETED_TASKS" -gt 0 ] && [ -d "freelifeclient" ]; then
        CS_DIFF=$(git -C freelifeclient diff --name-only "HEAD~${COMPLETED_TASKS}" HEAD -- '*.cs' 2>/dev/null | head -5)
        if [ -n "$CS_DIFF" ]; then
            WAVE_HAS_CS_CHANGES=true
        fi
    fi
    if [ "$WAVE_HAS_CS_CHANGES" = true ]; then
        echo ""
        echo "[Wave ${WAVE_NUM}] 客户端冒烟测试（.cs 变更检测到）..."
        SMOKE_START=$(date +%s)
        SMOKE_PROMPT="执行客户端编译冒烟检查：
1. 调用 console-get-logs 检查 Unity 编译是否有 CS 错误
2. 如有错误，只报告不修复
输出格式：SMOKE_PASS 或 SMOKE_FAIL + 错误摘要"
        SMOKE_RESULT=$(timeout 60 bash -c "run_claude '波次冒烟' '$SMOKE_PROMPT' --allowedTools 'Read,Grep,Glob,Agent,ToolSearch' | tail -5" 2>/dev/null || echo "SMOKE_TIMEOUT")
        SMOKE_END=$(date +%s)
        SMOKE_DURATION=$((SMOKE_END - SMOKE_START))
        echo "| Wave${WAVE_NUM}冒烟 | ${SMOKE_RESULT} | ${SMOKE_DURATION}s |" >> "$WORK_LOG"
        if echo "$SMOKE_RESULT" | grep -q "SMOKE_FAIL"; then
            echo "WARNING: 波次 ${WAVE_NUM} 客户端编译冒烟失败"
        fi
    fi
done

STAGE4_END=$(date +%s)
STAGE4_DURATION=$((STAGE4_END - STAGE4_START))
echo "| 任务开发(波次并行) | 完成 | ${STAGE4_DURATION}s | Keep=${COMPLETED_TASKS} Discard=${DISCARDED_TASKS} Waves=${WAVE_TOTAL} agents=${TOTAL_AGENTS} cost=$(format_cost "$TOTAL_COST_USD") |" >> "$WORK_LOG"

# ══════════════════════════════════════
# 阶段四-B：Unity MCP 验收测试
# ══════════════════════════════════════

STAGE4B_START=$(date +%s)

# 仅当有客户端改动且 plan 中含验收测试方案时执行
HAS_CLIENT_CHANGES=false
if [ "$COMPLETED_TASKS" -gt 0 ]; then
    # 检查是否有 .cs 文件变更
    if git -C freelifeclient diff --name-only HEAD~${COMPLETED_TASKS} HEAD 2>/dev/null | grep -q '\.cs$'; then
        HAS_CLIENT_CHANGES=true
    fi
fi

# 检查 plan 中是否定义了验收测试用例 [TC-XXX]
HAS_TEST_CASES=false
if grep -rq '\[TC-[0-9]' "${FEATURE_DIR}/plan"* 2>/dev/null || grep -rq '\[TC-[0-9]' "${FEATURE_DIR}/plan/" 2>/dev/null; then
    HAS_TEST_CASES=true
fi

if [ "$HAS_CLIENT_CHANGES" = true ]; then
    print_stage_header "阶段四-B：Unity MCP 验收测试"

    MCP_VERIFY_REPORT="${FEATURE_DIR}/mcp-verify-report.md"

    if [ "$HAS_TEST_CASES" = true ]; then
        # 有 [TC-XXX] → 完整 MCP 验收（执行 plan 中定义的全部测试用例）
        MCP_VERIFY_PROMPT="你是 Unity MCP 验收测试执行专家。

## 任务
读取 ${FEATURE_DIR}/ 下的 plan.json（和 plan/ 子目录），找到所有 [TC-XXX] 验收测试用例，逐一执行。

## 执行流程
1. 环境准备：
   - editor-application-get-state 确认 Unity Editor 状态（MCP 不通则 python3 scripts/mcp_call.py editor-application-get-state 测试）
   - 如未在 Play 模式 → editor-application-set-state 进入 Play 模式
   - 如未登录 → 读取 .claude/skills/unity-login/SKILL.md 按流程登录
2. 逐用例执行每个 [TC-XXX] 的操作步骤
3. 每步验证后截图（screenshot-game-view）+ 记录结果
4. 全部执行完后生成报告写入 ${MCP_VERIFY_REPORT}
5. 报告末尾追加元数据：<!-- mcp-verify: passed=X failed=Y skipped=Z -->

## 失败处理
- 用例失败时截图+日志（console-get-logs）作为证据，不中断后续用例
- MCP 断连时执行 python3 scripts/mcp_call.py editor-application-get-state 检测，不通则 powershell scripts/unity-restart.ps1 恢复
- 环境准备失败 3 次后标记所有用例为 skipped 并退出"
    else
        # 无 [TC-XXX] 但有客户端改动 → 基础 MCP 验收（编译+登录+截图）
        echo "Plan 中无 [TC-XXX] 验收用例，但有客户端改动，执行基础 MCP 验收..."
        MCP_VERIFY_PROMPT="你是 Unity MCP 基础验收测试执行专家。

## 任务
本功能有客户端 C# 改动但 plan 中未定义 [TC-XXX] 验收用例。执行基础运行时验收，确保客户端改动不会导致崩溃或编译错误。

## 基础验收流程
1. 环境准备：
   - editor-application-get-state 确认 Unity Editor 状态（MCP 不通则 python3 scripts/mcp_call.py editor-application-get-state 测试）
   - console-get-logs 检查是否有 CS 编译错误（Error 级别），有则记录 FAIL
2. 进入 Play 模式：
   - editor-application-set-state 进入 Play 模式
   - 等待 5 秒稳定
3. 登录验证：
   - 读取 .claude/skills/unity-login/SKILL.md 按流程登录游戏
   - 等待登录完成（10 秒超时）
4. 基础截图：
   - screenshot-game-view 截取主界面截图
   - console-get-logs 检查 Error 级别日志
5. 退出 Play 模式
6. 生成报告写入 ${MCP_VERIFY_REPORT}，包含：
   - 编译状态（PASS/FAIL）
   - 登录状态（PASS/FAIL/SKIP）
   - 运行时错误数量
   - 截图路径
7. 报告末尾追加元数据：<!-- mcp-verify: passed=X failed=Y skipped=Z -->

## 失败处理
- MCP 断连时执行 python3 scripts/mcp_call.py editor-application-get-state 检测，不通则 powershell scripts/unity-restart.ps1 恢复
- 环境准备失败 3 次后标记所有检查项为 skipped 并退出"
    fi

    MCP_EXIT=0
    run_claude "MCP验收测试" "$MCP_VERIFY_PROMPT" --max-turns 60 | tail -20 || MCP_EXIT=$?

    # 解析验收结果
    MCP_PASSED=0; MCP_FAILED=0; MCP_SKIPPED=0
    if [ -f "$MCP_VERIFY_REPORT" ]; then
        MCP_LINE=$(grep -o 'mcp-verify: passed=[0-9]* failed=[0-9]* skipped=[0-9]*' "$MCP_VERIFY_REPORT" 2>/dev/null | tail -1 || echo "")
        if [ -n "$MCP_LINE" ]; then
            MCP_PASSED=$(echo "$MCP_LINE" | sed 's/.*passed=\([0-9]*\).*/\1/')
            MCP_FAILED=$(echo "$MCP_LINE" | sed 's/.*failed=\([0-9]*\).*/\1/')
            MCP_SKIPPED=$(echo "$MCP_LINE" | sed 's/.*skipped=\([0-9]*\).*/\1/')
        fi
    fi

    STAGE4B_END=$(date +%s)
    STAGE4B_DURATION=$((STAGE4B_END - STAGE4B_START))
    echo "MCP 验收结果: Passed=$MCP_PASSED Failed=$MCP_FAILED Skipped=$MCP_SKIPPED"
    echo "| MCP验收测试 | 完成 | ${STAGE4B_DURATION}s | passed=$MCP_PASSED failed=$MCP_FAILED skipped=$MCP_SKIPPED |" >> "$WORK_LOG"

    # 有失败用例时尝试修复（最多 2 轮）
    MCP_FIX_ROUND=0
    while [ "$MCP_FAILED" -gt 0 ] && [ "$MCP_FIX_ROUND" -lt 2 ]; do
        MCP_FIX_ROUND=$((MCP_FIX_ROUND + 1))
        echo "MCP 验收有 $MCP_FAILED 个失败用例，修复轮次 $MCP_FIX_ROUND/2..."

        MCP_FIX_PROMPT="读取 ${MCP_VERIFY_REPORT}，找到所有失败的测试用例。
分析失败原因，修复对应代码。修复后重新编译（Server: cd P1GoServer && make build，Client: 等待 Unity 编译）。
修复完成后，重新执行失败的用例（不需要重跑已通过的），更新 ${MCP_VERIFY_REPORT} 并追加新的元数据行。"

        run_claude "MCP修复R${MCP_FIX_ROUND}" "$MCP_FIX_PROMPT" --max-turns 40 | tail -10 || true

        # 重新解析
        if [ -f "$MCP_VERIFY_REPORT" ]; then
            MCP_LINE=$(grep -o 'mcp-verify: passed=[0-9]* failed=[0-9]* skipped=[0-9]*' "$MCP_VERIFY_REPORT" 2>/dev/null | tail -1 || echo "")
            if [ -n "$MCP_LINE" ]; then
                MCP_FAILED=$(echo "$MCP_LINE" | sed 's/.*failed=\([0-9]*\).*/\1/')
            fi
        fi
    done

    if [ "$MCP_FAILED" -gt 0 ]; then
        echo "WARNING: MCP 验收仍有 $MCP_FAILED 个失败用例（2 轮修复未解决），登记到 docs/bugs/ 并启动 dev-debug 修复"

        # 生成遗留 bug 映射文件
        RESIDUAL_FILE="${FEATURE_DIR}/stage4b-residual-bugs.md"
        echo "# Stage 4-B MCP 验收遗留问题" > "$RESIDUAL_FILE"
        echo "" >> "$RESIDUAL_FILE"
        echo "以下测试用例在 2 轮修复后仍未通过：" >> "$RESIDUAL_FILE"
        echo "" >> "$RESIDUAL_FILE"
        # 从 MCP 验收输出中提取失败的 TC（由验收进程输出 failed_tcs=TC-001,TC-003 格式）
        echo "$MCP_RESULT" | grep -oP 'failed_tcs=\K[^\s]+' | tr ',' '\n' | while read -r tc; do
            echo "- [ ] $tc" >> "$RESIDUAL_FILE"
        done

        # 启动独立进程登记 + 修复
        BUGFIX_PROMPT="读取 ${RESIDUAL_FILE}，对每个未通过的测试用例：
1. 用 bug:report ${VERSION_ID} ${FEATURE_NAME} 登记到 docs/bugs/
2. 用 /dev-debug --mode acceptance --caller direct 逐个修复
3. 修复后更新 ${RESIDUAL_FILE} 中对应条目为 [x]，并更新 docs/bugs/ 归档状态
上下文：功能方案 ${FEATURE_DIR}/idea.md，Plan ${FEATURE_DIR}/plan.json"
        run_claude "Stage4B-Bug修复" "$BUGFIX_PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" | tail -10
        echo "Stage 4-B 遗留 bug 修复完成"
    fi
else
    echo "无客户端改动，跳过 MCP 验收测试"
    echo "| MCP验收测试 | 跳过 | 0s | 无客户端改动 |" >> "$WORK_LOG"
fi

# ══════════════════════════════════════
# 阶段五：生成模块文档
# ══════════════════════════════════════

STAGE5_START=$(date +%s)
print_stage_header "阶段五：生成模块文档 (docs/knowledge/Business)"

# 仅在有成功完成的任务时才生成文档
if [ "$COMPLETED_TASKS" -gt 0 ]; then
    DOC_PROMPT="你是一名资深游戏引擎文档工程师。请为刚完成的功能生成/更新模块文档，归档到 docs/knowledge/ 目录下。

请读取以下文件建立上下文：
1. ${FEATURE_DIR}/feature.json — 功能需求（JSON 格式）
2. ${FEATURE_DIR}/plan.json — 技术方案（JSON 格式）
3. 浏览 ${TASKS_DIR}/ 下的任务文件了解实现范围
4. 阅读实际修改的代码文件，理解最终实现

然后执行以下步骤：

### 步骤一：确定模块归属
- 根据功能涉及的领域，确定归属到 docs/knowledge/ 下的哪个模块目录
- 查看 docs/knowledge/ 已有的目录列表，优先归入已有模块
- 如果是全新领域，创建新的模块目录（目录名用 PascalCase 英文，如 Weapon、Vehicle、Town）
- 如果功能横跨多个模块，在主模块写完整文档，其他相关模块添加交叉引用

### 步骤二：生成/更新文档
- 如果该模块目录下已有文档，阅读现有文档，以**追加或更新**方式整合新内容，不要覆盖已有信息
- 如果是全新模块，创建主文档（中文命名，如 XX系统.md）

文档格式参考 docs/knowledge/Weapon/武器系统.md 的风格：

\`\`\`markdown
# {系统名称}

## 概述
一段话描述系统目标和核心设计思路。

## 架构总览
用文本图或列表描述核心组件关系。

## 核心流程
描述关键业务流程（如创建→使用→销毁）。

## 关键文件索引

### 客户端
| 职责 | 文件路径 |
|------|----------|
| ... | ... |

### 服务端
| 职责 | 文件路径 |
|------|----------|
| ... | ... |

### 配置
| 配置 | 路径 | 说明 |
|------|------|------|
| ... | ... | ... |

## 网络协议
列出相关的 Proto 消息及其用途。

## 注意事项
开发时需要注意的坑和约束。
\`\`\`

规则：
- 文档内容必须基于实际代码，不要编造不存在的文件路径或类名
- 重点记录架构决策和关键流程，不要逐行翻译代码
- 文件路径索引要准确，以实际代码路径为准
- 注释和文档用中文
- 如果更新已有文档，在修改处标注 [${VERSION_ID}新增] 方便追溯
- 直接写文件，不要向用户提问"

    run_claude "生成模块文档" "$DOC_PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" | tail -20
    DOC_EXIT=$?

    STAGE5_END=$(date +%s)
    STAGE5_DURATION=$((STAGE5_END - STAGE5_START))

    if [ $DOC_EXIT -eq 0 ]; then
        echo "| 生成模块文档 | 完成 | ${STAGE5_DURATION}s | docs/knowledge/ |" >> "$WORK_LOG"
        echo "模块文档生成完成 (${STAGE5_DURATION}s)"

        # 提交文档到 Git
        DOC_COMMIT_PROMPT="请执行以下步骤提交文档变更：

1. 运行 git status 查看 docs/knowledge/ 下的变更
2. 如果有变更，用 git add 添加 docs/knowledge/ 下的所有变更文件
3. 提交：

git commit -m \"\$(cat <<'COMMITEOF'
docs(${FEATURE_NAME}): 更新模块文档

将 ${VERSION_ID}/${FEATURE_NAME} 的实现总结归档到 docs/knowledge/

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
COMMITEOF
)\"

4. 如果没有变更，输出 'NO_CHANGES'
5. 如果 commit 成功，输出 'COMMIT_SUCCESS'"

        DOC_COMMIT_RESULT=$(run_claude_capture "提交文档" "$DOC_COMMIT_PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" | tail -10)
        echo "$DOC_COMMIT_RESULT"
    else
        echo "WARNING: 模块文档生成异常 (exit=$DOC_EXIT)"
        echo "| 生成模块文档 | 异常 | ${STAGE5_DURATION:-0}s | exit=$DOC_EXIT |" >> "$WORK_LOG"
    fi
else
    echo "无成功完成的任务，跳过文档生成"
    echo "| 生成模块文档 | 跳过 | 0s | 无成功任务 |" >> "$WORK_LOG"
fi

# ══════════════════════════════════════
# 阶段六：推送到远程仓库
# ══════════════════════════════════════

STAGE6_START=$(date +%s)
print_stage_header "阶段六：推送到远程仓库"

if [ "$COMPLETED_TASKS" -gt 0 ]; then
    PUSH_PROMPT="执行 /git-commit-push all 完成提交和推送。

该 skill 会自动完成：噪声文件过滤 → 按逻辑变更原子化拆分 commit → 生成规范 commit message → 提交并推送三个仓库（freelifeclient/P1GoServer/old_proto）。

注意：
- 当前是非交互模式，skill 中的用户确认步骤自动跳过（视为默认确认）
- 遵循 git-commit-push 的所有规范（原子化提交、噪声过滤、commit message 风格）
- 禁止 git push --force"

    PUSH_RESULT=$(run_claude_capture "提交推送仓库" "$PUSH_PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" | tail -20)
    echo "$PUSH_RESULT"

    STAGE6_END=$(date +%s)
    STAGE6_DURATION=$((STAGE6_END - STAGE6_START))
    echo "| 推送远程仓库 | 完成 | ${STAGE6_DURATION}s | freelifeclient/P1GoServer/Proto |" >> "$WORK_LOG"
    echo "推送完成 (${STAGE6_DURATION}s)"
else
    echo "无成功完成的任务，跳过推送"
    echo "| 推送远程仓库 | 跳过 | 0s | 无成功任务 |" >> "$WORK_LOG"
fi

# ══════════════════════════════════════
# 生成引擎结果摘要（供 new-feature Step 5 统一读取）
# ══════════════════════════════════════

COMPILE_STATUS="PASS"
if [ -f "$RESULTS_FILE" ]; then
    if grep -q "false" <(awk -F'\t' '{print $6}' "$RESULTS_FILE") 2>/dev/null; then
        COMPILE_STATUS="FAIL"
    fi
fi

cat > "${FEATURE_DIR}/engine-result.md" << ENGEOF
## 引擎执行结果

- 引擎: auto-work
- 总任务数: ${TOTAL_TASKS:-0}
- Keep: ${COMPLETED_TASKS:-0}, Discard: ${DISCARDED_TASKS:-0}
- 编译状态: ${COMPILE_STATUS}
- 运行时验证: $(if [ "${MCP_PASSED:-0}" -gt 0 ] || [ "${MCP_FAILED:-0}" -gt 0 ]; then echo "Stage4B passed=${MCP_PASSED:-0} failed=${MCP_FAILED:-0} skipped=${MCP_SKIPPED:-0}"; else echo "SKIPPED（无客户端改动或无 TC 用例）"; fi)
- 推送仓库: freelifeclient, P1GoServer, old_proto
- 详细日志: ${FEATURE_DIR}/results.tsv
ENGEOF

echo "引擎结果摘要已生成: ${FEATURE_DIR}/engine-result.md"

# ══════════════════════════════════════
# 阶段七：验收闭环（Step 5）
# ══════════════════════════════════════

if [ "${COMPLETED_TASKS:-0}" -gt 0 ] && [ -f "$IDEA_FILE" ] && grep -q '### 验收标准' "$IDEA_FILE" 2>/dev/null; then
    print_stage_header "阶段七：验收闭环"
    STAGE7_START=$(date +%s)

    echo "启动 acceptance-loop.sh..."
    bash .claude/scripts/acceptance-loop.sh "$VERSION_ID" "$FEATURE_NAME" 5
    AC_EXIT=$?
    aggregate_sub_metrics

    STAGE7_END=$(date +%s)
    STAGE7_DURATION=$((STAGE7_END - STAGE7_START))

    if [ $AC_EXIT -eq 0 ]; then
        echo "| 验收闭环 | 完成 | ${STAGE7_DURATION}s | ${FEATURE_DIR}/acceptance-report.md |" >> "$WORK_LOG"
        echo "验收完成 (${STAGE7_DURATION}s)"
    else
        echo "| 验收闭环 | 异常 | ${STAGE7_DURATION}s | exit=$AC_EXIT |" >> "$WORK_LOG"
        echo "WARNING: 验收闭环异常 (exit=$AC_EXIT)，请检查 ${FEATURE_DIR}/acceptance-report.md"
    fi
else
    if [ "${COMPLETED_TASKS:-0}" -eq 0 ]; then
        echo "无成功任务，跳过验收"
    else
        echo "idea.md 无验收标准，跳过验收闭环"
    fi
    echo "| 验收闭环 | 跳过 | 0s | - |" >> "$WORK_LOG"
fi

# ══════════════════════════════════════
# 总结
# ══════════════════════════════════════

TOTAL_END=$(date +%s)
TOTAL_DURATION=$((TOTAL_END - GLOBAL_START_TIME))
TOTAL_ALL_TOKENS=$((TOTAL_INPUT_TOKENS + TOTAL_OUTPUT_TOKENS + TOTAL_CACHE_READ_TOKENS + TOTAL_CACHE_WRITE_TOKENS))

CURRENT_STAGE="完成"
CURRENT_TASK=""
update_dashboard

cat >> "$WORK_LOG" << EOF

## 总结
- **总耗时**: $(format_duration $TOTAL_DURATION) (${TOTAL_DURATION}s)
- **完成时间**: $(date '+%Y-%m-%d %H:%M:%S')
- **执行模式**: 波次串行
- **任务统计**: 总计 ${TOTAL_TASKS} 个，Keep ${COMPLETED_TASKS} 个，Discard ${DISCARDED_TASKS} 个
- **波次数**: ${WAVE_TOTAL:-0}

### 资源消耗
- **Agent 总数**: ${TOTAL_AGENTS}
- **Token 消耗**: $(format_number $TOTAL_ALL_TOKENS) (输入: $(format_number $TOTAL_INPUT_TOKENS), 输出: $(format_number $TOTAL_OUTPUT_TOKENS), 缓存读: $(format_number $TOTAL_CACHE_READ_TOKENS), 缓存写: $(format_number $TOTAL_CACHE_WRITE_TOKENS))
- **总费用**: $(format_cost "$TOTAL_COST_USD")
- **API 总耗时**: $(format_duration $((TOTAL_API_DURATION_MS / 1000)))

### 产出文件
- 需求文档: ${FEATURE_DIR}/feature.json
- 技术方案: ${FEATURE_DIR}/plan.json
- 任务清单: ${TASKS_DIR}/README.md
- 结果追踪: ${FEATURE_DIR}/results.tsv
- 开发日志: ${FEATURE_DIR}/develop-log.md
- Plan 迭代日志: ${FEATURE_DIR}/plan-iteration-log.md
- Develop 迭代日志: ${FEATURE_DIR}/develop-iteration-log-*.md
- 模块文档: docs/knowledge/{模块}/
- 实时仪表盘: ${DASHBOARD_FILE}
EOF

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  Auto-Work 全流程完成"
echo "══════════════════════════════════════════════════════════════"
echo "  功能: ${VERSION_ID}/${FEATURE_NAME}"
echo "  总耗时: $(format_duration $TOTAL_DURATION)"
echo "  波次: ${WAVE_TOTAL:-0}"
echo "  任务: Keep=${COMPLETED_TASKS} Discard=${DISCARDED_TASKS} / 总计=${TOTAL_TASKS}"
echo "──────────────────────────────────────────────────────────────"
echo "  🤖 Agent 总数:  ${TOTAL_AGENTS}"
echo "  🔤 Token 总计:  $(format_number $TOTAL_ALL_TOKENS)"
echo "     输入:        $(format_number $TOTAL_INPUT_TOKENS)"
echo "     输出:        $(format_number $TOTAL_OUTPUT_TOKENS)"
echo "     缓存读取:    $(format_number $TOTAL_CACHE_READ_TOKENS)"
echo "     缓存写入:    $(format_number $TOTAL_CACHE_WRITE_TOKENS)"
echo "  💰 总费用:      $(format_cost "$TOTAL_COST_USD")"
echo "  ⏱  API 耗时:   $(format_duration $((TOTAL_API_DURATION_MS / 1000)))"
echo "──────────────────────────────────────────────────────────────"
echo "  工作目录: ${FEATURE_DIR}/"
echo "  总日志: ${WORK_LOG}"
echo "══════════════════════════════════════════════════════════════"
