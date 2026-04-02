#!/usr/bin/env bash
# ddrp-outer-loop.sh — DDRP 递归依赖解决编排脚本
# 用法: bash .claude/scripts/ddrp-outer-loop.sh <engine> <version_id> <feature_name>
# engine: "auto-work" | "dev-workflow"
#
# 核心流程（5 轮上限）：
#   1. 启动引擎（auto-work-loop.sh 或 claude -p dev-workflow）
#   2. 收集 ddrp-req-*.md（status:open）
#   3. 防线二：从编译错误自动生成 ddrp-req
#   4. 无 open → break
#   5. 对每个 open：查 registry → spawn 子 feature / 等待 / 标记 failed
#   6. wait 所有 spawn PID
#   7. 有新 resolved → reset blocked tasks → continue
#   8. 无新 resolved → break
set -euo pipefail

# ── 参数解析 ──
ENGINE="${1:?用法: $0 <engine> <version_id> <feature_name>}"
VERSION_ID="${2:?缺少 version_id}"
FEATURE_NAME="${3:?缺少 feature_name}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FEATURE_DIR="${PROJECT_ROOT}/docs/version/${VERSION_ID}/${FEATURE_NAME}"
REGISTRY="${PROJECT_ROOT}/docs/version/${VERSION_ID}/ddrp-registry.json"
LOCKDIR="${REGISTRY}.lock"
LOG_FILE="${FEATURE_DIR}/ddrp-loop.log"

MAX_ROUNDS="${DDRP_MAX_ROUNDS:-5}"
ENGINE_TIMEOUT="${DDRP_ENGINE_TIMEOUT:-7200}"
SPAWN_TIMEOUT="${DDRP_SPAWN_TIMEOUT:-3600}"
MAX_DDRP_CONCURRENT="${DDRP_MAX_CONCURRENT:-3}"
DDRP_ROUND=0

# ── 阶段信号（支持 pipeline 传入 per-feature marker 路径） ──
PHASE_MARKER="${PHASE_MARKER_PATH:-/tmp/.claude_phase}"
echo "autonomous" > "$PHASE_MARKER"

# ── 日志 ──
log() {
    local msg="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [DDRP-R${DDRP_ROUND}] $*"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg" >&2
}

mkdir -p "$FEATURE_DIR"
echo "# DDRP Outer Loop Log — $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$LOG_FILE"

# ── 锁函数（mkdir 原子锁，跨平台） ──
acquire_lock() {
    local attempts=0
    while ! mkdir "$LOCKDIR" 2>/dev/null; do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 60 ]; then
            # 检查陈旧锁（>30s）
            if python3 -c "
import os, time
lock='$LOCKDIR'
if os.path.isdir(lock) and time.time() - os.path.getmtime(lock) > 30:
    os.rmdir(lock)
    exit(0)
exit(1)
" 2>/dev/null; then
                continue
            fi
            log "WARN: 获取 registry 锁超时"
            return 1
        fi
        sleep 0.5
    done
    return 0
}

release_lock() {
    rmdir "$LOCKDIR" 2>/dev/null || true
}

# ── Registry 读写（python3 原子操作） ──
registry_upsert() {
    local dep_name="$1" status="$2" requested_by="$3"
    acquire_lock || return 1
    python3 -X utf8 -c "
import json, os, sys
reg_path = '$REGISTRY'
dep_name = '$dep_name'
status = '$status'
requested_by = '$requested_by'

if os.path.exists(reg_path):
    with open(reg_path, 'r') as f:
        reg = json.load(f)
else:
    reg = {'dependencies': []}

found = False
for dep in reg['dependencies']:
    if dep['name'] == dep_name:
        dep['status'] = status
        if requested_by and requested_by not in dep.get('requested_by', []):
            dep.setdefault('requested_by', []).append(requested_by)
        found = True
        break

if not found:
    reg['dependencies'].append({
        'name': dep_name,
        'feature_dir': 'docs/version/$VERSION_ID/' + dep_name + '/',
        'requested_by': [requested_by] if requested_by else [],
        'status': status
    })

tmp_path = reg_path + '.tmp'
with open(tmp_path, 'w') as f:
    json.dump(reg, f, indent=2, ensure_ascii=False)
os.replace(tmp_path, reg_path)
" 2>/dev/null
    local rc=$?
    release_lock
    return $rc
}

