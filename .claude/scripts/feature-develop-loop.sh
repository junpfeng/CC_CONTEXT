#!/bin/bash
# feature-develop-loop.sh
# 原子化开发迭代循环：编码 → 机械验证(编译) → 主观评估(Review) → keep/discard
# 每轮启动新 Claude 实例防止上下文污染
#
# 原子化原则：
# - Fail-fast：编译（机械、便宜）在前，Review（AI、贵）在后
# - 质量棘轮：修复后质量不升反降 → discard 修复，回滚到修复前
# - 结果追踪：每轮结果记录到 results.tsv
#
# 用法: bash .claude/scripts/feature-develop-loop.sh <version_id> <feature_name> [engine_name] [max_rounds]
#        bash .claude/scripts/feature-develop-loop.sh <version_id> <feature_name> --task <task_file> [max_rounds]
# 示例: bash .claude/scripts/feature-develop-loop.sh v0.0.2-mvp login-system
# 示例: bash .claude/scripts/feature-develop-loop.sh v0.0.2-mvp login-system 08-frontend
# 示例: bash .claude/scripts/feature-develop-loop.sh v0.0.2-mvp login-system --task docs/version/v0.0.3/weapon/tasks/task-01.md
#
# 前置条件:
#   - claude CLI 可用
#   - 从项目根目录运行

set -euo pipefail

# ══════════════════════════════════════
# 指标采集（写入 AUTO_WORK_METRICS_FILE 供父进程汇总）
# ══════════════════════════════════════

