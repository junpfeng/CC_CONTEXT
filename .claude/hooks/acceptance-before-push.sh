#!/bin/bash
# Hook: PreToolUse on Bash
# git push 前检查验收报告，未通过则阻断推送
#
# 双路径检查：
# 1. docs/version/*/*/acceptance-report.md — new-feature 验收报告（有 [FAIL] → 阻断）
# 2. docs/version/*/*/acceptance-bug-map.md — dev-debug 修复进度（有 OPEN → 阻断）
# 3. docs/bugs/*/*/*.md — 关联的 bug 追踪（有未勾选 [ ] 且来自验收 → 阻断）
# 4. 无相关文件 → 放行（非 new-feature 工作流）

# 只拦截 git push 命令
TOOL_INPUT="$CLAUDE_TOOL_INPUT"
if ! echo "$TOOL_INPUT" | grep -q "git push"; then
    exit 0
fi

PROJECT_DIR="$CLAUDE_PROJECT_DIR"
VERSION_DIR="$PROJECT_DIR/docs/version"
BUGS_DIR="$PROJECT_DIR/docs/bugs"

if [ ! -d "$VERSION_DIR" ]; then
    exit 0
fi

# ── 检查 1: acceptance-report.md 中的 [FAIL] ──
RECENT_REPORTS=$(find "$VERSION_DIR" -name "acceptance-report.md" -mmin -120 2>/dev/null)

for report in $RECENT_REPORTS; do
    FEATURE_DIR=$(dirname "$report")
    FEATURE_NAME=$(basename "$FEATURE_DIR")

    # 有 override 标记 → 跳过此功能
    if [ -f "$FEATURE_DIR/.acceptance-override" ]; then
        echo "INFO: 功能 [$FEATURE_NAME] 验收有遗留项，已通过 .acceptance-override 确认跳过。"
        continue
    fi

    FAIL_COUNT=$(grep -c '\[FAIL\]' "$report" 2>/dev/null || echo "0")
    if [ "$FAIL_COUNT" -gt 0 ]; then
        echo "BLOCKED: 功能 [$FEATURE_NAME] 验收报告中有 $FAIL_COUNT 个未通过项。"
        echo "报告: $report"
        echo ""
        grep '\[FAIL\]' "$report" 2>/dev/null | head -5
        echo ""
        echo "请先修复所有 FAIL 项后再推送。"
        echo "如需跳过: touch $FEATURE_DIR/.acceptance-override"
        exit 2
    fi

    UNRESOLVED_COUNT=$(grep -c '\[UNRESOLVED\]' "$report" 2>/dev/null || echo "0")
    if [ "$UNRESOLVED_COUNT" -gt 0 ]; then
        echo "BLOCKED: 功能 [$FEATURE_NAME] 有 $UNRESOLVED_COUNT 个验收项在 5 轮修复后仍未通过。"
        echo "报告: $report"
        echo ""
        grep '\[UNRESOLVED\]' "$report" 2>/dev/null | head -5
        echo ""
        echo "如需跳过: touch $FEATURE_DIR/.acceptance-override"
        exit 2
    fi
done

# ── 检查 2: acceptance-bug-map.md 中的 OPEN 状态（dev-debug 修复进行中） ──
PENDING_MAPS=$(find "$VERSION_DIR" -name "acceptance-bug-map.md" -mmin -120 2>/dev/null)

for map_file in $PENDING_MAPS; do
    FEATURE_DIR=$(dirname "$map_file")
    FEATURE_NAME=$(basename "$FEATURE_DIR")

    if [ -f "$FEATURE_DIR/.acceptance-override" ]; then
        continue
    fi

    # 有 bug-map 但没有 report → 修复进行中
    if [ ! -f "$FEATURE_DIR/acceptance-report.md" ]; then
        OPEN_COUNT=$(grep -c '| OPEN' "$map_file" 2>/dev/null || echo "0")
        if [ "$OPEN_COUNT" -gt 0 ]; then
            echo "BLOCKED: 功能 [$FEATURE_NAME] 有 $OPEN_COUNT 个验收 Bug 待修复（dev-debug 进行中）。"
            echo "映射表: $map_file"
            echo "请等待修复完成并生成验收报告后再推送。"
            echo "如需跳过: touch $FEATURE_DIR/.acceptance-override"
            exit 2
        fi
    fi