registry_get_status() {
    local dep_name="$1"
    if [ ! -f "$REGISTRY" ]; then
        echo "unregistered"
        return
    fi
    python3 -X utf8 -c "
import json
with open('$REGISTRY') as f:
    reg = json.load(f)
for dep in reg.get('dependencies', []):
    if dep['name'] == '$dep_name':
        print(dep.get('status', 'unknown'))
        exit(0)
print('unregistered')
" 2>/dev/null || echo "unregistered"
}

# ── 环路检测 ──
has_cycle() {
    local target="$1" current="$2"
    if [ ! -f "$REGISTRY" ]; then
        return 1  # no cycle
    fi
    python3 -X utf8 -c "
import json
with open('$REGISTRY') as f:
    reg = json.load(f)
deps = {d['name']: d.get('requested_by', []) for d in reg.get('dependencies', [])}

def check(name, visited):
    if name in visited:
        return True
    visited.add(name)
    for upstream in deps.get(name, []):
        if upstream == '$current':
            return True
        if check(upstream, visited):
            return True
    return False

exit(0 if check('$target', set()) else 1)
" 2>/dev/null
}

# ── 收集 open ddrp-req ──
collect_open_reqs() {
    local reqs=()
    for f in "$FEATURE_DIR"/ddrp-req-*.md; do
        [ -f "$f" ] || continue
        if grep -q 'status: open' "$f" 2>/dev/null; then
            local name
            name=$(grep '^# DDRP-REQ:' "$f" 2>/dev/null | head -1 | sed 's/^# DDRP-REQ: *//')
            reqs+=("$name|$f")
        fi
    done
    printf '%s\n' "${reqs[@]}" 2>/dev/null || true
}

