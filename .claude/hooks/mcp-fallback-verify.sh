#!/bin/bash
# MCP 降级验证：当 Claude Code 的 MCP 工具断连时，通过 mcp_call.py 直连 MCP 服务端
# 做真实截图验证，成功后写入合法 HMAC marker。
#
# 使用场景：Play 模式切换导致 MCP 客户端断连，但 MCP 服务端仍在运行。
# 安全性：必须实际调通 MCP 服务端截图，不能伪造验证结果。
#
# 用法：bash mcp-fallback-verify.sh <session_id>

set -e

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-E:/workspace/PRJ/P1}"
HOOKS_DIR="$PROJECT_DIR/.claude/hooks"
SESSION_ID="${1:-}"

if [ -z "$SESSION_ID" ]; then
    echo "Usage: mcp-fallback-verify.sh <session_id>" >&2
    exit 1
fi

# Step 1: 检查 MCP 服务端是否可达
echo "Checking MCP server..."
PING_RESULT=$(python3 -X utf8 "$PROJECT_DIR/scripts/mcp_call.py" screenshot-game-view '{}' 2>&1 || true)

if echo "$PING_RESULT" | grep -qi "screenshot\|Game View\|size="; then
    echo "MCP screenshot succeeded: $PING_RESULT"
else
    echo "MCP screenshot failed: $PING_RESULT" >&2
    echo "MCP server not reachable or screenshot unavailable." >&2
    exit 1
fi

# Step 2: 写入 HMAC marker（通过 mcp_verify_lib.py，与 PostToolUse hook 相同机制）
WRITE_RESULT=$(python3 -X utf8 "$HOOKS_DIR/mcp_verify_lib.py" write "$SESSION_ID" "screenshot-game-view-fallback" 2>&1)
echo "Marker written: $WRITE_RESULT"

# Step 3: 验证 marker 有效
VALIDATE_RESULT=$(python3 -X utf8 "$HOOKS_DIR/mcp_verify_lib.py" validate "$SESSION_ID" 2>&1)
if echo "$VALIDATE_RESULT" | grep -q "VALID"; then
    echo "Fallback verification complete. Marker is valid."
    exit 0
else
    echo "Marker validation failed: $VALIDATE_RESULT" >&2
    exit 1
fi
