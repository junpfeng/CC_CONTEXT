#!/bin/bash
# Hook: Stop (command type)
# 在 Claude 停止前检查：如果本次会话修改了客户端 .cs 文件，是否通过 MCP 视觉验证
# 使用 HMAC 签名验证，不是文件存在检查——无法通过 touch 绕过
# exit 0 = 允许停止, exit 2 = 阻止停止（强制继续）

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-E:/workspace/PRJ/P1}"
HOOKS_DIR="$PROJECT_DIR/.claude/hooks"
BASELINE_FILE="/tmp/.cs_baseline_snapshot"

# 读取 stdin
INPUT=$(cat 2>/dev/null || true)

# 防止无限循环
STOP_ACTIVE="false"
if [ -n "$INPUT" ]; then
    STOP_ACTIVE=$(echo "$INPUT" | head -1 | python3 -X utf8 -c "
import sys, json
line = sys.stdin.readline().strip()
if not line:
    print('false')
else:
    try:
        d = json.loads(line)
        print(str(d.get('stop_hook_active', False)).lower())
    except Exception:
        print('false')
" 2>/dev/null || echo "false")
fi
if [ "$STOP_ACTIVE" = "true" ]; then
    exit 0
fi

# 提取 session_id
SESSION_ID=""
if [ -n "$INPUT" ]; then
    SESSION_ID=$(echo "$INPUT" | head -1 | python3 -X utf8 -c "
import sys, json
line = sys.stdin.readline().strip()
if not line:
    print('')
else:
    try:
        d = json.loads(line)
        print(d.get('session_id', ''))
    except Exception:
        print('')
" 2>/dev/null || echo "")
fi

# 获取当前 .cs 变更列表
CURRENT_CS=$(
    {
        git -C "$PROJECT_DIR/freelifeclient" diff --name-only 2>/dev/null
        git -C "$PROJECT_DIR/freelifeclient" diff --cached --name-only 2>/dev/null
        git -C "$PROJECT_DIR/freelifeclient" ls-files --others --exclude-standard 2>/dev/null
    } | grep '\.cs$' | sort -u
)

# 对比基线，只检测本会话新增的变更
if [ -f "$BASELINE_FILE" ]; then
    BASELINE_CS=$(cat "$BASELINE_FILE")
    NEW_CS=$(comm -23 <(echo "$CURRENT_CS") <(echo "$BASELINE_CS"))
else
    NEW_CS="$CURRENT_CS"
fi

# 无新增 .cs 变更，放行
if [ -z "$NEW_CS" ]; then
    exit 0
fi

# 检查是否全部是 codegen 路径（自动放行）
IS_CODEGEN=$(echo "$NEW_CS" | python3 -X utf8 -c "
import sys
codegen_paths = ['Proto/', 'Config/Gen/', 'Managers/Net/Proto/']
files = [l.strip() for l in sys.stdin if l.strip()]
if not files:
    print('yes')
elif all(any(cp in f for cp in codegen_paths) for f in files):
    print('yes')
else:
    print('no')
" 2>/dev/null || echo "no")

if [ "$IS_CODEGEN" = "yes" ]; then
    exit 0
fi

# 有非 codegen 的 .cs 变更，验证 HMAC 签名
if [ -n "$SESSION_ID" ]; then
    python3 -X utf8 "$HOOKS_DIR/mcp_verify_lib.py" validate "$SESSION_ID" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        exit 0
    fi
fi

# 无 session_id 时回退：检查 marker 文件签名格式是否有效（允许任意 session_id）
if [ -z "$SESSION_ID" ] && [ -f "/tmp/.mcp_visual_verified" ]; then
    MARKER_VALID=$(python3 -X utf8 -c "
import sys
sys.path.insert(0, '$HOOKS_DIR')
from mcp_verify_lib import validate_marker
# 无 session_id 时，读取 marker 中记录的 session_id 自验证
import os
content = open('/tmp/.mcp_visual_verified').read().strip()
parts = content.split('|')
if len(parts) == 4:
    from mcp_verify_lib import compute_hmac
    sid, ts, tool, sig = parts
    import hmac as _h
    expected = compute_hmac(sid, ts, tool)
    if _h.compare_digest(sig, expected):
        import time
        age = int(time.time()) - int(ts)
        if age < 1800:
            print('valid')
        else:
            print('expired')
    else:
        print('invalid_sig')
else:
    print('invalid_format')
" 2>/dev/null || echo "invalid")
    if [ "$MARKER_VALID" = "valid" ]; then
        exit 0
    fi
fi

# === MCP 自动恢复链路 ===
# 不立即 BLOCK，先尝试自动恢复 MCP 并完成验证

# 尝试 1: 通过 mcp-fallback-verify.sh 直连 MCP 服务端截图
FALLBACK_SID="${SESSION_ID:-fallback}"
FALLBACK_RESULT=$(bash "$HOOKS_DIR/mcp-fallback-verify.sh" "$FALLBACK_SID" 2>&1)
if [ $? -eq 0 ]; then
    # 写入行为追踪日志
    echo "$(date +%s)|MCP_VERIFY|fallback-auto-recovery" >> "/tmp/.claude_action_log" 2>/dev/null
    exit 0
fi

# 尝试 2: 自动重启 MCP 后重试
RESTART_SCRIPT="$PROJECT_DIR/scripts/unity-restart.ps1"
if [ -f "$RESTART_SCRIPT" ]; then
    powershell.exe -ExecutionPolicy Bypass -File "$RESTART_SCRIPT" > /dev/null 2>&1
    # 等待 MCP 服务恢复
    sleep 12
    RETRY_RESULT=$(bash "$HOOKS_DIR/mcp-fallback-verify.sh" "$FALLBACK_SID" 2>&1)
    if [ $? -eq 0 ]; then
        echo "$(date +%s)|MCP_VERIFY|fallback-after-restart" >> "/tmp/.claude_action_log" 2>/dev/null
        exit 0
    fi
fi

# 所有自动恢复失败，BLOCK 并给出明确指令（不是问用户，而是告诉 Claude 下一步）
echo "客户端有非自动生成的 .cs 文件变更，MCP 验证失败且自动恢复未成功。请执行：1) python3 scripts/mcp_call.py screenshot-game-view '{}' 检查 MCP 服务端状态 2) 若不可达，手动执行 powershell scripts/unity-restart.ps1 重启 Unity+MCP 3) 重启后通过 MCP screenshot 工具验证视觉表现。" >&2
exit 2