# ── 防线二：从编译错误自动生成 ddrp-req ──
analyze_discards_for_ddrp() {
    local results_file="${FEATURE_DIR}/results.tsv"
    [ -f "$results_file" ] || return

    # 提取 discarded 任务的错误摘要
    local errors=""
    while IFS=$'\t' read -r task_id status wave reason error_summary rest; do
        if [ "$status" = "discarded" ] && [ -n "$error_summary" ]; then
            errors="${errors}${error_summary}\n"
        fi
    done < "$results_file"

    [ -z "$errors" ] && return

    # 从编译错误中提取未定义类型/包
    python3 -X utf8 -c "
import re, os
errors = '''$(echo -e "$errors")'''

# Go: undefined: TypeName
go_undef = set(re.findall(r'undefined:\s+(\w+)', errors))
# C#: CS0246/CS0103 type or namespace 'X' could not be found
cs_undef = set(re.findall(r\"CS0[12][04][36].*?'(\w+)'\", errors))

all_missing = go_undef | cs_undef
if not all_missing:
    exit(0)

for name in sorted(all_missing):
    req_file = os.path.join('$FEATURE_DIR', f'ddrp-req-auto-{name.lower()}.md')
    if os.path.exists(req_file):
        continue
    with open(req_file, 'w') as f:
        f.write(f'# DDRP-REQ: {name}\n')
        f.write('- status: open\n')
        f.write(f'- 核心能力：缺失类型/包 {name}（从编译错误自动检测）\n')
        f.write('- 预估规模：待评估\n')
        f.write('- 阻塞的 task：多个 discarded tasks\n')
        f.write('- 参考实现：待查找\n')
    print(f'auto-generated: {req_file}')
" 2>/dev/null
}

# ── Spawn 子 feature ──
spawn_sub_feature() {
    local dep_name="$1" req_file="$2"
    local dep_dir="${PROJECT_ROOT}/docs/version/${VERSION_ID}/${dep_name}"

    # 从 ddrp-req 提取核心能力
    local capability
    capability=$(grep '核心能力' "$req_file" 2>/dev/null | sed 's/.*核心能力[：:]//' | head -1)

    mkdir -p "$dep_dir"

    # 创建子 feature 的 idea.md（含 ## 确认方案 → 跳过交互阶段）
    cat > "$dep_dir/idea.md" << IDEA_EOF
# ${dep_name}

## 核心需求
${capability:-缺失依赖（详见 ddrp-req）}

## 调研上下文
- 调用方：${FEATURE_NAME} 需要此系统
- 参考实现：待查找

## 范围边界
- 做：满足调用方需求的最小可用版本
- 不做：完整功能

## 确认方案

方案摘要：${dep_name} — 最小可用版本

核心思路：实现调用方所需的最小接口集

### 锁定决策
按项目约定实现

### 执行引擎
auto-work

### 待细化
无

### 验收标准
- 编译通过（涉及的所有工程）
- 核心接口存在且可被调用方引用
IDEA_EOF

    # 注册到 registry
    registry_upsert "$dep_name" "developing" "$FEATURE_NAME"

    # Spawn（后台 + 超时）
    log "Spawning sub-feature: $dep_name (timeout ${SPAWN_TIMEOUT}s)"
    timeout "$SPAWN_TIMEOUT" claude -p "/new-feature ${VERSION_ID} ${dep_name}" \
        --max-turns 120 --output-format json > "${dep_dir}/spawn.log" 2>&1 &
    local pid=$!
    echo "$pid" >> "${FEATURE_DIR}/.ddrp-spawn-pids"
    log "Spawned PID=$pid for $dep_name"
}

# ── 计数活跃 spawn PID ──
count_active_spawns() {
    local pid_file="${FEATURE_DIR}/.ddrp-spawn-pids"
    [ -f "$pid_file" ] || { echo 0; return; }
    local count=0
    while IFS= read -r pid; do
        [ -z "$pid" ] && continue
        kill -0 "$pid" 2>/dev/null && count=$((count + 1))
    done < "$pid_file"
    echo "$count"
}

# ── 等待 spawn 并发低于上限 ──
throttle_spawns() {
    while [ "$(count_active_spawns)" -ge "$MAX_DDRP_CONCURRENT" ]; do
        log "Spawn throttle: ${MAX_DDRP_CONCURRENT} active, waiting..."
        sleep 5
    done
}

# ── 等待所有 spawn 完成（增量 poll） ──
wait_for_deps() {
    local pid_file="${FEATURE_DIR}/.ddrp-spawn-pids"
    [ -f "$pid_file" ] || return 0

    local new_resolved=0
    local max_wait="${SPAWN_TIMEOUT:-3600}"
    local waited=0

    # poll 循环：每 10s 检查 PID + registry 状态
    while [ "$waited" -lt "$max_wait" ]; do
        # 清理已退出的 PID
        local still_running=""
        while IFS= read -r pid; do
            [ -z "$pid" ] && continue
            if kill -0 "$pid" 2>/dev/null; then
                still_running="${still_running}${pid}"$'\n'
            else
                log "PID=$pid finished"
            fi
        done < "$pid_file"
        printf '%s' "$still_running" > "$pid_file"

        # 增量检查 dep 状态
        for f in "$FEATURE_DIR"/ddrp-req-*.md; do
            [ -f "$f" ] || continue
            if grep -q 'status: open' "$f" 2>/dev/null; then
                local dep_name
                dep_name=$(grep '^# DDRP-REQ:' "$f" 2>/dev/null | head -1 | sed 's/^# DDRP-REQ: *//')
                local dep_status
                dep_status=$(registry_get_status "$dep_name")
                if [ "$dep_status" = "completed" ]; then
                    sed -i 's/status: open/status: resolved/' "$f"
                    new_resolved=$((new_resolved + 1))
                    log "Dependency resolved (incremental): $dep_name"
                elif [ "$dep_status" = "failed" ]; then
                    sed -i 's/status: open/status: failed/' "$f"
                    log "Dependency failed (incremental): $dep_name"
                fi
            fi
        done

        # 所有 PID 已退出则结束
        [ -z "$(tr -d '[:space:]' < "$pid_file" 2>/dev/null)" ] && break

        sleep 10
        waited=$((waited + 10))
    done

    if [ "$waited" -ge "$max_wait" ]; then
        log "WARN: wait_for_deps timed out after ${max_wait}s"
    fi

    rm -f "$pid_file"
    return $((new_resolved > 0 ? 0 : 1))
}

# ── 重置被阻塞的任务 ──
reset_blocked_tasks() {
    local results_file="${FEATURE_DIR}/results.tsv"
    [ -f "$results_file" ] || return
    sed -i 's/\tdiscarded\t/\tpending\t/g' "$results_file"
    log "Reset discarded tasks to pending"
}

# ══════════════════════════════════════════
# 主循环
# ══════════════════════════════════════════
log "Starting DDRP outer loop: engine=$ENGINE version=$VERSION_ID feature=$FEATURE_NAME"

while [ "$DDRP_ROUND" -lt "$MAX_ROUNDS" ]; do
    DDRP_ROUND=$((DDRP_ROUND + 1))
    log "=== Round $DDRP_ROUND / $MAX_ROUNDS ==="

    # Step 1: 运行引擎
    log "Running engine: $ENGINE (timeout ${ENGINE_TIMEOUT}s)"
    local_exit=0
    if [ "$ENGINE" = "auto-work" ]; then
        timeout "$ENGINE_TIMEOUT" bash "$SCRIPT_DIR/auto-work-loop.sh" \
            "$VERSION_ID" "$FEATURE_NAME" 2>&1 | tee -a "$LOG_FILE" || local_exit=$?
    elif [ "$ENGINE" = "dev-workflow" ]; then
        timeout "$ENGINE_TIMEOUT" claude -p "/dev-workflow ${FEATURE_DIR}/idea.md" \
            --max-turns 200 --output-format json 2>&1 | tee -a "$LOG_FILE" || local_exit=$?
    else
        log "ERROR: unknown engine '$ENGINE'"
        break
    fi

    if [ "$local_exit" -eq 124 ]; then
        log "WARN: Engine timed out after ${ENGINE_TIMEOUT}s"
    fi

    # Step 2: 收集 open ddrp-req（防线一）
    OPEN_REQS=$(collect_open_reqs)

    # Step 3: 防线二（无 open 但有 discarded → 从编译错误自动生成）
    if [ -z "$OPEN_REQS" ]; then
        analyze_discards_for_ddrp
        OPEN_REQS=$(collect_open_reqs)
    fi

    # Step 4: 无 open → 完成
    if [ -z "$OPEN_REQS" ]; then
        log "No open DDRP requests — breaking"
        break
    fi

    log "Found open DDRP requests:"
    echo "$OPEN_REQS" | while IFS='|' read -r name file; do
        log "  - $name ($file)"
    done

    # Step 5: 解决每个 open 依赖
    echo "$OPEN_REQS" | while IFS='|' read -r dep_name req_file; do
        [ -z "$dep_name" ] && continue

        # 检查环路
        if has_cycle "$dep_name" "$FEATURE_NAME"; then
            log "WARN: Circular dependency detected for $dep_name — marking failed"
            sed -i 's/status: open/status: failed/' "$req_file"
            registry_upsert "$dep_name" "failed" "$FEATURE_NAME"
            continue
        fi

        # 检查 feature registry（跨 feature 依赖）
        local feat_status=""
        if [ -f "${PROJECT_ROOT}/.feature-registry.json" ]; then
            feat_status=$(bash "$SCRIPT_DIR/feature-workspace.sh" status "$dep_name" 2>/dev/null | grep -o 'active\|completed\|failed' | head -1)
        fi

        if [ "$feat_status" = "completed" ]; then
            sed -i 's/status: open/status: resolved/' "$req_file"
            log "Dependency $dep_name already completed in feature registry"
            continue
        elif [ "$feat_status" = "active" ]; then
            log "Dependency $dep_name is active in another feature — waiting"
            sed -i "s/status: open/status: waiting:${dep_name}/" "$req_file"
            continue
        fi

        # 检查 ddrp registry
        local reg_status
        reg_status=$(registry_get_status "$dep_name")
        case "$reg_status" in
            completed)
                sed -i 's/status: open/status: resolved/' "$req_file"
                log "Dependency $dep_name already completed in ddrp registry"
                ;;
            developing)
                log "Dependency $dep_name is being developed — will wait"
                ;;
            failed)
                sed -i 's/status: open/status: failed/' "$req_file"
                log "Dependency $dep_name previously failed"
                ;;
            *)
                # unregistered or pending → spawn（节流）
                throttle_spawns
                spawn_sub_feature "$dep_name" "$req_file"
                ;;
        esac
    done

    # Step 6: 等待所有 spawn 完成
    if wait_for_deps; then
        # 有新 resolved → 重置 blocked tasks，继续循环
        reset_blocked_tasks
        log "Dependencies resolved — resetting blocked tasks and re-running"
    else
        log "No new dependencies resolved — breaking"
        break
    fi
done

if [ "$DDRP_ROUND" -ge "$MAX_ROUNDS" ]; then
    log "WARN: DDRP outer loop reached max rounds ($MAX_ROUNDS) without convergence"
fi

# ── 清理 ──
rm -f "$PHASE_MARKER" 2>/dev/null
rm -f "${FEATURE_DIR}/.ddrp-spawn-pids" 2>/dev/null
log "DDRP outer loop completed (${DDRP_ROUND} rounds)"
