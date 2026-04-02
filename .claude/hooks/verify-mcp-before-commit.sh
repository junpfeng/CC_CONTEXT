#!/bin/bash
# Hook: PreToolUse/Bash (command type)
# 在 git commit 之前检查是否做过 MCP 视觉验证（HMAC 签名验证）
# if: Bash(git commit*)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-E:/workspace/PRJ/P1}"
HOOKS_DIR="$PROJECT_DIR/.claude/hooks"

INPUT=$(cat 2>/dev/null || true)

if [ -z "$INPUT" ]; then
    exit 0
fi

# 只拦截 git commit 命令，其他 Bash 命令放行
TOOL_INPUT=$(echo "$INPUT" | python3 -X utf8 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

if ! echo "$TOOL_INPUT" | grep -q "git commit"; then
    exit 0
fi

# 提取 session_id
SESSION_ID=$(echo "$INPUT" | python3 -X utf8 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('session_id', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

# 检查是否有客户端 .cs 文件变更
# 从 git commit 命令中提取工作目录（cd 到的目录），判断是否在 freelifeclient 中
COMMIT_DIR=$(echo "$TOOL_INPUT" | grep -oP '(?<=cd\s)[^\s&;]+' | head -1)
if [ -n "$COMMIT_DIR" ] && ! echo "$COMMIT_DIR" | grep -q "freelifeclient"; then
    # commit 不在 freelifeclient 仓库，跳过 .cs 检查
    exit 0
fi
HAS_NON_CODEGEN=false
CS_FILES=$(
    {
        git -C "$PROJECT_DIR/freelifeclient" diff --cached --name-only 2>/dev/null
        git -C "$PROJECT_DIR/freelifeclient" diff --name-only 2>/dev/null
    } | grep '\.cs$' | sort -u
)

if [ -z "$CS_FILES" ]; then
    exit 0
fi

# 检查是否全部是 codegen 路径
IS_CODEGEN=$(echo "$CS_FILES" | python3 -X utf8 -c "
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

# 有非 codegen .cs 变更，验证签名 marker
if [ -n "$SESSION_ID" ]; then
    python3 -X utf8 "$HOOKS_DIR/mcp_verify_lib.py" validate "$SESSION_ID" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        exit 0
    fi
fi

# 无 session_id 回退：自验证 marker 签名
if [ -f "/tmp/.mcp_visual_verified" ]; then
    MARKER_VALID=$(python3 -X utf8 -c "
content = open('/tmp/.mcp_visual_verified').read().strip()
parts = content.split('|')
if len(parts) == 4:
    import sys; sys.path.insert(0, '$HOOKS_DIR')
    from mcp_verify_lib import compute_hmac
    import hmac, time
    sid, ts, tool, sig = parts
    expected = compute_hmac(sid, ts, tool)
    if hmac.compare_digest(sig, expected) and (int(time.time()) - int(ts)) < 1800:
        print('valid')
    else:
        print('invalid')
else:
    print('invalid')
" 2>/dev/null || echo "invalid")
    if [ "$MARKER_VALID" = "valid" ]; then
        exit 0
    fi
fi

echo "客户端有非自动生成的 .cs 文件变更，但未检测到有效的 MCP 视觉验收记录。请先通过 MCP 截图工具验证视觉表现，确认无误后再提交。" >&2
exit 2
