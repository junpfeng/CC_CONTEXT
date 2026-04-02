#!/bin/bash
# bug-fix-loop.sh
# 自动闭环 Bug 修复流程：分析 → 修复 → 编译验证 → Review → 收敛 → 固化
# 每个阶段启动新 Claude 实例防止上下文污染
#
# 用法:
#   bash .claude/scripts/bug-fix-loop.sh <version> <feature_name> [bug_index] [max_rounds]
#
# 示例:
#   bash .claude/scripts/bug-fix-loop.sh 0.0.1 match              # 修复 match 模块所有未修复 bug
#   bash .claude/scripts/bug-fix-loop.sh 0.0.1 match 1            # 只修复第 1 个 bug
#
# 注意: 批量模式（扫描所有版本）已移至 bug:fix skill 层编排（支持并行），不再由本脚本处理
#
# 前置条件:
#   - claude CLI 可用
#   - 从项目根目录运行

set -euo pipefail

# ══════════════════════════════════════
# 参数解析
# ══════════════════════════════════════

VERSION=""
FEATURE_NAME=""
BUG_INDEX=""
MAX_FIX_ROUNDS=10  # 每个 bug 的最大修复迭代轮次

if [ -n "${1:-}" ] && [ -n "${2:-}" ]; then
    VERSION="$1"
    FEATURE_NAME="$2"
    BUG_INDEX="${3:-}"
    if [[ "${BUG_INDEX}" =~ ^[0-9]+$ ]]; then
        MAX_FIX_ROUNDS="${4:-10}"
    else
        # 第三个参数如果不是数字，视为空，可能是 max_rounds
        if [[ -n "$BUG_INDEX" ]] && [[ "$BUG_INDEX" =~ ^[0-9]+$ ]]; then
            MAX_FIX_ROUNDS="${4:-10}"
        else
            MAX_FIX_ROUNDS="${3:-10}"
            BUG_INDEX=""
        fi
    fi
else
    echo "用法:"
    echo "  $0 <version> <feature_name> [bug_index] [max_rounds]"
    exit 1
fi

# ══════════════════════════════════════
# 公共函数
# ══════════════════════════════════════

# 服务端编译验证
verify_server_build() {
    if [ ! -d "P1GoServer" ]; then
        return 0
    fi
    echo "  [编译] 服务端编译验证..."
    BUILD_OUTPUT=$(cd P1GoServer && make build 2>&1)
    BUILD_EXIT=$?
    if [ $BUILD_EXIT -ne 0 ]; then
        echo "  WARNING: 服务端编译失败"
        return 1
    fi
    echo "  [编译] 服务端编译通过"

    echo "  [测试] 服务端单元测试..."
    TEST_OUTPUT=$(cd P1GoServer && make test 2>&1)
    TEST_EXIT=$?
    if [ $TEST_EXIT -ne 0 ]; then
        echo "  WARNING: 服务端测试失败"
        return 2
    fi
    echo "  [测试] 服务端测试通过"
    return 0
}

# 客户端编译验证（双保险：Editor.log + Unity MCP）
verify_client_build() {
    echo "  [编译] 客户端编译验证..."

    UNITY_LOG="C:/Users/admin/AppData/Local/Unity/Editor/Editor.log"
    CLIENT_HAS_ERRORS=false
    CS_ERRORS=""
    CS_ERROR_COUNT=0

    # 保险1: Editor.log
    if [ -f "$UNITY_LOG" ]; then
        LOG_MTIME=$(stat --format="%Y" "$UNITY_LOG" 2>/dev/null || echo "0")
        NOW=$(date +%s)
        LOG_AGE=$((NOW - LOG_MTIME))

        if [ "$LOG_AGE" -lt 120 ]; then
            CS_ERRORS=$(grep "error CS" "$UNITY_LOG" 2>/dev/null | sort -u || true)
            CS_ERROR_COUNT=$(echo "$CS_ERRORS" | grep -c "error CS" 2>/dev/null || echo "0")
            if [ "$CS_ERROR_COUNT" -gt 0 ]; then
                echo "  WARNING: Editor.log 发现 ${CS_ERROR_COUNT} 条编译错误"
                CLIENT_HAS_ERRORS=true
            fi
        fi
    fi

    # 保险2: Unity MCP
    if command -v claude &>/dev/null; then
        MCP_RESULT=$(timeout 60 claude -p "尝试使用 Unity MCP 工具检查客户端编译状态：

Unity MCP 工具名（精确）：
- mcp__unityMCP__refresh_unity — 触发 Unity 刷新/重新编译
- mcp__unityMCP__read_console — 读取 Unity Console 日志

执行步骤：
1. 先用 ToolSearch 搜索 'select:mcp__unityMCP__refresh_unity' 获取工具定义
2. 调用 mcp__unityMCP__refresh_unity 触发重新编译
3. 等待 5 秒让编译完成
4. 用 ToolSearch 搜索 'select:mcp__unityMCP__read_console' 获取工具定义
5. 调用 mcp__unityMCP__read_console 获取 Console 错误

异常处理：
- 如果 ToolSearch 找不到 mcp__unityMCP 开头的工具，输出 'MCP_NOT_AVAILABLE'
- 如果工具调用报错，输出 'MCP_NOT_AVAILABLE'
- 如果有编译错误（error CS），输出所有 error 行
- 如果无错误，输出 'MCP_NO_ERRORS'" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" 2>&1 | tail -20)

        if echo "$MCP_RESULT" | grep -q "MCP_NOT_AVAILABLE"; then
            echo "  NOTICE: Unity MCP 不可用"
        elif echo "$MCP_RESULT" | grep -q "error CS"; then
            echo "  WARNING: Unity MCP 发现编译错误"
            CLIENT_HAS_ERRORS=true
            CS_ERRORS=$(echo "$MCP_RESULT" | grep "error CS" | sort -u)
            CS_ERROR_COUNT=$(echo "$CS_ERRORS" | grep -c "error CS" 2>/dev/null || echo "0")
        elif echo "$MCP_RESULT" | grep -q "MCP_NO_ERRORS"; then
            echo "  [编译] Unity MCP 确认无编译错误"
            CLIENT_HAS_ERRORS=false
        fi
    fi

    if [ "$CLIENT_HAS_ERRORS" = true ]; then
        echo "  客户端编译错误: ${CS_ERROR_COUNT} 条"
        return 1
    fi
    echo "  [编译] 客户端编译通过"
    return 0
}

