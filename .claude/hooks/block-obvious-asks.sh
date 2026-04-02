#!/bin/bash
# Hook: PreToolUse (command type) on AskUserQuestion
# 确定性前置过滤：硬拦截明显违反自主闭环的提问，不依赖 LLM 判断
# 在 prompt 类型 hook 之前执行，拦截高频违规模式
# exit 0 = 放行（交给后续 prompt hook 判断）, exit 2 = 阻断

INPUT=$(cat 2>/dev/null || true)
if [ -z "$INPUT" ]; then
    exit 0
fi

# 提取提问内容
QUESTION=$(echo "$INPUT" | python3 -X utf8 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {})
    # AskUserQuestion 的参数可能是 question 字段或直接是字符串
    q = ti.get('question', '') if isinstance(ti, dict) else str(ti)
    print(q)
except Exception:
    print('')
" 2>/dev/null || echo "")

if [ -z "$QUESTION" ]; then
    exit 0
fi

# ── 阶段感知拦截 ──
# 支持全局 marker（/tmp/.claude_phase）和 per-feature marker（/tmp/.claude_phase_*）
# 任一 marker 为 autonomous → 拦截；任一为 interactive → 放行；全部缺失 → fallback regex
PHASE_FOUND=""
for PHASE_FILE in /tmp/.claude_phase /tmp/.claude_phase_*; do
    [ -f "$PHASE_FILE" ] || continue
    PHASE=$(cat "$PHASE_FILE" 2>/dev/null | tr -d '[:space:]')
    if [ "$PHASE" = "autonomous" ]; then
        echo "自主执行阶段：禁止一切用户提问。依赖问题按 DDRP 协议处理，其他问题自主判断解决。" >&2
        exit 2
    elif [ "$PHASE" = "interactive" ]; then
        exit 0
    fi
    PHASE_FOUND="1"
done

# 用 Python 做确定性模式匹配（fallback：无阶段信号时生效）
RESULT=$(echo "$QUESTION" | python3 -X utf8 -c "
import sys, re

q = sys.stdin.read().strip()

# === 硬拦截：环境/工具/基础设施问题 ===
infra_patterns = [
    r'MCP.{0,10}(?:断|连不|不可|超时|失败|重启|启动)',
    r'Unity.{0,10}(?:重启|启动|打开|关闭|没有运行|未启动)',
    r'(?:重启|启动).{0,10}(?:MCP|Unity|服务器|Redis|MongoDB|Gateway)',
    r'(?:编译|构建|build).{0,10}(?:失败|错误|不通过)',
    r'(?:环境|端口|连接|网络).{0,10}(?:问题|异常|失败|不可用)',
    r'(?:服务器|进程).{0,10}(?:启动|重启|停止|挂了|崩了)',
]

# === 硬拦截：确认/许可类提问 ===
confirm_patterns = [
    r'是否(?:继续|开始|执行|启动|重启|修复|运行)',
    r'要不要(?:继续|开始|执行|启动|重启|修复)',
    r'(?:可以|能否|能不能)(?:继续|开始|执行)(?:吗|？)',
    r'(?:开始|继续|执行|启动|运行)(?:吗|？)\s*$',
    r'需要我.{0,15}(?:吗|？)\s*$',
    r'要我.{0,15}(?:吗|？)\s*$',
    r'我(?:接下来|下一步|现在)(?:应该|要|该)',
    r'你(?:觉得|认为|希望|想要|倾向)',
]

# === 硬拦截：放弃/等待类 ===
giveup_patterns = [
    r'(?:无法|不能|没法|做不到)(?:完成|解决|修复|处理|继续)',
    r'(?:需要你|等待你|请你)(?:手动|自己|来|帮)',
    r'(?:工具|环境|MCP|Unity)(?:不可用|不支持|有问题)',
    r'超出.{0,5}(?:能力|范围)',
]

for name, patterns in [('INFRA', infra_patterns), ('CONFIRM', confirm_patterns), ('GIVEUP', giveup_patterns)]:
    for pat in patterns:
        if re.search(pat, q):
            print(f'BLOCK:{name}:{pat[:30]}')
            sys.exit(0)

print('PASS')
" 2>/dev/null || echo "PASS")

if [[ "$RESULT" == BLOCK:* ]]; then
    CATEGORY="${RESULT#BLOCK:}"
    case "$CATEGORY" in
        INFRA*)
            echo "自主闭环违规：环境/工具问题必须自主排障解决，不要询问用户。参考 CLAUDE.md 和 scripts/ 目录中的工具。" >&2
            ;;
        CONFIRM*)
            echo "自主闭环违规：能判断的直接做，不要询问确认。只有业务需求模糊时才可以询问。" >&2
            ;;
        GIVEUP*)
            echo "自主闭环违规：遇到问题自主解决，不要声明无法完成或等待用户介入。" >&2
            ;;
    esac
    exit 2
fi

exit 0
