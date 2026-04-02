#!/usr/bin/env bash
# claude-headless.sh — 非交互式运行 Claude Code，实时显示执行过程，默认跳过所有权限确认
#
# 用法:
#   ./scripts/claude-headless.sh "你的任务描述"
#   ./scripts/claude-headless.sh "任务描述" --max-turns 5
#   ./scripts/claude-headless.sh "任务描述" --safe              # 不跳过权限，需手动确认
#   ./scripts/claude-headless.sh "任务描述" --allowedTools "Read,Grep"
#
# 日志自动保存到 logs/claude-headless-<时间戳>.json

set -uo pipefail  # 不用 -e，避免 claude 非零退出时脚本直接崩

if [ "$#" -lt 1 ]; then
    echo "用法: $0 \"任务描述\" [额外claude参数...]"
    echo ""
    echo "示例:"
    echo "  $0 \"检查代码中的 bug\""
    echo "  $0 \"重构 auth 模块\" --max-turns 5"
    echo "  $0 \"分析日志\" --safe                    # 安全模式，不跳过权限"
    echo "  $0 \"分析日志\" --allowedTools \"Read,Grep\""
    exit 1
fi

PROMPT="$1"
shift  # 剩余参数传给 claude

# 检查依赖 — winget 安装的 jq 可能不在 bash PATH 中，自动补全
_winget_local="$HOME/AppData/Local/Microsoft/WinGet"
for _p in \
    "$_winget_local/Links" \
    "$_winget_local/Packages"/jqlang.jq_*/; do
    [ -d "$_p" ] && PATH="$PATH:$_p"
done
unset _p _winget_local
if ! command -v jq &>/dev/null; then
    echo "错误: 需要 jq 来解析 stream-json 输出"
    echo "安装: winget install jqlang.jq  或  choco install jq"
    exit 1
fi
if ! command -v claude &>/dev/null; then
    echo "错误: claude 命令未找到，请确认 Claude Code CLI 已安装并在 PATH 中"
    exit 1
fi

# 解析 --safe 标志
SKIP_PERMISSIONS=true
EXTRA_ARGS=()
for arg in "$@"; do
    if [ "$arg" = "--safe" ]; then
        SKIP_PERMISSIONS=false
    else
        EXTRA_ARGS+=("$arg")
    fi
done
set -- "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"

# 创建日志目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="$SCRIPT_DIR/../logs"
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/claude-headless-${TIMESTAMP}.json"
ERR_FILE="$LOG_DIR/claude-headless-${TIMESTAMP}.err"

PERM_LABEL="跳过权限确认"
PERM_ARGS=()
if [ "$SKIP_PERMISSIONS" = true ]; then
    PERM_ARGS+=("--dangerously-skip-permissions")
else
    PERM_LABEL="安全模式（需手动确认权限）"
fi

echo "========================================"
echo "  Claude Code 非交互式执行"
echo "========================================"
echo "  任务: $PROMPT"
echo "  权限: $PERM_LABEL"
echo "  日志: $LOG_FILE"
echo "  额外参数: $*"
echo "========================================"
echo ""

# 运行 claude，stream-json 输出
# tee 同时写日志，单次 jq 流式解析（避免 while+fork 在 Git Bash 下极慢）
JQ_FILTER='
def color(c; s): "\u001b[\(c)m\(s)\u001b[0m";
def trunc(n): if length > n then .[0:n] + "..." else . end;

if .type == "assistant" then
    (.message.content[]? |
        if .type == "thinking" then
            color("90"; "[思考] " + (.thinking // "" | trunc(200)))
        elif .type == "text" then
            .text // empty
        elif .type == "tool_use" then
            color("36"; "[工具] \(.name) → \(.input | tostring | trunc(120))")
        else empty end
    )
elif .type == "result" then
    "\n========================================\n  执行完成\n========================================",
    (.result // empty),
    color("90"; "[tokens: 输入 \(.usage.input_tokens // "?") / 输出 \(.usage.output_tokens // "?")]")
else empty end
'

claude -p "$PROMPT" \
    --output-format stream-json \
    --verbose \
    "${PERM_ARGS[@]+"${PERM_ARGS[@]}"}" \
    "$@" \
    2>"$ERR_FILE" \
    | tee "$LOG_FILE" \
    | jq --unbuffered -r "$JQ_FILTER" 2>/dev/null || true

# 检查 stderr 是否有内容
if [ -s "$ERR_FILE" ]; then
    echo ""
    echo -e "\033[33m[stderr 输出]\033[0m"
    cat "$ERR_FILE"
fi

echo ""
echo "完整日志已保存: $LOG_FILE"
if [ -s "$ERR_FILE" ]; then
    echo "错误日志: $ERR_FILE"
else
    rm -f "$ERR_FILE"
fi
