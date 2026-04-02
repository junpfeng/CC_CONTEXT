#!/bin/bash
# pre-review-check.sh
# 在 AI Review 之前自动扫描已知机械性规则违规，减少 Review 发现的 HIGH 数量
#
# 用法: bash .claude/scripts/pre-review-check.sh <feature_dir> [task_file]
# 输出: 违规列表（带 PRE_REVIEW_ISSUES_FOUND=N 头部）
# 退出码: 0=无问题, 1=发现问题

FEATURE_DIR="${1:-}"
TASK_FILE="${2:-}"

ISSUES=()

# ── 扫描范围：优先用 git diff 找改动文件，失败则全量扫 ──
GO_FILES=()
CS_FILES=()

# 尝试从 git 获取改动文件列表
if [ -d "P1GoServer/.git" ]; then
    while IFS= read -r f; do
        [[ "$f" == *.go ]] && GO_FILES+=("P1GoServer/$f")
    done < <(git -C P1GoServer diff --name-only HEAD 2>/dev/null; git -C P1GoServer diff --name-only --cached 2>/dev/null)
fi
if [ -d "freelifeclient/.git" ]; then
    while IFS= read -r f; do
        [[ "$f" == *.cs ]] && CS_FILES+=("freelifeclient/$f")
    done < <(git -C freelifeclient diff --name-only HEAD 2>/dev/null; git -C freelifeclient diff --name-only --cached 2>/dev/null)
fi

# git 没有结果时退化为全量扫（仍然很快）
if [ ${#GO_FILES[@]} -eq 0 ] && [ -d "P1GoServer" ]; then
    mapfile -t GO_FILES < <(find P1GoServer -name "*.go" -not -path "*/vendor/*" -not -path "*_test.go" 2>/dev/null | head -200)
fi
if [ ${#CS_FILES[@]} -eq 0 ] && [ -d "freelifeclient/Assets" ]; then
    mapfile -t CS_FILES < <(find freelifeclient/Assets/Scripts -name "*.cs" 2>/dev/null | head -300)
fi

# ══════════════════════════════════════
# lesson-003: C# 日志禁止 $"" 字符串插值
# ══════════════════════════════════════
if [ ${#CS_FILES[@]} -gt 0 ]; then
    while IFS= read -r hit; do
        ISSUES+=("[CS-LOG-INTERP] $hit  ← MLog 使用了 \$\"\" 插值，改用 + 拼接")
    done < <(grep -n 'MLog[^;]*\$"' "${CS_FILES[@]}" 2>/dev/null | head -20)
fi

# ══════════════════════════════════════
# lesson-005: Go 日志禁止 %d/%s 格式符
# ══════════════════════════════════════
if [ ${#GO_FILES[@]} -gt 0 ]; then
    while IFS= read -r hit; do
        ISSUES+=("[GO-FMT] $hit  ← 日志含 %d 或 %s，改用 %v")
    done < <(grep -n 'log\(f\)\?\.\(Info\|Debug\|Warn\|Error\)[^)]*%[ds]' "${GO_FILES[@]}" 2>/dev/null | head -20)

    # lesson-005: NPC 字段命名（entityID= / cfgId= 在日志中）
    while IFS= read -r hit; do
        ISSUES+=("[GO-FIELD] $hit  ← 日志字段名应为 npc_entity_id= / npc_cfg_id=")
    done < <(grep -n '\(entityID=\|cfgId=\)' "${GO_FILES[@]}" 2>/dev/null | head -20)
fi

# ══════════════════════════════════════
# lesson-001: using FL.NetModule 缺少 Vector3 alias
# ══════════════════════════════════════
if [ ${#CS_FILES[@]} -gt 0 ]; then
    for f in "${CS_FILES[@]}"; do
        if grep -q "using FL.NetModule" "$f" 2>/dev/null; then
            if ! grep -q "Vector3\s*=" "$f" 2>/dev/null; then
                ISSUES+=("[CS-ALIAS] $f  ← using FL.NetModule 但缺少 Vector3 alias 消歧义")
            fi
        fi
    done
fi

# ══════════════════════════════════════
# lesson-002: 角度变量无单位后缀（仅检查明显的无后缀 heading/angle）
# ══════════════════════════════════════
if [ ${#CS_FILES[@]} -gt 0 ]; then
    while IFS= read -r hit; do
        # 只报告函数参数/局部变量声明中的无后缀 heading/angle（排除注释行）
        ISSUES+=("[CS-ANGLE] $hit  ← 角度变量无 Deg/Rad 后缀，需标明单位")
    done < <(grep -n '\bfloat\s\+heading\b\|\bfloat\s\+angle\b\|\bfloat\s\+yaw\b' "${CS_FILES[@]}" 2>/dev/null | grep -v '//' | head -10)
fi

# ══════════════════════════════════════
# 输出结果
# ══════════════════════════════════════
COUNT=${#ISSUES[@]}

echo "PRE_REVIEW_ISSUES_FOUND=${COUNT}"

if [ "$COUNT" -gt 0 ]; then
    echo "--- 机械性规则违规清单（共 ${COUNT} 条）---"
    for issue in "${ISSUES[@]}"; do
        echo "$issue"
    done
    exit 1
else
    echo "--- 无机械性规则违规 ---"
    exit 0
fi
