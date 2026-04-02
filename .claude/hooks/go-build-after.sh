#!/bin/bash
# PostToolUse hook: 编辑 .go 文件后自动编译检查
# 仅在编辑 P1GoServer/ 下的 .go 文件时触发

FILE_PATH=$(jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [ -z "$FILE_PATH" ]; then
    exit 0
fi

# 仅对 P1GoServer 下的 .go 文件执行
if echo "$FILE_PATH" | grep -qi 'P1GoServer.*\.go$'; then
    BUILD_OUTPUT=$(cd "$CLAUDE_PROJECT_DIR/P1GoServer" && go build ./... 2>&1)
    BUILD_EXIT=$?
    echo "$BUILD_OUTPUT" | head -20

    # 写入行为追踪日志
    ACTION_LOG="/tmp/.claude_action_log"
    if [ $BUILD_EXIT -eq 0 ]; then
        echo "$(date +%s)|GO_COMPILE_PASS|$FILE_PATH" >> "$ACTION_LOG" 2>/dev/null
    else
        echo "$(date +%s)|GO_COMPILE_FAIL|$FILE_PATH" >> "$ACTION_LOG" 2>/dev/null
    fi
fi
