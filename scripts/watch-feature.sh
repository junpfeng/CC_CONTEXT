#!/usr/bin/env bash
# watch-feature.sh — 后台 feature 进度监控
#
# 用法:
#   bash scripts/watch-feature.sh <feature_name> [version]   # 启动后台监控
#   bash scripts/watch-feature.sh --show                      # 前台查看（Ctrl+C 退出查看，监控继续）
#   bash scripts/watch-feature.sh --stop                      # 停止后台监控
#   bash scripts/watch-feature.sh --status                    # 一次性打印当前状态
#
# 原理: 后台进程每 5 秒刷新状态写入 /tmp/feature-watch.log
#        --show 用 tail -f 查看，Ctrl+C 只退出 tail，后台进程不受影响

set -euo pipefail
WATCH_PID_FILE="/tmp/feature-watch.pid"
WATCH_LOG="/tmp/feature-watch.log"
PROJECT_ROOT="E:/workspace/PRJ/P1"

# ─── 颜色 ───
if [[ -t 1 ]] || [[ "${1:-}" == "--show" ]]; then
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
  CYAN='\033[0;36m'; RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'
else
  GREEN=''; YELLOW=''; BLUE=''; CYAN=''; RED=''; BOLD=''; RESET=''
fi

# ─── --show: 前台查看 ───
if [[ "${1:-}" == "--show" ]]; then
  if [[ ! -f "$WATCH_PID_FILE" ]]; then
    echo "没有运行中的监控。用 bash scripts/watch-feature.sh <feature_name> 启动。"
    exit 1
  fi
  PID=$(cat "$WATCH_PID_FILE")
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "监控进程已退出（PID $PID）。最后状态:"
    cat "$WATCH_LOG" 2>/dev/null
    rm -f "$WATCH_PID_FILE"
    exit 1
  fi
  echo -e "${CYAN}监控运行中 (PID $PID)。Ctrl+C 退出查看，监控继续运行。${RESET}"
  echo "───────────────────────────────────────"
  tail -f "$WATCH_LOG"
  exit 0
fi

# ─── --stop: 停止 ───
if [[ "${1:-}" == "--stop" ]]; then
  if [[ -f "$WATCH_PID_FILE" ]]; then
    PID=$(cat "$WATCH_PID_FILE")
    kill "$PID" 2>/dev/null && echo "已停止监控 (PID $PID)" || echo "进程已退出"
    rm -f "$WATCH_PID_FILE"
  else
    echo "没有运行中的监控。"
  fi
  exit 0
fi

# ─── --status: 一次性打印 ───
if [[ "${1:-}" == "--status" ]]; then
  if [[ -f "$WATCH_LOG" ]]; then
    cat "$WATCH_LOG"
  else
    echo "无监控日志。"
  fi
  exit 0
fi

# ─── 参数解析 ───
FEATURE_NAME="${1:?用法: bash scripts/watch-feature.sh <feature_name> [version]}"
VERSION="${2:-0.0.4}"
FEATURE_DIR="${PROJECT_ROOT}/docs/version/${VERSION}/${FEATURE_NAME}"

if [[ ! -d "$FEATURE_DIR" ]]; then
  echo "找不到功能目录: $FEATURE_DIR"
  exit 1
fi

# 如果已有监控在跑，先停掉
if [[ -f "$WATCH_PID_FILE" ]]; then
  OLD_PID=$(cat "$WATCH_PID_FILE")
  kill "$OLD_PID" 2>/dev/null || true
fi

