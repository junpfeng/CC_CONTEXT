#!/bin/bash
# PostToolUse hook (Bash matcher): 检测 go test 执行结果并写入 action log
# 当 Bash 命令包含 go test 且成功时，记录 GO_TEST_PASS marker

INPUT=$(cat 2>/dev/null || true)
if [ -z "$INPUT" ]; then
    exit 0
fi

# 提取 Bash 命令内容
COMMAND=$(echo "$INPUT" | python3 -X utf8 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    cmd = d.get('tool_input', {}).get('command', '') if isinstance(d.get('tool_input'), dict) else str(d.get('tool_input', ''))
    print(cmd)
except Exception:
    print('')
" 2>/dev/null || echo "")

# 只关注 go test 命令
if ! echo "$COMMAND" | grep -q "go test"; then
    exit 0
fi

# 提取执行结果（tool_result 中的 exit_code）
EXIT_CODE=$(echo "$INPUT" | python3 -X utf8 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # PostToolUse 提供 tool_result
    result = d.get('tool_result', {})
    if isinstance(result, dict):
        print(result.get('exit_code', result.get('exitCode', '1')))
    else:
        # 如果 tool_result 是字符串，检查是否包含 PASS
        r = str(result)
        print('0' if 'PASS' in r and 'FAIL' not in r else '1')
except Exception:
    print('1')
" 2>/dev/null || echo "1")

ACTION_LOG="/tmp/.claude_action_log"
if [ "$EXIT_CODE" = "0" ]; then
    echo "$(date +%s)|GO_TEST_PASS|$COMMAND" >> "$ACTION_LOG" 2>/dev/null
else
    echo "$(date +%s)|GO_TEST_FAIL|$COMMAND" >> "$ACTION_LOG" 2>/dev/null
fi

exit 0
