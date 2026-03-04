#!/usr/bin/env bash
#
# claude-git: 管理 Claude 上下文文件的版本控制辅助脚本
#
# 基于 bare repo 模式，自动处理嵌套 .git 目录的临时移除与恢复。
#
# 用法:
#   claude-git add <file|dir> ...    # 添加文件（自动处理嵌套 .git）
#   claude-git scan                  # 扫描未跟踪的上下文文件
#   claude-git <any git command>     # 透传给 git（status/diff/log/commit 等）
#

set -uo pipefail
# 注意：不用 set -e，手动控制错误处理，确保 .git 恢复不受影响

GIT_DIR="$HOME/workspace/claude-context.git"
WORK_TREE="$HOME/workspace/server"

# 备份恢复用的全局变量（确保 trap 能访问）
_BACKUP_DIR=""
declare -A _GIT_DIRS_BACKUP=()

# 基础 git 命令
_git() {
    git --git-dir="$GIT_DIR" --work-tree="$WORK_TREE" "$@"
}

# 清理函数：确保 .git 一定被恢复（全局 trap）
_cleanup() {
    local restored=false
    for git_path in "${!_GIT_DIRS_BACKUP[@]}"; do
        local backup_name="${_GIT_DIRS_BACKUP[$git_path]}"
        if [[ -n "$_BACKUP_DIR" && -d "$_BACKUP_DIR/$backup_name" ]]; then
            mv "$_BACKUP_DIR/$backup_name" "$git_path"
            echo "  已恢复 $git_path"
            restored=true
        fi
    done
    if [[ -n "$_BACKUP_DIR" ]]; then
        rm -rf "$_BACKUP_DIR"
    fi
    _BACKUP_DIR=""
    _GIT_DIRS_BACKUP=()
}
trap _cleanup EXIT

# 找到路径所属的嵌套 .git 目录（如果有）
_find_nested_git() {
    local filepath="$1"
    # 转为绝对路径
    if [[ "$filepath" != /* ]]; then
        filepath="$WORK_TREE/$filepath"
    fi

    local dir
    if [[ -d "$filepath" ]]; then
        dir="$filepath"
    else
        dir="$(dirname "$filepath")"
    fi

    # 从当前目录向上找，到 WORK_TREE 为止
    while [[ "$dir" != "$WORK_TREE" && "$dir" != "/" ]]; do
        if [[ -d "$dir/.git" ]]; then
            echo "$dir/.git"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# 安全地添加文件，自动处理嵌套 .git
cmd_add() {
    if [[ $# -eq 0 ]]; then
        echo "用法: claude-git add <file|dir> ..."
        return 1
    fi

    # 收集需要临时移走的 .git 目录（去重）
    local nested_count=0
    declare -A git_dirs_to_move
    for path in "$@"; do
        local nested_git
        if nested_git=$(_find_nested_git "$path"); then
            git_dirs_to_move["$nested_git"]=1
            nested_count=$((nested_count + 1))
        fi
    done

    # 如果没有嵌套 .git，直接添加（-f 绕过子项目 .gitignore）
    if [[ $nested_count -eq 0 ]]; then
        _git add -f "$@"
        echo "已添加 $# 个路径"
        return 0
    fi

    # 临时目录
    _BACKUP_DIR=$(mktemp -d /tmp/claude-git-backup.XXXXXX)

    # 移走嵌套 .git，同时注册到全局变量供 trap 恢复
    for git_path in "${!git_dirs_to_move[@]}"; do
        local backup_name
        backup_name=$(echo "$git_path" | md5sum | cut -c1-12)
        _GIT_DIRS_BACKUP["$git_path"]="$backup_name"
        mv "$git_path" "$_BACKUP_DIR/$backup_name"
        echo "  临时移走 $git_path"
    done

    # 执行 git add（-f 绕过子项目 .gitignore）
    _git add -f "$@"
    local add_rc=$?

    # 立即恢复 .git（不等 trap）
    for git_path in "${!_GIT_DIRS_BACKUP[@]}"; do
        local backup_name="${_GIT_DIRS_BACKUP[$git_path]}"
        if [[ -d "$_BACKUP_DIR/$backup_name" ]]; then
            mv "$_BACKUP_DIR/$backup_name" "$git_path"
            echo "  已恢复 $git_path"
        fi
    done
    rm -rf "$_BACKUP_DIR"
    _BACKUP_DIR=""
    _GIT_DIRS_BACKUP=()

    if [[ $add_rc -eq 0 ]]; then
        echo "已添加 $# 个路径"
    else
        echo "添加失败（exit $add_rc）" >&2
        return $add_rc
    fi
}

# 扫描未跟踪的上下文文件
cmd_scan() {
    echo "=== 扫描 workspace 中的上下文文件 ==="
    echo ""

    # 当前已跟踪的文件
    local tracked
    tracked=$(_git ls-files)

    local found_new=false

    # 扫描 CLAUDE.md
    while IFS= read -r f; do
        local rel="${f#$WORK_TREE/}"
        if ! echo "$tracked" | grep -qxF "$rel"; then
            echo "  未跟踪: $rel"
            found_new=true
        fi
    done < <(find "$WORK_TREE" -name "CLAUDE.md" -not -path "*/node_modules/*" -not -path "*/.git/*")

    # 扫描 .claude 目录下的文件（排除不纳入版本管理的目录）
    while IFS= read -r f; do
        local rel="${f#$WORK_TREE/}"
        if ! echo "$tracked" | grep -qxF "$rel"; then
            echo "  未跟踪: $rel"
            found_new=true
        fi
    done < <(find "$WORK_TREE" -path "*/.claude/*" -type f \
        -not -path "*/.git/*" \
        -not -name "settings.local.json" \
        -not -path "*/node_modules/*" \
        -not -path "*/.claude/agents/*" \
        -not -path "*/.claude/archive/*" \
        -not -path "*/.claude/designs/*" \
        -not -path "*/.claude/docs/*" \
        -not -path "*/.claude/plans/*")

    # 扫描 claude-mem-doc.md
    while IFS= read -r f; do
        local rel="${f#$WORK_TREE/}"
        if ! echo "$tracked" | grep -qxF "$rel"; then
            echo "  未跟踪: $rel"
            found_new=true
        fi
    done < <(find "$WORK_TREE" -maxdepth 1 -name "claude-mem-doc.md" -type f)

    if [[ "$found_new" == false ]]; then
        echo "  所有上下文文件均已跟踪"
    else
        echo ""
        echo "使用 'claude-git add <path>' 添加新文件"
    fi
}

# 显示帮助
cmd_help() {
    cat << 'HELP'
claude-git — Claude 上下文文件版本控制

专用命令:
  add <path> ...   添加文件/目录（自动处理嵌套 .git 和 .gitignore）
  scan             扫描未跟踪的上下文文件

透传命令（直接转发给 git）:
  status           查看状态
  diff             查看改动
  log              查看历史
  commit           提交
  ...              其他任何 git 命令

示例:
  claude-git scan
  claude-git add <子工程>/CLAUDE.md
  claude-git add .claude/skills/dev-workflow/
  claude-git commit -m "update debug docs"
  claude-git log --oneline
  claude-git diff
HELP
}

# 主入口
main() {
    if [[ $# -eq 0 ]]; then
        cmd_help
        return 0
    fi

    local subcmd="$1"
    shift

    case "$subcmd" in
        add)
            cmd_add "$@"
            ;;
        scan)
            cmd_scan
            ;;
        help|--help|-h)
            cmd_help
            ;;
        *)
            # 透传给 git
            _git "$subcmd" "$@"
            ;;
    esac
}

main "$@"
