#!/bin/bash
# Hook: SessionStart (command type)
# 记录会话开始时 freelifeclient/ 的 .cs 变更基线快照
# 供 verify-mcp-before-stop.sh 对比，区分本会话 vs 历史遗留变更

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-E:/workspace/PRJ/P1}"
BASELINE_FILE="/tmp/.cs_baseline_snapshot"

# 刷新 git index，确保状态准确
git -C "$PROJECT_DIR/freelifeclient" update-index -q --refresh 2>/dev/null

# 记录当前所有 .cs 变更（已暂存 + 未暂存 + untracked）
{
    git -C "$PROJECT_DIR/freelifeclient" diff --name-only 2>/dev/null
    git -C "$PROJECT_DIR/freelifeclient" diff --cached --name-only 2>/dev/null
    git -C "$PROJECT_DIR/freelifeclient" ls-files --others --exclude-standard 2>/dev/null
} | grep '\.cs$' | sort -u > "$BASELINE_FILE"

# 初始化行为追踪日志（清空上次会话的记录）
ACTION_LOG="/tmp/.claude_action_log"
echo "# Session started at $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$ACTION_LOG"

# 清理残留的阶段信号（防止上次会话崩溃后遗留 autonomous 状态）
rm -f /tmp/.claude_phase 2>/dev/null

echo "CS baseline snapshot saved: $(wc -l < "$BASELINE_FILE") files"
