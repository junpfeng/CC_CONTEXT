#!/bin/bash
# Hook: PostToolUse (command type)
# MCP 视觉工具调用成功后，自动写入签名 marker
# matcher: mcp__ai-game-developer__screenshot-game-view|screenshot-scene-view|script-execute

HOOKS_DIR="$(cd "$(dirname "$0")" && pwd)"
INPUT=$(cat 2>/dev/null || true)

if [ -z "$INPUT" ]; then
    exit 0
fi

# 从 hook stdin 提取 session_id 和 tool_name
RESULT=$(echo "$INPUT" | python3 -X utf8 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    sid = d.get('session_id', '')
    tool = d.get('tool_name', '')
    print(f'{sid}|{tool}')
except Exception:
    print('|')
" 2>/dev/null || echo "|")

SESSION_ID="${RESULT%%|*}"
TOOL_NAME="${RESULT#*|}"

if [ -z "$SESSION_ID" ] || [ -z "$TOOL_NAME" ]; then
    exit 0
fi

# 检查是否是视觉验证工具
IS_VISUAL=$(python3 -X utf8 -c "
tools = ['screenshot-game-view', 'screenshot-scene-view', 'script-execute']
name = '$TOOL_NAME'
print('yes' if any(t in name for t in tools) else 'no')
" 2>/dev/null || echo "no")

if [ "$IS_VISUAL" != "yes" ]; then
    exit 0
fi

# 写入签名 marker
python3 -X utf8 "$HOOKS_DIR/mcp_verify_lib.py" write "$SESSION_ID" "$TOOL_NAME" > /dev/null 2>&1

# 写入行为追踪日志
ACTION_LOG="/tmp/.claude_action_log"
echo "$(date +%s)|MCP_VERIFY|$TOOL_NAME" >> "$ACTION_LOG" 2>/dev/null

exit 0