done

# ── 检查 3: DDRP 依赖未解决（status: open 的 ddrp-req 文件） ──
DDRP_OPEN=0
DDRP_NAMES=""
while IFS= read -r ddrp_file; do
    if grep -q 'status: open' "$ddrp_file" 2>/dev/null; then
        DDRP_OPEN=$((DDRP_OPEN + 1))
        NAME=$(grep '^# DDRP-REQ:' "$ddrp_file" 2>/dev/null | head -1 | sed 's/^# DDRP-REQ: *//')
        DDRP_NAMES="${DDRP_NAMES:+${DDRP_NAMES}, }${NAME}"
    fi
done < <(find "$PROJECT_DIR/docs/version" -name "ddrp-req-*.md" 2>/dev/null)

if [ "$DDRP_OPEN" -gt 0 ]; then
    echo "BLOCKED: 存在 $DDRP_OPEN 个未解决的 DDRP 依赖：${DDRP_NAMES}" >&2
    echo "必须实现或标记 failed 后才能推送。" >&2
    exit 2
fi

# ── 检查 4: 跨 feature 回归风险（仅 WARNING，不阻断） ──
REGRESSION_INDEX="$PROJECT_DIR/docs/regression-index.md"
if [ -f "$REGRESSION_INDEX" ]; then
    # 获取本次推送涉及的变更文件
    CHANGED_FILES=$(git diff --name-only HEAD~1 2>/dev/null)
    if [ -z "$CHANGED_FILES" ]; then
        CHANGED_FILES=$(git diff --cached --name-only 2>/dev/null)
    fi

    if [ -n "$CHANGED_FILES" ]; then
        # 从 regression-index.md 提取模块路径模式和关联 feature
        # 格式: | 模块路径模式 | 关联 Feature | 关键验收项 |
        WARNED_FEATURES=""
        while IFS='|' read -r _ pattern features _ ; do
            pattern=$(echo "$pattern" | xargs)  # trim whitespace
            [ -z "$pattern" ] && continue
            [[ "$pattern" == "模块路径模式" ]] && continue
            [[ "$pattern" == "-"* ]] && continue

            # 检查变更文件是否匹配模块路径
            MATCHED=false
            while IFS= read -r changed_file; do
                if echo "$changed_file" | grep -q "$pattern"; then
                    MATCHED=true
                    break
                fi
            done <<< "$CHANGED_FILES"

            if [ "$MATCHED" = true ]; then
                features=$(echo "$features" | xargs)
                # 逐个检查关联 feature 的验收状态
                IFS=',' read -ra FEATURE_LIST <<< "$features"
                for feat in "${FEATURE_LIST[@]}"; do
                    feat=$(echo "$feat" | xargs)
                    [ -z "$feat" ] && continue
                    [[ "$feat" == "(ALL)" ]] && continue

                    # 跳过已警告的 feature
                    echo "$WARNED_FEATURES" | grep -q "$feat" && continue

                    # 查找该 feature 最近的验收报告
                    FEAT_REPORTS=$(find "$VERSION_DIR" -path "*/$feat/acceptance-report.md" 2>/dev/null)
                    for feat_report in $FEAT_REPORTS; do
                        FEAT_FAIL=$(grep -c '\[FAIL\]\|\[UNRESOLVED\]' "$feat_report" 2>/dev/null || echo "0")
                        if [ "$FEAT_FAIL" -gt 0 ]; then
                            echo "WARNING: 变更涉及共享模块 [$pattern]，关联功能 [$feat] 验收有 $FEAT_FAIL 个未通过项。"
                            echo "  报告: $feat_report"
                            WARNED_FEATURES="$WARNED_FEATURES $feat"
                        fi
                    done
                done
            fi
        done < <(grep '|' "$REGRESSION_INDEX" | tail -n +3)
    fi
fi

exit 0