# ─── 渲染函数 ───
render_status() {
  local PROGRESS_FILE="${FEATURE_DIR}/progress.json"
  local output=""

  # 标题
  output+="$(printf '%b' "${BOLD}═══ ${FEATURE_NAME} 开发监控 ═══${RESET}")\n"
  output+="$(date '+%Y-%m-%d %H:%M:%S')  |  dir: ${PROJECT_ROOT}\n"
  output+="───────────────────────────────────────\n"

  # progress.json
  if [[ ! -f "$PROGRESS_FILE" ]]; then
    output+="等待引擎启动...\n"
    echo -e "$output"
    return
  fi

  # 阶段进度
  local current_phase
  current_phase=$(python3 -c "
import json, sys
with open('${PROGRESS_FILE}') as f: d = json.load(f)
print(d.get('current_phase', '?'))
" 2>/dev/null || echo "?")

  output+="$(printf '%b' "${BOLD}阶段进度:${RESET}")\n"
  for phase in P0 P1 P2 P3 P4 P5 P6 P7; do
    local status
    status=$(python3 -c "
import json
with open('${PROGRESS_FILE}') as f: d = json.load(f)
print(d.get('phases',{}).get('${phase}',{}).get('status','pending'))
" 2>/dev/null || echo "pending")

    local icon name
    case $phase in
      P0) name="记忆查询";;  P1) name="需求分析";;
      P2) name="技术设计";;  P3) name="任务拆分";;
      P4) name="编码实现";;  P5) name="编译测试";;
      P6) name="代码审查";;  P7) name="经验沉淀";;
    esac
    case $status in
      completed)   icon="$(printf '%b' "${GREEN}✅${RESET}")";;
      in_progress) icon="$(printf '%b' "${YELLOW}🔄${RESET}")";;
      failed)      icon="$(printf '%b' "${RED}❌${RESET}")";;
      *)           icon="  ";;
    esac
    output+="  ${icon} ${phase} ${name}\n"
  done

  # 任务统计
  local task_summary
  task_summary=$(python3 -c "
import json
with open('${PROGRESS_FILE}') as f: d = json.load(f)
tasks = d.get('tasks', {})
total = len(tasks)
kept = sum(1 for t in tasks.values() if t.get('decision') == 'keep')
disc = sum(1 for t in tasks.values() if t.get('decision') == 'discard')
prog = sum(1 for t in tasks.values() if t.get('status') in ('in_progress','coding'))
fixes = sum(t.get('fix_rounds',0) for t in tasks.values())
print(f'{kept}/{total} keep | {disc} discard | {prog} coding | {fixes} fix rounds')
" 2>/dev/null || echo "解析中...")

  output+="\n$(printf '%b' "${BOLD}任务: ${RESET}")${task_summary}\n"

  # 任务详情
  local task_details
  task_details=$(python3 -c "
import json
with open('${PROGRESS_FILE}') as f: d = json.load(f)
tasks = d.get('tasks', {})
for tid in sorted(tasks.keys()):
    t = tasks[tid]
    st = t.get('status','?')
    dec = t.get('decision','')
    w = t.get('wave','?')
    fr = t.get('fix_rounds',0)
    icon = '✅' if dec == 'keep' else '❌' if dec == 'discard' else '🔄' if st in ('in_progress','coding') else '⏳'
    extra = f' ({fr} fix)' if fr > 0 else ''
    print(f'  {icon} {tid}  w{w}  {st}{extra}')
" 2>/dev/null || echo "  解析中...")

  output+="${task_details}\n"

  # 最新 git commits
  output+="\n$(printf '%b' "${BOLD}最新 commits:${RESET}")\n"
  for repo in P1GoServer freelifeclient old_proto; do
    local latest
    latest=$(git -C "${PROJECT_ROOT}/${repo}" log --oneline -1 2>/dev/null || echo "(无变更)")
    output+="  $(printf '%b' "${CYAN}${repo}:${RESET}") ${latest}\n"
  done

  # 文件列表
  output+="\n$(printf '%b' "${BOLD}产出文件:${RESET}")\n"
  output+="$(ls -1 "${FEATURE_DIR}/" 2>/dev/null | sed 's/^/  /')\n"

  output+="───────────────────────────────────────"
  echo -e "$output"
}

# ─── 后台循环 ───
run_loop() {
  trap 'rm -f "$WATCH_PID_FILE"; exit 0' SIGTERM SIGINT
  while true; do
    render_status > "$WATCH_LOG" 2>/dev/null
    sleep 5
  done
}

# 启动后台
run_loop &
BG_PID=$!
echo "$BG_PID" > "$WATCH_PID_FILE"
echo -e "${GREEN}监控已启动${RESET} (PID $BG_PID)"
echo ""
echo "  查看进度:  bash scripts/watch-feature.sh --show"
echo "  一次快照:  bash scripts/watch-feature.sh --status"
echo "  停止监控:  bash scripts/watch-feature.sh --stop"
echo ""

# 首次渲染一次到终端
render_status