# 包装 claude -p 调用，用 --output-format json 提取指标
# 用法: claude_tracked <description> <prompt> [extra_args...]
# 输出: 文本结果到 stdout
claude_tracked() {
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

        # 写入共享指标文件（如果父进程设置了）
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

# 包装版：用于需要捕获输出的场景（超时版本）
claude_tracked_timeout() {
    local timeout_s="$1"
    shift
    local desc="$1"
    shift
    local prompt="$1"
    shift
    local extra_args=("$@")

    local tmp_json
    tmp_json=$(mktemp)

    timeout "$timeout_s" claude -p "$prompt" --output-format json "${extra_args[@]}" > "$tmp_json" 2>/dev/null
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

VERSION_ID="${1:?用法: $0 <version_id> <feature_name> [--task <task_file>] [engine_name] [max_rounds]}"
FEATURE_NAME="${2:?用法: $0 <version_id> <feature_name> [--task <task_file>] [engine_name] [max_rounds]}"

# 解析参数：支持 --task <file>、engine_name、max_rounds
ENGINE_NAME=""
MAX_ROUNDS=8
TASK_FILE=""

shift 2
while [ $# -gt 0 ]; do
    case "$1" in
        --task)
            TASK_FILE="${2:?--task 需要指定任务文件路径}"
            shift 2
            ;;
        *)
            if [[ "$1" =~ ^[0-9]+$ ]]; then
                MAX_ROUNDS="$1"
            else
                ENGINE_NAME="$1"
            fi
            shift
            ;;
    esac
done

FEATURE_DIR="docs/version/${VERSION_ID}/${FEATURE_NAME}"
PLAN_FILE="${FEATURE_DIR}/plan.json"

# 根据是否有 task 文件区分日志文件名，避免多任务间日志覆盖
if [ -n "$TASK_FILE" ]; then
    TASK_BASENAME=$(basename "$TASK_FILE" .md)
    LOG_FILE="${FEATURE_DIR}/develop-iteration-log-${TASK_BASENAME}.md"
    REVIEW_FILE="${FEATURE_DIR}/develop-review-report-${TASK_BASENAME}.md"
    KNOWN_ISSUES_FILE="${FEATURE_DIR}/develop-known-issues-${TASK_BASENAME}.md"
else
    LOG_FILE="${FEATURE_DIR}/develop-iteration-log.md"
    REVIEW_FILE="${FEATURE_DIR}/develop-review-report.md"
    KNOWN_ISSUES_FILE="${FEATURE_DIR}/develop-known-issues.md"
fi

# 构建 developing 参数
DEVELOP_ARGS="${VERSION_ID} ${FEATURE_NAME}"
if [ -n "$ENGINE_NAME" ]; then
    DEVELOP_ARGS="${DEVELOP_ARGS} ${ENGINE_NAME}"
fi

# 校验
# 优先 plan.json，兼容旧的 plan.md
if [ ! -f "$PLAN_FILE" ]; then
    if [ -f "${FEATURE_DIR}/plan.md" ]; then
        PLAN_FILE="${FEATURE_DIR}/plan.md"
        echo "NOTICE: 使用旧格式 plan.md（建议迁移到 plan.json）"
    else
        echo "ERROR: ${PLAN_FILE} not found (先运行 feature-plan 生成 plan)"
        exit 1
    fi
fi

if [ -n "$TASK_FILE" ] && [ ! -f "$TASK_FILE" ]; then
    echo "ERROR: 任务文件不存在: ${TASK_FILE}"
    exit 1
fi

# 构建任务约束提示（如果有 task 文件）
TASK_SCOPE_PROMPT=""
if [ -n "$TASK_FILE" ]; then
    TASK_CONTENT=$(cat "$TASK_FILE")
    TASK_SCOPE_PROMPT="
【重要：本次只实现以下任务的范围】
任务文件：${TASK_FILE}
任务内容：
${TASK_CONTENT}

你只需要实现上述任务中列出的文件和功能，不要实现 plan 中其他任务的内容。
完成后确保代码能独立编译通过（不会有悬空引用或缺失依赖）。"

    # 注入前序失败教训（只保留最近 3 轮，截断到 3KB 防止 prompt 膨胀）
    LESSON_FILE="${FEATURE_DIR}/failure-lessons.md"
    if [ -f "$LESSON_FILE" ]; then
        LESSON_CONTENT=$(tail -30 "$LESSON_FILE" 2>/dev/null | cut -c1-3072 || true)
        if [ -n "$LESSON_CONTENT" ]; then
            TASK_SCOPE_PROMPT="${TASK_SCOPE_PROMPT}

【前序任务的失败教训（最近 3 轮），务必避免重复相同错误】
${LESSON_CONTENT}"
        fi
    fi
fi

# ══════════════════════════════════════
# 阶段标记：确保 hook 级 AskUserQuestion 硬拦截生效
# ══════════════════════════════════════
echo "autonomous" > /tmp/.claude_phase

echo "══════════════════════════════════════"
echo "  Feature Develop 迭代循环"
echo "  功能: ${VERSION_ID}/${FEATURE_NAME}"
if [ -n "$TASK_FILE" ]; then
    echo "  任务: $(basename "$TASK_FILE")"
fi
if [ -n "$ENGINE_NAME" ]; then
    echo "  工程: ${ENGINE_NAME}"
fi
echo "  最大轮次: ${MAX_ROUNDS}"
echo "══════════════════════════════════════"

# ══════════════════════════════════════
# 初始化日志
# ══════════════════════════════════════

cat > "$LOG_FILE" << 'EOF'
# 开发迭代日志

| 轮次 | 操作 | Critical | High | Medium | 状态 |
|------|------|----------|------|--------|------|
EOF

PREV_TOTAL=-1
BEST_TOTAL=999  # 质量棘轮：记录最佳 Review 成绩
CRITICAL=0
HIGH=0
MEDIUM=0
PREV_CRITICAL=0
PREV_HIGH=0
STABLE_STREAK=0
STABLE_HINT=""
REASON=""

# ── results.tsv 结果追踪 ──
RESULTS_FILE="${FEATURE_DIR}/results.tsv"
if [ ! -f "$RESULTS_FILE" ]; then
    echo -e "phase\ttask_id\twave\tattempt\taction\tduration_s\tcompile_ok\treview_critical\treview_high\tdecision\treason" > "$RESULTS_FILE"
fi
RESULTS_TASK_ID="${TASK_BASENAME:-full}"

# ── 质量棘轮：保存修复前的 git 状态，用于 discard ──
save_fix_checkpoint() {
    FIX_CKPT_CLIENT=""
    FIX_CKPT_SERVER=""
    FIX_CKPT_PROTO=""
    if [ -d "freelifeclient/.git" ]; then
        FIX_CKPT_CLIENT=$(git -C freelifeclient rev-parse HEAD 2>/dev/null || echo "")
    fi
    if [ -d "P1GoServer/.git" ]; then
        FIX_CKPT_SERVER=$(git -C P1GoServer rev-parse HEAD 2>/dev/null || echo "")
    fi
    if [ -d "old_proto/.git" ]; then
        FIX_CKPT_PROTO=$(git -C old_proto rev-parse HEAD 2>/dev/null || echo "")
    fi
}

rollback_fix() {
    echo "[质量棘轮] 修复导致质量恶化，Discard 本轮修复..."
    if [ -n "$FIX_CKPT_CLIENT" ] && [ -d "freelifeclient/.git" ]; then
        git -C freelifeclient checkout . 2>/dev/null || true
        git -C freelifeclient clean -fd 2>/dev/null || true
    fi
    if [ -n "$FIX_CKPT_SERVER" ] && [ -d "P1GoServer/.git" ]; then
        git -C P1GoServer checkout . 2>/dev/null || true
        git -C P1GoServer clean -fd 2>/dev/null || true
    fi
    if [ -n "$FIX_CKPT_PROTO" ] && [ -d "old_proto/.git" ]; then
        git -C old_proto checkout . 2>/dev/null || true
        git -C old_proto clean -fd 2>/dev/null || true
    fi
}

# ══════════════════════════════════════
# 主循环（原子化迭代）
# ══════════════════════════════════════

for ROUND in $(seq 1 "$MAX_ROUNDS"); do
    STAGE_ROUND_START=$(date +%s)
    echo ""
    echo "══════════════════════════════════════"
    echo "  轮次 ${ROUND} / ${MAX_ROUNDS}"
    echo "══════════════════════════════════════"

    if [ $((ROUND % 2)) -eq 1 ]; then
        # ── 奇数轮: 编码实现/修复 ──

        if [ "$ROUND" -eq 1 ]; then
            echo "[Round $ROUND] 编码实现..."

            PROMPT="读取 .claude/commands/feature/developing.md 中的完整工作流程，按照其中的 9 个步骤执行。

参数（已解析，直接使用）：
- version_id: ${VERSION_ID}
- feature_name: ${FEATURE_NAME}
- FEATURE_DIR: ${FEATURE_DIR}
- ENGINE_NAME: ${ENGINE_NAME}
${TASK_SCOPE_PROMPT}

自动化模式特殊规则：
1. 第二步（确认实现范围）：默认两端都做（如果 plan 包含两端设计），不等待用户确认。如果 plan 明确只涉及一端，则只做该端。
2. 如果文件清单较长，默认一次性全部完成，不分批。
3. 编码过程中发现可优化项时，不要提问，记录到 develop-log.md 的待办事项中。
4. 完成所有步骤后直接结束，不要中途停下来。
5. 配置文件（JSON、配置表等）如果 plan 要求新建，直接根据 plan 规格和已有配置格式自主创建，不要标记为"需策划确认"或"需人工介入"。参数值参考 plan 设计、GTA 源码和已有配置的数值范围，合理设定默认值。
6. UI 修改（面板、组件、事件绑定等）直接实施，不要推迟为人工处理。对照已有 UI 代码风格实现。
7. 禁止在代码或日志中写"待人工处理"、"需策划确认参数"、"需要人工介入"等推脱标记。所有 plan 中要求的功能都必须给出完整实现。

【完成声明（Ralph Loop 机制）— 不可跳过】
完成所有文件的实现后，你必须在 ${FEATURE_DIR}/develop-log.md 的末尾追加一行：
ALL_FILES_IMPLEMENTED
这一行表示你已经实现了任务范围中列出的**所有**文件。
- 如果你只实现了部分文件（因为上下文不够、遇到困难等），**不要写这一行**，而是在 develop-log.md 中记录已完成和未完成的文件清单。
- 只有当你确信任务范围中的每个文件都已新增或修改时，才写 ALL_FILES_IMPLEMENTED。
- 这是自动化流水线判断你是否真正完成的唯一依据，虚报会导致后续 Review 失败和质量下降。"

        else
            echo "[Round $ROUND] 修复代码（基于上轮 Review）..."

            # 质量棘轮：修复前保存检查点，修复后如果质量恶化则回滚
            save_fix_checkpoint

            PROMPT="${STABLE_HINT:+${STABLE_HINT}

}你的任务是根据 Review 报告修复代码。

