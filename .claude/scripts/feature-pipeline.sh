#!/bin/bash
# feature-pipeline.sh — Step 4 + Step 5 + merge 不可打断机械管道
# 用法: bash .claude/scripts/feature-pipeline.sh <engine> <version> <feature>
# engine: "auto-work" | "dev-workflow"
#
# 保证：bash 顺序执行，LLM 无法在中间停下来询问用户。
# Step 4 (引擎) → Step 5 (验收) → 条件 merge → cleanup
set -euo pipefail

ENGINE="${1:?用法: $0 <engine> <version> <feature>}"
VERSION="${2:?缺少 version}"
FEATURE="${3:?缺少 feature}"

# ── 路径 ──
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FEATURE_DIR="${PROJECT_ROOT}/docs/version/${VERSION}/${FEATURE}"
# 主工作区路径：从 worktree 路径去掉 --feature 后缀
if [[ "$PROJECT_ROOT" == *"--${FEATURE}" ]]; then
  MAIN_ROOT="${PROJECT_ROOT%%--${FEATURE}}"
  # 去掉尾部斜杠
  MAIN_ROOT="${MAIN_ROOT%/}"
else
  MAIN_ROOT="$PROJECT_ROOT"
fi
MAIN_FEATURE_DIR="${MAIN_ROOT}/docs/version/${VERSION}/${FEATURE}"
LOG_FILE="${FEATURE_DIR}/pipeline.log"

# ── Phase marker（per-feature + 全局兼容） ──
export PHASE_MARKER_PATH="/tmp/.claude_phase_${FEATURE}"

# ── 日志 ──
log() {
  local msg="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [PIPELINE] $*"
  echo "$msg" >> "$LOG_FILE"
  echo "$msg" >&2
}

mkdir -p "$FEATURE_DIR"

# ── 清理 trap ──
CHILD_PID=""
cleanup() {
  rm -f "$PHASE_MARKER_PATH" 2>/dev/null
  rm -f /tmp/.claude_phase 2>/dev/null
  if [[ -n "$CHILD_PID" ]]; then
    kill "$CHILD_PID" 2>/dev/null || true
  fi
}
trap 'cleanup' EXIT INT TERM

log "Pipeline started: engine=$ENGINE version=$VERSION feature=$FEATURE"
log "PROJECT_ROOT=$PROJECT_ROOT MAIN_ROOT=$MAIN_ROOT"

# ═══════════════════════════════════════════════
# Step 4: 引擎执行
# ═══════════════════════════════════════════════
log "Step 4: Starting engine ($ENGINE) via ddrp-outer-loop"
echo "autonomous" > "$PHASE_MARKER_PATH"
echo "autonomous" > /tmp/.claude_phase

bash "${SCRIPT_DIR}/ddrp-outer-loop.sh" "$ENGINE" "$VERSION" "$FEATURE"
ENGINE_EXIT=$?

if [ "$ENGINE_EXIT" -ne 0 ]; then
  log "Step 4: Engine exited with code $ENGINE_EXIT"
  # 仍然继续到 Step 5 尝试验收已完成的部分
fi

log "Step 4: Engine completed"

# ═══════════════════════════════════════════════
# Step 5: 验收（独立 claude -p）
# ═══════════════════════════════════════════════
log "Step 5: Starting acceptance verification"

# ddrp-outer-loop 清除了 marker，重写
echo "autonomous" > "$PHASE_MARKER_PATH"
echo "autonomous" > /tmp/.claude_phase

# 动态参数注入到 prompt 模板
STEP5_PROMPT=$(sed \
  -e "s|{VERSION}|${VERSION}|g" \
  -e "s|{FEATURE}|${FEATURE}|g" \
  -e "s|{FEATURE_DIR}|${FEATURE_DIR}|g" \
  -e "s|{PROJECT_ROOT}|${PROJECT_ROOT}|g" \
  "${SCRIPT_DIR}/step5-acceptance-prompt.md")

claude -p "$STEP5_PROMPT" \
  --allowedTools "Skill,Edit,Read,Bash,Grep,Write,Glob,Agent,ToolSearch" \
  --max-turns 200 &
CHILD_PID=$!
wait "$CHILD_PID" || true
CHILD_PID=""

log "Step 5: Acceptance process completed"

# ═══════════════════════════════════════════════
# 条件 merge（三重守卫）
# ═══════════════════════════════════════════════
REPORT="${FEATURE_DIR}/acceptance-report.md"

# 守卫 1: 报告必须存在
if [[ ! -f "$REPORT" ]]; then
  log "ERROR: acceptance-report.md not generated (Step 5 may have timed out or crashed)"
  # 保存文档到主工作区
  mkdir -p "$MAIN_FEATURE_DIR"
  cp -r "${FEATURE_DIR}/"* "$MAIN_FEATURE_DIR/" 2>/dev/null || true
  log "Feature docs saved to $MAIN_FEATURE_DIR"
  exit 1
