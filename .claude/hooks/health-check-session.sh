#!/bin/bash
# SessionStart hook: run workspace health check at session start
# 清理上次会话残留的阶段标记（防止 autonomous 状态泄漏到新会话）
rm -f /tmp/.claude_phase 2>/dev/null
TEMP_DIR=$(python3 -c 'import tempfile; print(tempfile.gettempdir())' 2>/dev/null || echo "/tmp")
rm -f "$TEMP_DIR/.bug_explore_metrics_recorded" 2>/dev/null

exec bash "$CLAUDE_PROJECT_DIR/scripts/health-check.sh" 2>&1