请读取以下文件：
1. ${REVIEW_FILE} — 本轮新发现问题
2. ${KNOWN_ISSUES_FILE} — 历史累积问题（所有轮次的 CRITICAL/HIGH，必须全部修复，不只修本轮新发现）
3. ${FEATURE_DIR}/develop-log.md — 开发日志（了解已实现的文件和上下文）
4. ${PLAN_FILE} — Plan 文件（JSON 或 md 格式，作为设计参考）
${TASK_SCOPE_PROMPT:+5. 任务约束（只修复本任务范围内的问题）：
${TASK_SCOPE_PROMPT}}

修复规则：
- 先看 ${KNOWN_ISSUES_FILE} 中所有状态为 open 的 CRITICAL/HIGH，全部修复，不遗漏
- 再修复 ${REVIEW_FILE} 中的 CRITICAL 和 HIGH 问题
- 修复后对照 P1GoServer/.claude/constitution.md 和 freelifeclient/.claude/constitution.md 做合宪性自检
- 只修复报告中列出的问题，不做额外重构或改进
- MEDIUM 问题可以顺手修复，但不强制
- 修复完成后，更新 ${FEATURE_DIR}/develop-log.md（追加修复记录）
- 重要：Proto 消息类命名空间是 FL.NetModule（不是 FL.Net.Proto），检查所有 using 引用
- 配置文件缺失属于必修项：如果 Review 指出配置文件未创建，直接创建，根据 plan 和已有配置格式自主设定参数
- UI 问题属于必修项：如果 Review 指出 UI 未实现或 FOV/事件未生效，直接修复
- 禁止将任何问题标记为"需人工介入"或"待策划确认"——全部自主解决"
        fi

        # 首轮编码给 80 turns，修复轮给 40 turns
        if [ "$ROUND" -eq 1 ]; then
            DEVELOP_MAX_TURNS=80
        else
            DEVELOP_MAX_TURNS=40
        fi
        claude_tracked "编码/修复 Round $ROUND" "$PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" --max-turns "$DEVELOP_MAX_TURNS" | tail -20
        echo "| $ROUND | 编码/修复 | - | - | - | done |" >> "$LOG_FILE"

        # ── Ralph Loop：首轮编码后检查完成声明 ──
        if [ "$ROUND" -eq 1 ] && [ -n "$TASK_FILE" ]; then
            DEVELOP_LOG="${FEATURE_DIR}/develop-log.md"
            RALPH_MAX=3
            RALPH_ROUND=0
            while [ $RALPH_ROUND -lt $RALPH_MAX ]; do
                if grep -q "ALL_FILES_IMPLEMENTED" "$DEVELOP_LOG" 2>/dev/null; then
                    echo "[Ralph] 已确认所有文件实现完成"
                    break
                fi
                RALPH_ROUND=$((RALPH_ROUND + 1))
                echo "[Ralph] 未检测到 ALL_FILES_IMPLEMENTED 声明，继续实现 (${RALPH_ROUND}/${RALPH_MAX})..."

                RALPH_PROMPT="上一轮编码尚未完成所有文件。请继续实现剩余部分。

