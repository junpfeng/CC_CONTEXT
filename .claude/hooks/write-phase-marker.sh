#!/bin/bash
# 由 Skill 工作流调用，写入阶段标记
# 用法: bash .claude/hooks/write-phase-marker.sh autonomous|interactive|clear
# 这是 .claude_phase 的唯一合法写入入口，block-marker-tamper.sh 拦截其他方式

PHASE="$1"

case "$PHASE" in
    autonomous|interactive)
        echo "$PHASE" > /tmp/.claude_phase
        ;;
    clear)
        rm -f /tmp/.claude_phase 2>/dev/null
        rm -f "$(python3 -c 'import tempfile; print(tempfile.gettempdir())')/.bug_explore_metrics_recorded" 2>/dev/null
        ;;
    *)
        echo "Invalid phase: $PHASE. Use: autonomous|interactive|clear" >&2
        exit 1
        ;;
esac
