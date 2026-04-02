#!/bin/bash
# Hook: PreToolUse/Bash (command type)
# 拦截任何试图手动创建/修改受保护 marker 文件的 Bash 命令
# 只拦截写入操作（echo/touch/rm/cp/mv/python写入等），放行只读操作（grep/cat/read等）
# exit 0 = 允许, exit 2 = 阻止

INPUT=$(cat 2>/dev/null || true)

if [ -z "$INPUT" ]; then
    exit 0
fi

RESULT=$(echo "$INPUT" | python3 -X utf8 -c "
import sys, json, re

try:
    d = json.load(sys.stdin)
    cmd = d.get('tool_input', {}).get('command', '')
except Exception:
    cmd = ''

if not cmd:
    print('PASS')
    sys.exit(0)

# 写入指示符：命令中同时包含受保护文件名和这些模式时才拦截
WRITE_INDICATORS = re.compile(
    r'(?:>\s|>>|touch\s|rm\s|rm\s+-|mv\s|cp\s|tee\s|dd\s|truncate\s|python3?\s+-c|open\()'
)

# 受保护的文件模式及其对应的白名单和错误消息
PROTECTED = [
    {
        'pattern': r'\.mcp_visual_verified|\.mcp_verify|mcp_verify_marker',
        'whitelist': None,  # 无白名单
        'msg': '禁止手动创建/修改 MCP 验收 marker 文件。验收 marker 只能由 MCP 视觉工具调用后自动生成。请通过 MCP 截图工具进行视觉验证。',
    },
    {
        'pattern': r'\.claude_phase|claude_phase',
        'whitelist': 'write-phase-marker.sh',
        'msg': '禁止手动修改阶段标记文件 .claude_phase。必须通过 bash .claude/hooks/write-phase-marker.sh <phase> 写入。',
    },
    {
        'pattern': r'\.bug_explore_metrics_recorded',
        'whitelist': 'record-metrics.py',
        'msg': '禁止手动创建/修改 bug-explore 指标标记文件。该文件只能由 record-metrics.py 自动生成。',
    },
]

# 对每条命令（用 && 或 ; 分隔的子命令逐一检查）
# 但先做整体匹配：如果整个命令不含受保护模式，直接放行
for rule in PROTECTED:
    if not re.search(rule['pattern'], cmd, re.IGNORECASE):
        continue
    # 命令中包含受保护文件名，检查是否有写入指示符
    if not WRITE_INDICATORS.search(cmd):
        continue  # 只读操作（grep/cat 等），放行
    # 检查白名单
    if rule['whitelist'] and rule['whitelist'] in cmd:
        continue
    # 有写入指示符、非白名单 → 拦截
    print('BLOCK:' + rule['msg'])
    sys.exit(0)

print('PASS')
" 2>/dev/null || echo "PASS")

if [[ "$RESULT" == BLOCK:* ]]; then
    MSG="${RESULT#BLOCK:}"
    echo "$MSG" >&2
    exit 2
fi

exit 0