先读取以下文件建立上下文：
1. ${PLAN_FILE} — 技术方案（了解整体设计）
2. ${DEVELOP_LOG} — 查看已完成和未完成的文件清单

然后继续实现未完成的文件。

${TASK_SCOPE_PROMPT}

完成后在 ${DEVELOP_LOG} 末尾追加 ALL_FILES_IMPLEMENTED。
如果仍有无法完成的文件，在 ${DEVELOP_LOG} 中说明原因，然后也追加 ALL_FILES_IMPLEMENTED 表示已尽力完成。"

                claude_tracked "Ralph续写 ${RALPH_ROUND}" "$RALPH_PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" --max-turns 40 | tail -20
                echo "| $ROUND.R${RALPH_ROUND} | Ralph续写 | - | - | - | done |" >> "$LOG_FILE"
            done

            # ── Ralph 交叉验证：机械检查 task 文件清单中的文件是否实际存在 ──
            EXPECTED_FILES=$(grep -E '^\s*-\s*(新增|修改|新建)\s*[:：]' "$TASK_FILE" 2>/dev/null | sed 's/.*[:：]\s*\(`\?\)\([^ `]*\).*/\2/' | head -30)
            if [ -n "$EXPECTED_FILES" ]; then
                MISSING_FILES=""
                MISSING_COUNT=0
                for ef in $EXPECTED_FILES; do
                    if [ ! -f "$ef" ]; then
                        MISSING_FILES="${MISSING_FILES}\n  - ${ef}"
                        MISSING_COUNT=$((MISSING_COUNT + 1))
                    fi
                done
                if [ "$MISSING_COUNT" -gt 0 ]; then
                    echo "[Ralph-Verify] WARNING: ALL_FILES_IMPLEMENTED 已声明但 ${MISSING_COUNT} 个文件不存在:${MISSING_FILES}"
                    RALPH_FIX_PROMPT="task 文件清单中以下文件未创建，请补充实现：
$(echo -e "$MISSING_FILES")

参考：
1. ${PLAN_FILE} — 技术方案
2. ${FEATURE_DIR}/develop-log.md — 已完成的文件
${TASK_SCOPE_PROMPT}

只创建缺失文件，不要修改已有文件。完成后更新 develop-log.md。"
                    claude_tracked "Ralph-Verify补文件" "$RALPH_FIX_PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" --max-turns 30 | tail -15
                    echo "| $ROUND.V | Ralph-Verify补文件(${MISSING_COUNT}) | - | - | - | done |" >> "$LOG_FILE"
                else
                    echo "[Ralph-Verify] 文件清单交叉验证通过（${EXPECTED_FILES##*$'\n'} 等文件均存在）"
                fi
            fi
        fi

        # ── 编译验证 + 单元测试 ──

        # 服务端：编译 + 测试
        if [ -d "P1GoServer" ]; then
            echo "[Round $ROUND] 服务端编译验证..."
            BUILD_OUTPUT=$(cd P1GoServer && make build 2>&1)
            BUILD_EXIT=$?
            echo "$BUILD_OUTPUT" | tail -10

            if [ $BUILD_EXIT -ne 0 ]; then
                echo "WARNING: 服务端编译失败，启动自动修复..."
                FIX_PROMPT="服务端编译失败，请修复以下编译错误：

\$(cd P1GoServer && make build 2>&1 | grep -E 'error|Error|cannot|undefined' | head -20)

修复规则：
- 阅读报错文件，理解上下文后修复
- 只修复编译错误，不做额外改动
- 修复后重新运行 cd P1GoServer && make build 验证"
                claude_tracked "编译修复 Server" "$FIX_PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" --max-turns 30 | tail -10
                echo "| $ROUND.1 | 编译修复(Server) | - | - | - | done |" >> "$LOG_FILE"
            else
                echo "服务端编译通过"
                echo "[Round $ROUND] 运行服务端单元测试..."
                TEST_OUTPUT=$(cd P1GoServer && make test 2>&1)
                TEST_EXIT=$?
                echo "$TEST_OUTPUT" | tail -10
                if [ $TEST_EXIT -ne 0 ]; then
                    echo "WARNING: 服务端测试失败，启动自动修复..."
                    FIX_PROMPT="服务端单元测试失败，请修复：

$(cd P1GoServer && make test 2>&1 | grep -E 'FAIL|Error|panic' | head -20)