fi

# 守卫 2: 不能有 FAIL / UNRESOLVED / BLOCKED
if grep -qE '^\[(FAIL|UNRESOLVED|BLOCKED)' "$REPORT"; then
  FAIL_COUNT=$(grep -cE '^\[(FAIL|UNRESOLVED|BLOCKED)' "$REPORT" || echo "0")
  PASS_COUNT=$(grep -cE '^\[PASS\]' "$REPORT" || echo "0")
  log "Acceptance not fully passed: ${PASS_COUNT} PASS, ${FAIL_COUNT} FAIL/UNRESOLVED/BLOCKED"
  log "Blocking merge. See $REPORT"
  # 保存文档到主工作区
  mkdir -p "$MAIN_FEATURE_DIR"
  cp -r "${FEATURE_DIR}/"* "$MAIN_FEATURE_DIR/" 2>/dev/null || true
  exit 1
fi

PASS_COUNT=$(grep -cE '^\[PASS\]' "$REPORT" || echo "0")
log "Acceptance passed: ${PASS_COUNT}/${PASS_COUNT} PASS"

# ═══════════════════════════════════════════════
# Step 5.7: 文档保存 + 合并
# ═══════════════════════════════════════════════
log "Step 5.7: Saving docs and merging"

# 保存 feature 文档到主工作区
mkdir -p "$MAIN_FEATURE_DIR"
cp -r "${FEATURE_DIR}/"* "$MAIN_FEATURE_DIR/" 2>/dev/null || true

# 仅在 worktree 模式下合并
if [[ "$PROJECT_ROOT" != "$MAIN_ROOT" ]]; then
  MERGE_FAILED=""
  for repo in P1GoServer freelifeclient old_proto; do
    REPO_PATH="${PROJECT_ROOT}/${repo}"
    MAIN_REPO="${MAIN_ROOT}/${repo}"
    BRANCH="feature/${FEATURE}"

    # 检查 feature 分支是否存在且有新 commit
    if ! git -C "$REPO_PATH" rev-parse --verify "$BRANCH" &>/dev/null; then
      log "  ${repo}: no feature branch, skip"
      continue
    fi

    # 获取当前 HEAD 和 feature 分支 HEAD
    MAIN_HEAD=$(git -C "$MAIN_REPO" rev-parse HEAD 2>/dev/null || echo "")
    FEAT_HEAD=$(git -C "$REPO_PATH" rev-parse "$BRANCH" 2>/dev/null || echo "")
    BASE=$(git -C "$MAIN_REPO" merge-base "$MAIN_HEAD" "$FEAT_HEAD" 2>/dev/null || echo "")

    if [[ -z "$BASE" ]] || [[ "$FEAT_HEAD" == "$BASE" ]]; then
      log "  ${repo}: no new commits on feature branch, skip"
      continue
    fi

    log "  ${repo}: merging ${BRANCH}"
    if git -C "$MAIN_REPO" merge --no-ff "$BRANCH" -m "merge(${FEATURE}): ${FEATURE} into main" 2>>"$LOG_FILE"; then
      log "  ${repo}: merge OK"
    else
      log "  ${repo}: MERGE CONFLICT — needs manual resolution"
      git -C "$MAIN_REPO" merge --abort 2>/dev/null || true
      MERGE_FAILED="1"
    fi
  done

  if [[ -n "$MERGE_FAILED" ]]; then
    log "WARNING: Some repos had merge conflicts. Feature docs saved to $MAIN_FEATURE_DIR"
    exit 1
  fi
fi

# ═══════════════════════════════════════════════
# Step 5.8: 清理 worktree
# ═══════════════════════════════════════════════
if [[ "$PROJECT_ROOT" != "$MAIN_ROOT" ]]; then
  log "Step 5.8: Cleaning up worktree"
  for repo in P1GoServer freelifeclient old_proto; do
    BRANCH="feature/${FEATURE}"
    git -C "${MAIN_ROOT}/${repo}" worktree remove "${PROJECT_ROOT}/${repo}" --force 2>/dev/null || true
    git -C "${MAIN_ROOT}/${repo}" branch -d "$BRANCH" 2>/dev/null || true
  done
  # 删除 worktree 顶层目录
  rm -rf "$PROJECT_ROOT" 2>/dev/null || true
  log "  Worktree cleaned"
fi

log "Pipeline completed successfully: ${FEATURE}"
echo ""
echo "═══════════════════════════════════════════════"
echo "  feature-pipeline completed: ${FEATURE}"
echo "  Report: ${MAIN_FEATURE_DIR}/acceptance-report.md"
echo "═══════════════════════════════════════════════"