# 客户端运行时错误诊断（通过 Editor.log + Unity MCP）
# 输出诊断结果到 stdout，调用方捕获
diagnose_client_errors() {
    local DIAG_RESULT=""

    echo "  [诊断] 收集客户端错误信息..." >&2

    UNITY_LOG="C:/Users/admin/AppData/Local/Unity/Editor/Editor.log"

    # ── 1. 读取 Editor.log 中的异常和错误 ──
    if [ -f "$UNITY_LOG" ]; then
        # 提取最近的 Exception、Error、NullReference、assert 等（去重，最多30条）
        LOG_ERRORS=$(grep -iE 'Exception|NullReference|Error|assert|FATAL|StackTrace|error CS' "$UNITY_LOG" 2>/dev/null \
            | grep -v "^$" \
            | sort -u \
            | tail -30 || true)

        if [ -n "$LOG_ERRORS" ]; then
            DIAG_RESULT="${DIAG_RESULT}
### Unity Editor.log 错误信息
\`\`\`
${LOG_ERRORS}
\`\`\`
"
            echo "  [诊断] Editor.log 发现错误/异常记录" >&2
        else
            echo "  [诊断] Editor.log 无明显错误" >&2
        fi
    else
        echo "  [诊断] Editor.log 不存在，跳过" >&2
    fi

    # ── 2. 通过 Unity MCP 读取 Console 日志 ──
    if command -v claude &>/dev/null; then
        echo "  [诊断] 尝试通过 Unity MCP 读取 Console..." >&2
        MCP_CONSOLE=$(timeout 60 claude -p "请通过 Unity MCP 读取 Console 日志中的错误和警告信息。

执行步骤：
1. 用 ToolSearch 搜索 'select:mcp__unityMCP__read_console' 获取工具定义
2. 调用 mcp__unityMCP__read_console 读取 Unity Console 输出
3. 从输出中筛选 Error 和 Warning 级别的消息
4. 如果包含堆栈信息（stack trace），完整保留

输出规则：
- 如果 ToolSearch 找不到 mcp__unityMCP 工具，输出 'MCP_NOT_AVAILABLE'
- 如果工具调用失败，输出 'MCP_NOT_AVAILABLE'
- 如果有错误/警告，原样输出所有 Error 和 Warning 消息（保留堆栈）
- 如果 Console 干净无错误，输出 'MCP_CONSOLE_CLEAN'" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" 2>&1 | tail -40)

        if echo "$MCP_CONSOLE" | grep -q "MCP_NOT_AVAILABLE"; then
            echo "  [诊断] Unity MCP 不可用，跳过 Console 读取" >&2
        elif echo "$MCP_CONSOLE" | grep -q "MCP_CONSOLE_CLEAN"; then
            echo "  [诊断] Unity Console 无错误" >&2
        else
            # MCP 返回了 Console 内容，提取有用部分
            CONSOLE_ERRORS=$(echo "$MCP_CONSOLE" | grep -ivE 'MCP_|ToolSearch|mcp__' | tail -40 || true)
            if [ -n "$CONSOLE_ERRORS" ]; then
                DIAG_RESULT="${DIAG_RESULT}
### Unity Console 错误信息（via MCP）
\`\`\`
${CONSOLE_ERRORS}
\`\`\`
"
                echo "  [诊断] Unity MCP 获取到 Console 错误信息" >&2
            fi
        fi
    else
        echo "  [诊断] claude CLI 不可用，跳过 MCP 诊断" >&2
    fi

    # 输出诊断结果
    if [ -n "$DIAG_RESULT" ]; then
        echo "$DIAG_RESULT"
    else
        echo ""
    fi
}

# 自动修复编译错误
fix_compile_errors() {
    local ERROR_TYPE="$1"  # server_build | server_test | client
    local ERROR_DETAIL="$2"

    echo "  [修复] 自动修复 ${ERROR_TYPE} 错误..."

    case "$ERROR_TYPE" in
        server_build)
            FIX_PROMPT="服务端编译失败，请修复以下编译错误：

\$(cd P1GoServer && make build 2>&1 | grep -E 'error|Error|cannot|undefined' | head -20)

修复规则：
- 阅读报错文件，理解上下文后修复
- 只修复编译错误，不做额外改动
- 修复后重新运行 cd P1GoServer && make build 验证"
            ;;
        server_test)
            FIX_PROMPT="服务端单元测试失败，请修复：

$(cd P1GoServer && make test 2>&1 | grep -E 'FAIL|Error|panic' | head -20)

修复规则：
- 分析失败的测试用例，判断是代码 bug 还是测试需要更新
- 修复后重新运行 cd P1GoServer && make test 验证"
            ;;
        client)
            ERROR_SAMPLE=$(echo "$ERROR_DETAIL" | head -30)
            FIX_PROMPT="Unity 客户端编译失败，请修复以下 C# 编译错误：

\`\`\`
${ERROR_SAMPLE}
\`\`\`

修复规则：
- 逐个分析每条 error CS 错误，阅读对应源文件理解上下文
- 搜索项目中正确的类名/方法名/命名空间，确认后再修
- 特别注意：Proto 消息类命名空间是 FL.NetModule（不是 FL.Net.Proto）
- Manager 类访问模式参考 BaseManager<T>
- 修复后用 Grep 验证修复的类/方法确实存在
- 禁止引入新的编译错误"
            ;;
    esac

    claude -p "$FIX_PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" 2>&1 | tail -10
}

# 编译验证 + 自动修复循环（最多重试 3 次）
compile_and_fix() {
    local MAX_COMPILE_RETRIES=3

    for RETRY in $(seq 1 "$MAX_COMPILE_RETRIES"); do
        COMPILE_OK=true

        # 服务端
        if ! verify_server_build; then
            COMPILE_OK=false
            if [ $? -eq 1 ]; then
                fix_compile_errors "server_build" ""
            else
                fix_compile_errors "server_test" ""
            fi
        fi

        # 客户端
        if ! verify_client_build; then
            COMPILE_OK=false
            fix_compile_errors "client" "$CS_ERRORS"
        fi

        if [ "$COMPILE_OK" = true ]; then
            echo "  [编译] 全部编译验证通过"
            return 0
        fi

        if [ "$RETRY" -lt "$MAX_COMPILE_RETRIES" ]; then
            echo "  [编译] 第 ${RETRY} 次编译修复后仍有错误，重试..."
            sleep 3
        fi
    done

    echo "  WARNING: 编译修复达到最大重试次数 (${MAX_COMPILE_RETRIES})"
    return 1
}

# ══════════════════════════════════════
# 单个 Bug 完整修复流程
# ══════════════════════════════════════
#
# 输入: fix_single_bug <version> <feature_name> <bug_text> <bug_number>
# 流程: 分析 → [修复 → 编译 → Review] 迭代 → 固化 + 文档更新
#
fix_single_bug() {
    local VERSION="$1"
    local FEATURE="$2"
    local BUG_TEXT="$3"
    local BUG_NUM="$4"

    local BUG_DIR="docs/bugs/${VERSION}/${FEATURE}"
    local BUG_DOC="${BUG_DIR}/${FEATURE}.md"
    local BUG_NUM_DIR="${BUG_DIR}/${BUG_NUM}"
    local ANALYSIS_FILE="${BUG_NUM_DIR}/analysis.md"
    local REVIEW_FILE="${BUG_NUM_DIR}/fix-review-report.md"
    local FIX_LOG="${BUG_NUM_DIR}/fix-log.md"

    mkdir -p "${BUG_NUM_DIR}"

    echo ""
    echo "────────────────────────────────────"
    echo "  Bug #${BUG_NUM}: ${BUG_TEXT:0:60}"
    echo "────────────────────────────────────"

    # 初始化修复日志
    cat > "$FIX_LOG" << EOF
# Bug 修复日志 #${BUG_NUM}

- **版本**: ${VERSION}
- **模块**: ${FEATURE}
- **Bug**: ${BUG_TEXT}
- **启动时间**: $(date '+%Y-%m-%d %H:%M:%S')

| 轮次 | 操作 | Critical | High | Medium | 状态 |
|------|------|----------|------|--------|------|
EOF

    # ── 阶段零-A：客户端错误诊断 ──

    echo "  [阶段零-A] 客户端运行时错误诊断..."
    CLIENT_DIAG_INFO=$(diagnose_client_errors)

    # 构建诊断上下文（注入到分析 prompt 中）
    CLIENT_DIAG_SECTION=""
    if [ -n "$CLIENT_DIAG_INFO" ]; then
        CLIENT_DIAG_SECTION="
## 客户端自动诊断结果

以下是通过 Unity Editor.log 和 Unity MCP Console 自动收集的客户端错误信息，请作为根因分析的重要线索：

${CLIENT_DIAG_INFO}

> 注意：以上信息可能包含与本 Bug 无关的历史错误，请结合 Bug 描述筛选相关条目。
"
    fi

    # ── 阶段一：根因分析 ──

    PHASE1_START=$(date +%s)
    echo "  [阶段一] 根因分析..."

    ANALYSIS_PROMPT="你是一名资深全栈游戏开发工程师和根因分析专家。请对以下 Bug 进行根因分析。

## Bug 信息
- **版本**：${VERSION}
- **功能模块**：${FEATURE}
- **Bug 文档路径**：${BUG_DOC}
- **Bug 描述**：${BUG_TEXT}
- **设计文档路径**（如存在）：docs/version/${VERSION}/${FEATURE}/spec.md
${CLIENT_DIAG_SECTION}
## 工作步骤

### 1. 理解 Bug
- 读取 Bug 文档 ${BUG_DOC}，提取现象、复现路径、预期行为
- 如果 Bug 条目包含图片引用，读取 ${BUG_NUM_DIR}/images/ 下对应图片
- 读取设计文档（如存在）作为正确行为参考
- **如果上方提供了客户端自动诊断结果**，从中提取与本 Bug 相关的异常/堆栈信息，作为定位问题的重要线索

### 1.5 客户端深度诊断（如果 Bug 涉及客户端）
- 尝试使用 Unity MCP 工具进一步获取信息：
  1. 用 ToolSearch 搜索 'select:mcp__unityMCP__read_console' 获取工具定义
  2. 调用 mcp__unityMCP__read_console 读取最新的 Console 日志
  3. 从 Console 日志中筛选与本 Bug 相关的 Error/Exception/Warning
- 如果 Unity MCP 不可用，读取 Unity Editor.log（路径：C:/Users/admin/AppData/Local/Unity/Editor/Editor.log），搜索与 Bug 相关的关键字
- 从堆栈信息中定位出错的具体代码文件和行号

### 2. 定位问题代码
搜索策略（按优先级）：
- **客户端优先利用诊断结果**：如果步骤 1/1.5 得到了堆栈或错误信息，直接定位到对应文件和行号
- 客户端：freelifeclient/Assets/Scripts/Gameplay/
- 服务端：P1GoServer/servers/
- 协议：old_proto/
- 配置：Configs/
- 根据错误日志关键字 → 功能模块名 → 事件/消息名 → 数据流追踪
- 找到可疑代码后，必须完整阅读相关文件

### 3. 根因分析
输出结构化根因分析，写入 ${ANALYSIS_FILE}，格式如下：

\`\`\`markdown
# 根因分析报告 - Bug #${BUG_NUM}

## Bug 描述
[一句话描述 Bug 表现]

## 直接原因
[导致 Bug 的直接代码问题，引用具体文件和行号]

## 根本原因分类
[从以下选择：知识盲区 / 模式违规 / 遗漏检查 / 时序问题 / 数据问题 / 配置问题 / 第三方问题 / 需求理解偏差]

## 影响范围
[这个根因可能影响的其他代码位置]

## 修复方案
[具体描述如何修复，列出要修改的文件和修改内容概述]

## 是否需要固化防护
[是/否] — [理由]

## 修复风险评估
[低/中/高] — [可能影响的现有功能]
\`\`\`

### 禁止事项
- 禁止不读代码就分析
- 禁止编造 API
- 禁止跳过根因直接给方案"

    claude -p "$ANALYSIS_PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" 2>&1 | tail -15

    PHASE1_END=$(date +%s)
    PHASE1_DURATION=$((PHASE1_END - PHASE1_START))

    if [ ! -f "$ANALYSIS_FILE" ]; then
        echo "  ERROR: 根因分析报告未生成: ${ANALYSIS_FILE}"
        echo "| 1 | 根因分析 | - | - | - | 失败 |" >> "$FIX_LOG"
        return 1
    fi

    echo "  [阶段一] 根因分析完成 (${PHASE1_DURATION}s)"
    echo "| 0 | 根因分析 | - | - | - | done (${PHASE1_DURATION}s) |" >> "$FIX_LOG"

    # ── 阶段二：修复迭代循环 ──

    echo "  [阶段二] 进入修复迭代循环 (最大 ${MAX_FIX_ROUNDS} 轮)..."

    PREV_TOTAL=-1
    PREV_MEDIUM=-1
    CRITICAL=0
    HIGH=0
    MEDIUM=0
    FIX_REASON=""

    for ROUND in $(seq 1 "$MAX_FIX_ROUNDS"); do
        echo ""
        echo "  ── 轮次 ${ROUND} / ${MAX_FIX_ROUNDS} ──"

        if [ $((ROUND % 2)) -eq 1 ]; then
            # ── 奇数轮: 实施修复 / 修复 Review 问题 ──

            if [ "$ROUND" -eq 1 ]; then
                echo "  [Fix] 实施修复（基于根因分析）..."

                FIX_PROMPT="你是一名资深全栈游戏开发工程师。请根据根因分析报告修复以下 Bug。

## Bug 信息
- **版本**：${VERSION}
- **功能模块**：${FEATURE}
- **Bug 描述**：${BUG_TEXT}

## 必读文件
1. ${ANALYSIS_FILE} — 根因分析报告（包含修复方案）
2. 相关源代码文件（分析报告中标注的文件，修改前必须先完整阅读）

## 客户端修复时的辅助诊断

如果本次修复涉及客户端代码，在动手修改之前先做以下诊断：

1. **读取 Unity Editor.log**（路径：C:/Users/admin/AppData/Local/Unity/Editor/Editor.log）
   - 搜索与本 Bug 相关的 Exception、NullReference、error CS 等关键字
   - 从堆栈信息定位出错的具体文件和行号
2. **尝试使用 Unity MCP 读取 Console**：
   - 用 ToolSearch 搜索 'select:mcp__unityMCP__read_console' 获取工具定义
   - 调用 mcp__unityMCP__read_console 获取最新 Console 错误
   - 如果 MCP 不可用则跳过，仅依赖 Editor.log
3. 将诊断结果与根因分析报告交叉验证，确认修复方向正确

## 修复规则
- 严格按照分析报告中的修复方案执行
- 最小化修改，不做无关重构
- 先阅读再修改：修改已有文件前，必须先 Read 完整文件
- 遵循项目宪法（客户端: freelifeclient/.claude/constitution.md，服务端: P1GoServer/.claude/constitution.md）
- 修改 using 语句时，检查 freelifeclient/.claude/rules/coding-style.md 中的类型歧义消解规则
- Proto 消息类命名空间是 FL.NetModule（不是 FL.Net.Proto）

## 客户端修复后验证

修复完成后，如果修改了客户端代码：
1. 尝试通过 Unity MCP 触发重新编译（ToolSearch 搜索 'select:mcp__unityMCP__refresh_unity'）
2. 等待 5 秒后，读取 Console 检查是否有新的编译错误或运行时异常
3. 如果 MCP 不可用，读取 Editor.log 确认无新增 error CS

## 合宪性自检
修复完成后，对照宪法自检：
- 客户端：MLog 日志、错误处理、事件配对、Result 检查、using 歧义
- 服务端：error 处理、Actor 独立性、safego

## 禁止事项
- 禁止编造 API
- 禁止不读代码就修改
- 禁止过度修复
- 禁止将问题标记为'需人工介入'

## 完成声明（Ralph Loop 机制）— 不可跳过
修复完成后，你必须在 ${FIX_LOG} 末尾追加一行：
ALL_FILES_FIXED
这一行表示你已经按照根因分析报告完成了**所有**需要修改的文件。
- 如果只修复了部分文件，**不要写这一行**，而是在 ${FIX_LOG} 中记录已修复和未修复的文件清单。
- 只有当你确信所有需要修改的文件都已完成时，才写 ALL_FILES_FIXED。"

            else
                echo "  [Fix] 修复 Review 问题（基于上轮审查）..."

                FIX_PROMPT="你的任务是根据 Bug Fix Review 报告修复代码。

请读取以下文件：
1. ${REVIEW_FILE} — 上一轮的 Bug Fix Review 报告
2. ${ANALYSIS_FILE} — 根因分析报告（确保修复不偏离根因）

修复规则：
- 逐个修复 Review 报告中的 CRITICAL 和 HIGH 问题
- 修复后对照 P1GoServer/.claude/constitution.md 和 freelifeclient/.claude/constitution.md 做合宪性自检
- 只修复报告中列出的问题，不做额外重构
- MEDIUM 问题可以顺手修复，但不强制
- 重要：Proto 消息类命名空间是 FL.NetModule（不是 FL.Net.Proto）
- 禁止将问题标记为'需人工介入'

客户端修复辅助：
- 如果涉及客户端修复，先读取 Unity Editor.log（C:/Users/admin/AppData/Local/Unity/Editor/Editor.log）确认当前错误状态
- 尝试用 Unity MCP（ToolSearch 搜索 'select:mcp__unityMCP__read_console'）读取 Console 错误，辅助定位问题
- 修复后尝试用 Unity MCP 触发重编译并验证（mcp__unityMCP__refresh_unity），如果 MCP 不可用则跳过"
            fi

            claude -p "$FIX_PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" 2>&1 | tail -15
            echo "| $ROUND | 修复 | - | - | - | done |" >> "$FIX_LOG"

            # ── Ralph Loop：首轮修复后检查完成声明 + 实际变更校验 ──
            if [ "$ROUND" -eq 1 ]; then
                RALPH_MAX=3
                RALPH_ROUND=0
                while [ $RALPH_ROUND -lt $RALPH_MAX ]; do
                    if grep -q "ALL_FILES_FIXED" "$FIX_LOG" 2>/dev/null; then
                        # 补充验证：检查是否有实际文件变更
                        RALPH_DIFF=$(git diff --stat HEAD 2>/dev/null | tail -1 || echo "")
                        if echo "$RALPH_DIFF" | grep -qE '[0-9]+ file'; then
                            echo "  [Ralph] 已确认所有文件修复完成，变更: ${RALPH_DIFF}"
                            break
                        else
                            echo "  [Ralph] WARNING: ALL_FILES_FIXED 标记存在但无实际文件变更，继续修复"
                        fi
                    fi
                    RALPH_ROUND=$((RALPH_ROUND + 1))
                    echo "  [Ralph] 未检测到有效修复完成，继续修复 (${RALPH_ROUND}/${RALPH_MAX})..."

                    RALPH_PROMPT="上一轮修复尚未完成所有需要修改的文件。请继续修复剩余部分。

读取 ${FIX_LOG} 查看已修复和未修复的文件清单，然后继续修复未完成的文件。
读取 ${ANALYSIS_FILE} 确认完整的修复方案。

修复规则同上：最小化修改、先读后改、遵循宪法。
完成后在 ${FIX_LOG} 末尾追加 ALL_FILES_FIXED。
如果仍有无法完成的文件，在 ${FIX_LOG} 中说明原因后也追加 ALL_FILES_FIXED。"

                    claude -p "$RALPH_PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" 2>&1 | tail -15
                    echo "| $ROUND.R${RALPH_ROUND} | Ralph续写 | - | - | - | done |" >> "$FIX_LOG"
                done

                # Ralph 耗尽后最终校验
                if [ $RALPH_ROUND -ge $RALPH_MAX ]; then
                    RALPH_FINAL=$(git diff --stat HEAD 2>/dev/null | tail -1 || echo "")
                    if ! echo "$RALPH_FINAL" | grep -qE '[0-9]+ file'; then
                        echo "  [Ralph] ERROR: 达到最大轮次且无实际文件变更"
                        echo "| 1.R_FAIL | Ralph | - | - | - | 无文件变更 |" >> "$FIX_LOG"
                    fi
                fi
            fi

            # ── 编译验证 + 自动修复 ──
            echo "  [编译验证] ..."
            if ! compile_and_fix; then
                echo "  WARNING: 编译验证未完全通过，继续进入 Review"
                echo "| ${ROUND}.c | 编译验证 | - | - | - | 部分失败 |" >> "$FIX_LOG"
            else
                echo "| ${ROUND}.c | 编译验证 | - | - | - | 通过 |" >> "$FIX_LOG"
            fi

        else
            # ── 偶数轮: Review 修复 ──

            echo "  [Review] 审查修复质量..."

            REVIEW_PROMPT="读取 .claude/commands/bug/fix-review.md 中的完整工作流程，按照其中的步骤执行。

参数（已解析，直接使用）：
- version: ${VERSION}
- feature_name: ${FEATURE}
- analysis_file: ${ANALYSIS_FILE}
- REVIEW_FILE: ${REVIEW_FILE}

自动化模式特殊规则：
1. 完成 Review 后，将完整的 Review 报告写入文件 ${REVIEW_FILE}（覆盖之前的报告）
2. 在报告文件的最后一行，必须追加以下格式的元数据（用于脚本自动解析，不要遗漏）：
   <!-- counts: critical=X high=Y medium=Z -->
   其中 X/Y/Z 替换为实际问题数量
3. 不要询问用户，直接完成 Review 并结束"

            claude -p "$REVIEW_PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" 2>&1 | tail -15

            # 解析 Review 结果
            if [ -f "$REVIEW_FILE" ]; then
                COUNTS_LINE=$(grep -o 'counts: critical=[0-9]* high=[0-9]* medium=[0-9]*' "$REVIEW_FILE" 2>/dev/null | tail -1 || echo "")
                if [ -n "$COUNTS_LINE" ]; then
                    CRITICAL=$(echo "$COUNTS_LINE" | sed 's/.*critical=\([0-9]*\).*/\1/')
                    HIGH=$(echo "$COUNTS_LINE" | sed 's/.*high=\([0-9]*\).*/\1/')
                    MEDIUM=$(echo "$COUNTS_LINE" | sed 's/.*medium=\([0-9]*\).*/\1/')
                else
                    echo "  WARNING: 无法解析 Review 报告中的 counts 元数据"
                    tail -5 "$REVIEW_FILE"
                    CRITICAL=999
                    HIGH=999
                    MEDIUM=0
                fi
            else
                echo "  WARNING: Review 报告未生成: ${REVIEW_FILE}"
                CRITICAL=999
                HIGH=999
                MEDIUM=0
            fi

            CURRENT_TOTAL=$((CRITICAL + HIGH))
            echo "| $ROUND | Review | $CRITICAL | $HIGH | $MEDIUM | done |" >> "$FIX_LOG"
            echo "  Review 结果: Critical=$CRITICAL, High=$HIGH, Medium=$MEDIUM"

            # ── 收敛判断 ──

            if [ "$CRITICAL" -eq 0 ] && [ "$HIGH" -le 2 ]; then
                FIX_REASON="质量达标"
                echo "  PASS: $FIX_REASON (Critical=0, High<=2)"
                break
            fi

            if [ "$PREV_TOTAL" -ge 0 ] && [ "$CURRENT_TOTAL" -ge "$PREV_TOTAL" ]; then
                FIX_REASON="问题未减少"
                echo "  WARN: $FIX_REASON (当前=$CURRENT_TOTAL, 上轮=$PREV_TOTAL)"
                break
            fi

            PREV_TOTAL=$CURRENT_TOTAL

            # ── Medium 趋势追踪（不影响收敛判断，仅增加可见性）──
            if [ "$PREV_MEDIUM" -ge 0 ] && [ "$MEDIUM" -gt "$PREV_MEDIUM" ]; then
                echo "  NOTICE: Medium 问题从 ${PREV_MEDIUM} 增至 ${MEDIUM}，建议关注"
            fi
            PREV_MEDIUM=$MEDIUM
        fi
    done

    if [ -z "$FIX_REASON" ]; then
        FIX_REASON="达到上限"
    fi

    echo "  [阶段二] 修复迭代完成: ${FIX_REASON}"

    # ── 阶段三：经验固化 + 文档更新 ──

    echo "  [阶段三] 经验固化 + 文档更新..."

    SOLIDIFY_PROMPT="你是一名资深全栈游戏开发工程师。请完成以下 Bug 修复的收尾工作。

## Bug 信息
- **版本**：${VERSION}
- **功能模块**：${FEATURE}
- **Bug 描述**：${BUG_TEXT}
- **根因分析报告**：${ANALYSIS_FILE}

## 任务一：经验固化

读取 ${ANALYSIS_FILE}，根据根因分析判断是否需要固化防护。

**判断标准——满足以下任一条件则需要固化：**
1. 模式性 Bug：这类错误在项目中容易反复出现
2. 框架用法陷阱：项目框架的某个 API 容易被误用
3. 隐蔽的约定：某些隐含的项目约定不在现有文档中
4. 第三方行为陷阱：第三方库/引擎的某个行为与直觉不符

**不需要固化的情况：**
1. 一次性的逻辑错误
2. 已有 skill/rule 已覆盖的问题
3. 配置值的简单修正
4. 纯粹的需求理解偏差

**如果需要固化，按以下方式操作：**

| 情况 | 固化方式 | 存放位置 |
|------|---------|---------|
| 编码风格/命名/引用类的通用规则 | 更新 rule | freelifeclient/.claude/rules/ 或 P1GoServer/.claude/rules/ |
| 某个模块/框架的使用陷阱 | 更新已有 skill | 对应 skill 文件 |
| 全新的技术领域知识 | 创建新 skill | freelifeclient/.claude/skills/ 或 P1GoServer/.claude/skills/ |
| 跨端的通用教训 | 更新 rule | 对应端的 .claude/rules/ |

固化内容格式：
\`\`\`markdown
## [陷阱/规则名称]
**问题**：[一句话描述容易犯的错误]
**原因**：[为什么会出错]
**正确做法**：[正确代码示例]
**错误做法**：[错误代码示例]
\`\`\`

先检查现有 skills 和 rules，确认是否已有覆盖此问题的文档再决定。

## 任务二：更新 Bug 文档

**1. 从未修复列表中移除：**
编辑 ${BUG_DOC}，删除已修复的 Bug 条目：${BUG_TEXT}

**2. 追加到已修复记录：**
编辑 ${BUG_DIR}/fixed.md，追加（不存在则创建）：

\`\`\`markdown
## $(date '+%Y-%m-%d')
- [x] ${BUG_TEXT}
  - **根因**：[从分析报告中提取一句话根因]
  - **修复**：[修改的文件和关键改动]
\`\`\`

## 任务三：输出修复报告

最终输出必须包含：

\`\`\`
## Bug 修复报告
### 状态：[已修复 / 修复失败]
### Bug：${BUG_TEXT}
### 根因：[一句话根因]
### 修改文件：
- [文件路径]: [修改概述]
### 固化：[固化了什么 / 不需要固化的理由]
\`\`\`"

    claude -p "$SOLIDIFY_PROMPT" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" 2>&1 | tail -15

    # ── 阶段四：提交修复 ──

    echo "  [阶段四] 提交修复到 Git..."

    # 检查是否有变更需要提交
    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
        COMMIT_MSG="fix(${FEATURE}): 修复 Bug #${BUG_NUM} - ${BUG_TEXT:0:50}"

        claude -p "请使用 /git:commit 命令提交当前所有变更，commit message 为：${COMMIT_MSG}" --allowedTools "Edit,Read,Bash,Grep,Write,Glob,Agent,WebSearch,WebFetch,ToolSearch" 2>&1 | tail -10

        if [ $? -eq 0 ]; then
            echo "  [阶段四] Git commit 完成"
        else
            echo "  WARNING: Git commit 失败，手动提交"
            # 降级：直接用 git 命令提交
            git add -A && git commit -m "${COMMIT_MSG}

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>" 2>&1 | tail -5 || echo "  WARNING: 降级 commit 也失败"
        fi
    else
        echo "  [阶段四] 无变更需要提交"
    fi

    # 写入修复日志总结
    cat >> "$FIX_LOG" << EOF

## 总结
- **总轮次**：$ROUND
- **终止原因**：$FIX_REASON
- **最终质量**：Critical=$CRITICAL, High=$HIGH, Medium=$MEDIUM
- **完成时间**：$(date '+%Y-%m-%d %H:%M:%S')
EOF

    echo "  [完成] Bug #${BUG_NUM} 修复流程结束: ${FIX_REASON}"
    return 0
}

# ══════════════════════════════════════
# 收集待修复 Bug 列表
# ══════════════════════════════════════

collect_bugs() {
    local V="$1"
    local F="$2"
    local BUG_DOC="docs/bugs/${V}/${F}/${F}.md"

    if [ ! -f "$BUG_DOC" ]; then
        echo ""
        return
    fi

    # 提取 "- [ ]" 开头的行（未修复条目）
    grep -E '^\s*-\s*\[ \]' "$BUG_DOC" 2>/dev/null || true
}

# ══════════════════════════════════════
# 主流程
# ══════════════════════════════════════

TOTAL_START=$(date +%s)
TOTAL_FIXED=0
TOTAL_FAILED=0
TOTAL_SKIPPED=0  # reserved
SUMMARY_LINES=""

echo ""
echo "══════════════════════════════════════"
echo "  Bug Fix 自动闭环流程"
echo "  版本: ${VERSION}"
echo "  模块: ${FEATURE_NAME}"
[ -n "$BUG_INDEX" ] && echo "  Bug: #${BUG_INDEX}"
echo "  最大迭代轮次: ${MAX_FIX_ROUNDS}"
echo "══════════════════════════════════════"

# ── 单模块模式 ──

BUG_DOC="docs/bugs/${VERSION}/${FEATURE_NAME}/${FEATURE_NAME}.md"
mkdir -p "docs/bugs/${VERSION}/${FEATURE_NAME}"

    if [ ! -f "$BUG_DOC" ]; then
        echo "ERROR: Bug 文档不存在: ${BUG_DOC}"
        exit 1
    fi

    BUGS=$(collect_bugs "$VERSION" "$FEATURE_NAME")
    if [ -z "$BUGS" ]; then
        echo "当前无待修复 Bug"
        exit 0
    fi

    # 计算 Bug 总数
    BUG_COUNT=$(echo "$BUGS" | grep -c '.' || echo "0")
    echo "发现 ${BUG_COUNT} 个未修复 Bug"

    if [ -n "$BUG_INDEX" ]; then
        # 指定了 Bug 编号，只修复该 Bug
        BUG_LINE=$(echo "$BUGS" | sed -n "${BUG_INDEX}p")
        if [ -z "$BUG_LINE" ]; then
            echo "ERROR: Bug #${BUG_INDEX} 不存在（共 ${BUG_COUNT} 个）"
            exit 1
        fi
        BUG_TEXT=$(echo "$BUG_LINE" | sed 's/^\s*-\s*\[ \]\s*//')
        fix_single_bug "$VERSION" "$FEATURE_NAME" "$BUG_TEXT" "$BUG_INDEX"
    else
        # 修复所有未修复 Bug
        BUG_NUM=0
        while IFS= read -r BUG_LINE; do
            [ -z "$BUG_LINE" ] && continue
            BUG_NUM=$((BUG_NUM + 1))
            BUG_TEXT=$(echo "$BUG_LINE" | sed 's/^\s*-\s*\[ \]\s*//')

            if fix_single_bug "$VERSION" "$FEATURE_NAME" "$BUG_TEXT" "$BUG_NUM"; then
                TOTAL_FIXED=$((TOTAL_FIXED + 1))

                # ── 跨 Bug 回归检查：确认当前 fix 没有破坏编译 ──
                echo "  [回归检查] Bug #${BUG_NUM} 修复后编译验证..."
                if ! verify_server_build || ! verify_client_build; then
                    echo "  WARNING: Bug #${BUG_NUM} 修复后编译状态异常，尝试自动修复..."
                    compile_and_fix || echo "  WARNING: 编译修复失败，后续 Bug 修复可能受影响"
                fi
            else
                TOTAL_FAILED=$((TOTAL_FAILED + 1))
            fi
        done <<< "$BUGS"

        TOTAL_END=$(date +%s)
        TOTAL_DURATION=$((TOTAL_END - TOTAL_START))

        echo ""
        echo "══════════════════════════════════════"
        echo "  修复完成: ${VERSION}/${FEATURE_NAME}"
        echo "══════════════════════════════════════"
        echo "  总 Bug: ${BUG_COUNT}"
        echo "  已修复: ${TOTAL_FIXED}"
        echo "  失败: ${TOTAL_FAILED}"
        echo "  总耗时: ${TOTAL_DURATION}s"
        echo "══════════════════════════════════════"
    fi