修复规则：
- 分析失败的测试用例，判断是代码 bug 还是测试需要更新
- 修复后重新运行 cd P1GoServer && make test 验证"
                    claude_tracked "测试修复 Server" "$FIX_PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" --max-turns 30 | tail -10
                    echo "| $ROUND.2 | 测试修复(Server) | - | - | - | done |" >> "$LOG_FILE"
                else
                    echo "服务端测试通过"
                fi
            fi
        fi

        # ── 客户端编译验证（双保险：Unity Editor.log + Unity MCP） ──
        echo "[Round $ROUND] 客户端编译验证..."

        UNITY_LOG="C:/Users/admin/AppData/Local/Unity/Editor/Editor.log"
        CLIENT_HAS_ERRORS=false

        # 保险1: 读取 Unity Editor.log 中的编译错误
        # 注意：Editor.log 可能包含旧的编译错误（Unity 未重新编译时）
        # 因此优先使用 MCP 触发重新编译后的结果，Editor.log 作为兜底
        if [ -f "$UNITY_LOG" ]; then
            LOG_MTIME=$(stat --format="%Y" "$UNITY_LOG" 2>/dev/null || echo "0")
            NOW=$(date +%s)
            LOG_AGE=$((NOW - LOG_MTIME))

            if [ "$LOG_AGE" -lt 120 ]; then
                # Editor.log 2分钟内更新过，说明 Unity 可能刚编译
                CS_ERRORS=$(grep "error CS" "$UNITY_LOG" 2>/dev/null | sort -u)
                CS_ERROR_COUNT=$(echo "$CS_ERRORS" | grep -c "error CS" 2>/dev/null || echo "0")

                if [ "$CS_ERROR_COUNT" -gt 0 ]; then
                    echo "WARNING: Unity Editor.log 发现 ${CS_ERROR_COUNT} 条编译错误（日志更新于 ${LOG_AGE}s 前）"
                    CLIENT_HAS_ERRORS=true
                else
                    echo "Unity Editor.log 无编译错误"
                fi
            else
                echo "NOTICE: Unity Editor.log 已过期（${LOG_AGE}s 前），等待 MCP 检查更实时的结果"
            fi
        else
            echo "NOTICE: Unity Editor.log 不存在，跳过日志检查"
        fi

        # 保险2: 直接用 mcp_call.py 调用 Unity MCP（避免启动 claude 子进程，节省 40-60s）
        if command -v python3 &>/dev/null && [ -f "scripts/mcp_call.py" ]; then
            echo "通过 mcp_call.py 调用 Unity MCP 获取编译状态..."
            MCP_RAW=$(timeout 30 python3 scripts/mcp_call.py console-get-logs '{"logType":"Error","count":50}' 2>/dev/null || echo '{"error":"mcp_unavailable"}')

            if echo "$MCP_RAW" | grep -q '"error"'; then
                echo "NOTICE: Unity MCP 不可用，仅依赖 Editor.log 结果"
            else
                MCP_CS_ERRORS=$(echo "$MCP_RAW" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    logs = d.get('logs', d.get('text', ''))
    if isinstance(logs, list):
        for l in logs:
            msg = l.get('message','') if isinstance(l, dict) else str(l)
            if 'error CS' in msg:
                print(msg)
    elif isinstance(logs, str):
        for line in logs.splitlines():
            if 'error CS' in line:
                print(line)
except: pass
" 2>/dev/null | sort -u)
                MCP_CS_COUNT=$(echo "$MCP_CS_ERRORS" | grep -c "error CS" 2>/dev/null || echo "0")

                if [ "$MCP_CS_COUNT" -gt 0 ]; then
                    echo "WARNING: Unity MCP 发现 ${MCP_CS_COUNT} 条编译错误（MCP 结果优先于 Editor.log）"
                    CLIENT_HAS_ERRORS=true
                    CS_ERRORS="$MCP_CS_ERRORS"
                    CS_ERROR_COUNT="$MCP_CS_COUNT"
                else
                    echo "Unity MCP 确认无编译错误"
                    CLIENT_HAS_ERRORS=false
                fi
            fi
        fi

        # 如果发现编译错误，启动自动修复
        if [ "$CLIENT_HAS_ERRORS" = true ] && [ "$CS_ERROR_COUNT" -gt 0 ]; then
            echo "启动客户端编译错误自动修复（${CS_ERROR_COUNT} 条错误）..."
            # 只传前30条去重后的错误，避免 prompt 太长
            # 上下文控制：编译错误截断到 30 行/4KB，防止大量嵌套错误膨胀 prompt
            ERROR_SAMPLE=$(echo "$CS_ERRORS" | head -30 | cut -c1-4096)
            FIX_PROMPT="Unity 客户端编译失败，请修复以下 C# 编译错误：

\`\`\`
${ERROR_SAMPLE}
\`\`\`

修复规则：
- 逐个分析每条 error CS 错误，阅读对应源文件理解上下文
- 搜索项目中正确的类名/方法名/命名空间，确认后再修
- 特别注意：Proto 消息类命名空间是 FL.NetModule（不是 FL.Net.Proto）
- Manager 类访问模式参考 BaseManager<T>，不一定有 .Instance 属性
- 修复后用 Grep 验证修复的类/方法确实存在
- 禁止引入新的编译错误"
            claude_tracked "编译修复 freelifeclient" "$FIX_PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" --max-turns 30 | tail -15
            echo "| $ROUND.3 | 编译修复(Client) | - | - | - | done |" >> "$LOG_FILE"

            # 修复后再次检查（等待 Unity 重新编译）
            echo "等待 Unity 重新编译（5秒）..."
            sleep 5
            if [ -f "$UNITY_LOG" ]; then
                REMAINING=$(grep "error CS" "$UNITY_LOG" 2>/dev/null | sort -u | wc -l)
                echo "修复后剩余编译错误: $REMAINING 条"
            fi
        else
            echo "客户端编译检查通过"
        fi
        # 客户端编译验证结束

    else
        # ── 偶数轮: 代码审查 ──

        # ── Pre-Review 机械检查（O1）：拦截已知规则违规，减少 Review 发现的 HIGH ──
        echo "[Round $ROUND] Pre-Review 机械检查..."
        # 上下文控制：pre-review 输出截断到 5KB，防止 prompt 膨胀
        PRE_CHECK_RESULT=$(bash .claude/scripts/pre-review-check.sh "$FEATURE_DIR" "${TASK_FILE:-}" 2>/dev/null | head -100 | cut -c1-5120 || true)
        PRE_ISSUE_COUNT=$(echo "$PRE_CHECK_RESULT" | grep -o 'PRE_REVIEW_ISSUES_FOUND=[0-9]*' | sed 's/PRE_REVIEW_ISSUES_FOUND=//' || echo "0")

        if [ "${PRE_ISSUE_COUNT:-0}" -gt 0 ]; then
            echo "Pre-Review 发现 ${PRE_ISSUE_COUNT} 个机械性问题，先修复再 Review..."
            PRE_FIX_PROMPT="请修复以下机械性规则违规（这些是 AI Review 之前的自动检查结果）：

${PRE_CHECK_RESULT}

修复规则（逐条处理）：
- [CS-LOG-INTERP]：将 MLog 中的 \$\"\" 插值改为 + 字符串拼接
- [GO-FMT]：将日志中的 %d/%s 格式符改为 %v
- [GO-FIELD]：将 entityID= 改为 npc_entity_id=，cfgId= 改为 npc_cfg_id=
- [CS-ALIAS]：在 using FL.NetModule 的文件中添加 Vector3/Vector2 alias
- [CS-ANGLE]：为角度变量添加 Deg 或 Rad 后缀并确保单位一致
修复完成后不需要写任何完成标记，直接结束。"
            claude_tracked "Pre-Review机械修复" "$PRE_FIX_PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob" --max-turns 20 | tail -10
            echo "| $ROUND.P | Pre-Review修复 | - | - | - | done |" >> "$LOG_FILE"
        else
            echo "Pre-Review 检查通过，无机械性违规"
        fi

        echo "[Round $ROUND] 3-Agent 并行 Review..."

        # ── 并行 Review：3 个独立 CLI 进程，各聚焦一个维度 ──
        REVIEW_DIR="${FEATURE_DIR}/review-round-${ROUND}"
        mkdir -p "$REVIEW_DIR"

        # Agent 1: 代码质量+合宪性+Plan完整性+需求对齐（主 review）
        REVIEW_PROMPT_MAIN="读取 .claude/commands/feature/develop-review.md 中的完整工作流程，按照其中的步骤执行。
参数：version_id=${VERSION_ID} feature_name=${FEATURE_NAME} FEATURE_DIR=${FEATURE_DIR}
自动化模式：将报告写入 ${REVIEW_DIR}/review-code.md，末尾追加 <!-- counts: critical=X high=Y medium=Z -->"

        # Agent 2: 安全审查
        REVIEW_PROMPT_SEC="你是安全审查专家。检查 ${FEATURE_DIR} 涉及的代码变更（用 git diff）：
1. 硬编码密钥/Token/服务器地址 2. 客户端直接修改游戏状态（应服务器权威）3. 敏感数据写入日志 4. SQL/命令注入 5. 越权访问 6. 信息泄露
将报告写入 ${REVIEW_DIR}/review-security.md，末尾追加 <!-- counts: critical=X high=Y medium=Z -->"

        # Agent 3: 测试覆盖审查（替代原事务审查，事务检查已内含在 Agent 1 的 develop-review.md Step 4-B）
        REVIEW_PROMPT_TEST="你是测试覆盖审查专家。检查 ${FEATURE_DIR} 涉及的代码变更（用 git diff），聚焦：
1. 公共 API/RPC Handler 是否有对应的单元测试或集成测试
2. plan.json 中的 acceptance_criteria 和边界用例是否在代码或测试中覆盖
3. 错误路径测试：异常输入、超时、断连等场景是否有测试
4. 配置表/协议变更是否有对应的验证逻辑
5. 跨端交互（C/S 通信）是否有端到端验证方案
参考 plan：读取 ${FEATURE_DIR}/plan.json 了解设计要求。
将报告写入 ${REVIEW_DIR}/review-test-coverage.md，末尾追加 <!-- counts: critical=X high=Y medium=Z -->"

        # 并行启动 3 个 review 进程
        claude_tracked "Review-Code R${ROUND}" "$REVIEW_PROMPT_MAIN" --allowedTools "Read,Bash,Grep,Glob,Agent,WebSearch,WebFetch,ToolSearch" --max-turns 25 > /dev/null &
        PID_MAIN=$!
        claude_tracked "Review-Security R${ROUND}" "$REVIEW_PROMPT_SEC" --allowedTools "Read,Bash,Grep,Glob" --max-turns 15 > /dev/null &
        PID_SEC=$!
        claude_tracked "Review-TestCoverage R${ROUND}" "$REVIEW_PROMPT_TEST" --allowedTools "Read,Bash,Grep,Glob" --max-turns 15 > /dev/null &
        PID_TEST=$!

        echo "  并行 Review PID: code=$PID_MAIN security=$PID_SEC test-coverage=$PID_TEST"
        wait $PID_MAIN $PID_SEC $PID_TEST 2>/dev/null || true

        # ── 合并 3 份报告（含 severity 加权）──
        CRITICAL=0; HIGH=0; MEDIUM=0; WEIGHTED_SCORE=0
        for RFILE in "$REVIEW_DIR"/review-*.md; do
            if [ -f "$RFILE" ]; then
                LINE=$(grep -o 'counts: critical=[0-9]* high=[0-9]* medium=[0-9]*' "$RFILE" 2>/dev/null | tail -1 || echo "")
                if [ -n "$LINE" ]; then
                    C=$(echo "$LINE" | sed 's/.*critical=\([0-9]*\).*/\1/')
                    H=$(echo "$LINE" | sed 's/.*high=\([0-9]*\).*/\1/')
                    M=$(echo "$LINE" | sed 's/.*medium=\([0-9]*\).*/\1/')
                    CRITICAL=$((CRITICAL + C))
                    HIGH=$((HIGH + H))
                    MEDIUM=$((MEDIUM + M))

                    # 按维度加权: security > code > test-coverage
                    BASENAME=$(basename "$RFILE")
                    case "$BASENAME" in
                        *security*)  WC=5; WH=3 ;;
                        *code*)      WC=3; WH=2 ;;
                        *test*)      WC=2; WH=1 ;;
                        *)           WC=3; WH=2 ;;
                    esac
                    WEIGHTED_SCORE=$((WEIGHTED_SCORE + C * WC + H * WH))
                fi
            fi
        done

        # 合并为统一报告（供 fix agent 读取）
        {
            echo "# Review Round $ROUND 合并报告"
            echo ""
            for RFILE in "$REVIEW_DIR"/review-*.md; do
                [ -f "$RFILE" ] && echo "---" && cat "$RFILE"
            done
            echo ""
            echo "<!-- counts: critical=$CRITICAL high=$HIGH medium=$MEDIUM -->"
        } > "$REVIEW_FILE"

        # 回退兼容：如果 3 个进程全部失败（无报告文件），标记异常
        if [ "$CRITICAL" -eq 0 ] && [ "$HIGH" -eq 0 ] && [ "$MEDIUM" -eq 0 ]; then
            if ! ls "$REVIEW_DIR"/review-*.md 1>/dev/null 2>&1; then
                echo "WARNING: 所有 Review 进程均未产出报告"
                CRITICAL=999
                HIGH=999
                MEDIUM=0
            fi
        fi

        CURRENT_TOTAL=$WEIGHTED_SCORE
        ROUND_END=$(date +%s)
        ROUND_DURATION=$((ROUND_END - STAGE_ROUND_START))
        echo "| $ROUND | Review | $CRITICAL | $HIGH | $MEDIUM | W=$WEIGHTED_SCORE | done |" >> "$LOG_FILE"
        echo "Review 结果: Critical=$CRITICAL, High=$HIGH, Medium=$MEDIUM, WeightedScore=$WEIGHTED_SCORE"

        # ── 早期卡死检测：Round ≥4 且仍未收敛 → 写 stuck signal ──
        if [ "$ROUND" -ge 4 ] && [ "$CRITICAL" -gt 0 -o "$HIGH" -gt 2 ]; then
            echo "WARNING: Round $ROUND 仍有 Critical=$CRITICAL High=$HIGH — 任务可能卡死"
            echo "STUCK round=$ROUND critical=$CRITICAL high=$HIGH weighted=$WEIGHTED_SCORE" > "${FEATURE_DIR}/stuck-signal-${RESULTS_TASK_ID}.txt"
        fi

        # ── 追加到累积问题文件（O2）：fix agent 下轮可以看到所有历史问题 ──
        {
            echo ""
            echo "## Round ${ROUND} Review ($(date '+%Y-%m-%d %H:%M:%S'))"
            echo "Critical=${CRITICAL}, High=${HIGH}, Medium=${MEDIUM}"
            echo ""
            # 提取本轮 CRITICAL/HIGH 问题到 known-issues
            if [ -f "$REVIEW_FILE" ]; then
                grep -A2 -E '^\*\*(CRITICAL|HIGH)\*\*|^### (CRITICAL|HIGH)' "$REVIEW_FILE" 2>/dev/null | head -60 || true
            fi
        } >> "$KNOWN_ISSUES_FILE"

        # 上下文控制：KNOWN_ISSUES_FILE 只保留最近 3 轮（~100 行），归档旧内容
        if [ -f "$KNOWN_ISSUES_FILE" ]; then
            local ISSUE_LINES=$(wc -l < "$KNOWN_ISSUES_FILE")
            if [ "$ISSUE_LINES" -gt 100 ]; then
                tail -100 "$KNOWN_ISSUES_FILE" > "${KNOWN_ISSUES_FILE}.tmp"
                mv "${KNOWN_ISSUES_FILE}.tmp" "$KNOWN_ISSUES_FILE"
            fi
        fi

        # ── 记录到 results.tsv ──
        echo -e "P4\t${RESULTS_TASK_ID}\t${TASK_WAVE:-0}\t${ROUND}\treview\t${ROUND_DURATION}\ttrue\t${CRITICAL}\t${HIGH}\tpending\t-" >> "$RESULTS_FILE"

        # ── 收敛判断（含质量棘轮）──

        if [ "$CRITICAL" -eq 0 ] && [ "$HIGH" -le 2 ] && [ "$WEIGHTED_SCORE" -le 6 ]; then
            REASON="质量达标"
            echo "PASS: $REASON (Critical=0, High<=2, W=${WEIGHTED_SCORE}<=6)"
            # 记录 keep 决策
            echo -e "P4\t${RESULTS_TASK_ID}\t${TASK_WAVE:-0}\t${ROUND}\tkeep\t${ROUND_DURATION}\ttrue\t${CRITICAL}\t${HIGH}\tkeep\t质量达标(W=${WEIGHTED_SCORE})" >> "$RESULTS_FILE"
            break
        fi

        # 质量棘轮：修复后质量恶化 → discard 修复
        if [ "$ROUND" -gt 2 ] && [ "$PREV_TOTAL" -ge 0 ] && [ "$CURRENT_TOTAL" -gt "$PREV_TOTAL" ]; then
            REASON="质量恶化(棘轮)"
            echo "RATCHET: $REASON (当前=$CURRENT_TOTAL > 上轮=$PREV_TOTAL)"
            rollback_fix
            # 恢复到上轮的 Review 结果
            echo -e "P4\t${RESULTS_TASK_ID}\t${TASK_WAVE:-0}\t${ROUND}\tdiscard-fix\t0\ttrue\t${CRITICAL}\t${HIGH}\tdiscard\t修复导致质量恶化 ${PREV_TOTAL}->${CURRENT_TOTAL}" >> "$RESULTS_FILE"
            # 恢复上一轮的 counts 作为最终状态
            CRITICAL=$PREV_CRITICAL
            HIGH=$PREV_HIGH
            break
        fi

        if [ "$PREV_TOTAL" -ge 0 ] && [ "$CURRENT_TOTAL" -eq "$PREV_TOTAL" ]; then
            STABLE_STREAK=$((STABLE_STREAK + 1))
            echo "WARN: 问题总数未减少 ($CURRENT_TOTAL), 连续 ${STABLE_STREAK} 轮稳定"
            if [ "$STABLE_STREAK" -ge 2 ]; then
                REASON="连续2轮稳定不变"
                echo "EXIT: $REASON"
                break
            fi
            # 第一轮稳定：注入"换策略"提示到下一轮 fix prompt
            STABLE_HINT="【重要】上一轮修复未改善质量（问题总数仍为 ${CURRENT_TOTAL}）。请尝试不同的修复策略——如果之前改了实现逻辑，考虑改接口/配置；如果改了单文件，考虑跨文件协调。不要重复上一轮的修复方式。"
        else
            STABLE_STREAK=0
            STABLE_HINT=""
        fi

        # 更新最佳成绩和上轮数据
        if [ "$CURRENT_TOTAL" -lt "$BEST_TOTAL" ]; then
            BEST_TOTAL=$CURRENT_TOTAL
        fi
        PREV_CRITICAL=$CRITICAL
        PREV_HIGH=$HIGH
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
- 最终状态：Critical=$CRITICAL, High=$HIGH, Medium=$MEDIUM, WeightedScore=${WEIGHTED_SCORE:-0}
- 最佳成绩(棘轮)：$BEST_TOTAL
- 结果追踪：$RESULTS_FILE
EOF

echo ""
echo "══════════════════════════════════════"
echo "  开发迭代完成（原子化）"
echo "══════════════════════════════════════"
echo "  轮次: $ROUND"
echo "  终止原因: $REASON"
echo "  最终质量: Critical=$CRITICAL, High=$HIGH, Medium=$MEDIUM"
echo "  质量棘轮最佳: $BEST_TOTAL"
echo "  Plan 文件: $PLAN_FILE"
echo "  迭代日志: $LOG_FILE"
echo "  结果追踪: $RESULTS_FILE"
echo "  开发日志: ${FEATURE_DIR}/develop-log.md"
echo "══════════════════════════════════════"

