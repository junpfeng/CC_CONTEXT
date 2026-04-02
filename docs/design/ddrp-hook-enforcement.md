# DDRP 递归依赖自动闭环（Hook 强制版）

> 设计文档 — 2026-04-01

## Context

实现需求时发现依赖/扩展需求，AI 应该**直接完成**——不能询问用户是否需要做、怎么做。当前 DDRP 协议设计完整（`new-feature/SKILL.md` 371-478 行）但全靠 AI 自觉执行，没有任何硬约束。需要从 hook 层面强制保证。

**核心原则**：发现依赖 → 直接做完 → 不能停下来问 → 不能跳过交付。

**问题现状**：
- `auto-work-loop.sh`（2054 行）中 0 处 DDRP 引用
- AI 在引擎执行期间上下文膨胀后遗忘外循环，子特性从未被 spawn
- 没有 hook 或脚本强制保证 DDRP 执行

## 方案：三层 Hook 硬约束 + 编排脚本

### 层级架构

```
Layer 1: PreToolUse (AskUserQuestion) — 阶段感知全量拦截（自动阶段 block 所有提问）
Layer 2: Stop hook — 拦截"有未解决 ddrp-req 就交付"
Layer 3: PreToolUse (Bash git push) — 拦截"有未解决 ddrp-req 就推送"
Layer 4: ddrp-outer-loop.sh — 编排引擎重跑 + 子特性 spawn（保底机制）
```

Hook 是安全网（硬约束），脚本是执行引擎（软编排）。自动阶段 AI 试图提问→L1 全量拦截；试图跳过交付→L2 拦截；试图直接推→L3 拦截。

### 改动清单

| 文件 | 动作 | 说明 |
|------|------|------|
| `.claude/hooks/block-obvious-asks.sh` | **修改** | 阶段感知拦截（读 `/tmp/.claude_phase` 信号文件） |
| `.claude/hooks/cs-baseline-snapshot.sh` | **修改** | SessionStart 清理残留信号文件 |
| `.claude/hooks/delivery-quality-check.sh` | **修改** | 新增 ddrp-req 未解决检查（Check 5） |
| `.claude/hooks/acceptance-before-push.sh` | **修改** | 新增 ddrp-req 未解决检查（Check 3） |
| `.claude/scripts/ddrp-outer-loop.sh` | **新建** | DDRP 编排脚本（~280 行） |
| `.claude/skills/new-feature/SKILL.md` | **修改** | 阶段信号写入 + DDRP 伪代码精简为脚本引用 |
| `.claude/skills/bug-explore/SKILL.md` | **修改** | Phase 4 入口写 autonomous 信号 |
| `.claude/skills/dev-workflow/SKILL.md` | **修改** | 启动即写 autonomous 信号 |
| `.claude/skills/dev-debug/SKILL.md` | **修改** | 启动即写 autonomous 信号 |
| `.claude/skills/auto-work/SKILL.md` | **修改** | 启动即写 autonomous 信号 |
| `.claude/commands/feature/develop.md` | **修改** | 启动即写 autonomous 信号 |

### 不改动

- `auto-work-loop.sh` — 已有跳过完成任务的逻辑，重跑幂等
- `ddrp-protocol.md` — 保持为规范文档

---

## Layer 1: 阶段感知全量拦截

**文件**：`.claude/hooks/block-obvious-asks.sh`、`.claude/hooks/cs-baseline-snapshot.sh`

**原设计**：regex 匹配依赖相关提问。**问题**：自动阶段不只是不能问依赖，什么都不该问；交互阶段（new-feature Step 0-3、bug-explore Phase 1-3）的合理提问会被误拦。

**升级方案**：阶段信号文件 `/tmp/.claude_phase`

**信号协议**：
- Skills 在阶段边界写信号：`echo "autonomous" > /tmp/.claude_phase`（进入自动阶段）
- Skills 完成时清理：`rm -f /tmp/.claude_phase`（恢复默认）
- SessionStart hook 清理残留（防崩溃后遗留）

**Hook 逻辑**：
```bash
PHASE_FILE="/tmp/.claude_phase"
if [ -f "$PHASE_FILE" ]; then
    PHASE=$(cat "$PHASE_FILE" 2>/dev/null | tr -d '[:space:]')
    if [ "$PHASE" = "autonomous" ]; then
        # 自动阶段：拦截所有 AskUserQuestion
        exit 2
    elif [ "$PHASE" = "interactive" ]; then
        # 交互阶段：放行所有
        exit 0
    fi
fi
# 无信号文件：fallback 到现有 regex 模式（兼容非 skill 场景）
```

**Skill 阶段边界**：

| Skill | 交互→自动边界 |
|-------|-------------|
| new-feature | Step 3 确认方案后；断点恢复到 Step 4 时 |
| bug-explore | Phase 3 确认后进入 Phase 4 |
| dev-workflow | 启动即 autonomous |
| dev-debug | 启动即 autonomous |
| auto-work | 启动即 autonomous |
| feature:develop | 启动即 autonomous |

## Layer 2: 拦截未解决依赖的交付

**文件**：`.claude/hooks/delivery-quality-check.sh`

在现有检查 4（action log 验证）之后新增检查 5：

```python
# === 检查5: DDRP 依赖未解决 ===
import glob as globmod

# 扫描当前工作目录下所有 ddrp-req 文件
ddrp_files = globmod.glob('docs/version/*/*/ddrp-req-*.md', recursive=False)
open_reqs = []
for f in ddrp_files:
    try:
        with open(f) as fh:
            content = fh.read()
            if 'status: open' in content:
                for line in content.splitlines():
                    if line.startswith('# DDRP-REQ:'):
                        name = line.replace('# DDRP-REQ:', '').strip()
                        open_reqs.append(f'{name} ({f})')
                        break
    except Exception:
        pass

if open_reqs:
    violations.append(f'存在 {len(open_reqs)} 个未解决的 DDRP 依赖：{"; ".join(open_reqs[:3])}。必须实现或标记 failed 后才能交付')
```

## Layer 3: 拦截未解决依赖的推送

**文件**：`.claude/hooks/acceptance-before-push.sh`

在现有 acceptance-report 检查之后，新增 ddrp-req 检查（逻辑与 Layer 2 相同的 python3 glob 扫描）。

## Layer 4: DDRP 编排脚本

**文件**：`.claude/scripts/ddrp-outer-loop.sh`（~250 行）

定位：编排机制（hook 是安全网，脚本是执行引擎）。

**调用方式**：
```bash
bash .claude/scripts/ddrp-outer-loop.sh <engine> <version_id> <feature_name>
# engine: "auto-work" | "dev-workflow"
```

**核心流程**（5 轮上限）：
```
while DDRP_ROUND <= 5:
  1. 启动后台 ddrp-req watcher（每 30s poll，写日志）
  2. 运行引擎（auto-work-loop.sh 或 claude -p dev-workflow）
  3. 停止 watcher
  4. glob ddrp-req-*.md，收集 status:open
  5. 无 open + 有 discarded → 防线二：grep/python3 分析编译错误自动生成 ddrp-req
  6. 仍无 open → break
  7. 对每个 open：查 registry → spawn 子 feature（claude -p &）/ 等待 developing / 标记 failed
  8. wait 所有 spawn PID 完成
  9. 有新 resolved → reset_blocked_tasks(sed discarded→pending) → continue
  10. 无新 resolved → break
```

**关键函数**（9 个）：

| 函数 | 用途 |
|------|------|
| `acquire_lock` / `release_lock` | mkdir 原子锁 + 30s 超时清理 |
| `registry_upsert` | python3 读改写 → `.json.tmp` + `mv` 原子写入 |
| `has_cycle` | python3 遍历 requested_by 链检测环路 |
| `collect_open_reqs` | glob + grep status:open |
| `spawn_sub_feature` | 创建 idea.md + 注册 + `claude -p &` + PID 记录 |
| `wait_for_deps` | `wait $PID` + kill -0 轮询 + registry 状态检查 |
| `analyze_discards_for_ddrp` | grep/python3 提取未定义类型，不用 LLM |
| `reset_blocked_tasks` | sed discarded→pending |
| `watch_ddrp_reqs` | 后台每 30s poll ddrp-req glob，写日志 |

**Windows/MSYS 兼容性**：
- 锁：mkdir 原子（不用 flock）
- JSON：python3 inline + `.tmp` + `mv`
- PID：bash `wait` + `kill -0`（不用 tail --pid）
- timeout：MSYS coreutils 自带

**幂等性**：
- Registry 持久化 → 已 spawn 的不重复 spawn
- 引擎内建跳过 → 重跑只执行 pending 任务
- 陈旧锁 >30s 自动清理

## SKILL.md 修改

**文件**：`.claude/skills/new-feature/SKILL.md` Step 4

路径 A（dev-workflow）和路径 B（auto-work）的启动命令统一改为：
```bash
bash .claude/scripts/ddrp-outer-loop.sh "{ENGINE}" "{VERSION_ID}" "{FEATURE_NAME}"
```

DDRP 伪代码段（371-476 行）精简为脚本引用 + hook 说明。

## 阶段性交付

**Phase 1（本次）**：三层 Hook + auto-work 引擎路径
**Phase 2（后续）**：dev-workflow 断点恢复（需 progress.json 读取 + Phase 4 跳过逻辑）

## 验证方式

1. **Hook L1**：模拟 AskUserQuestion "是否需要先实现这个依赖" → 确认被 block
2. **Hook L2**：手动创建 `ddrp-req-test.md`(status:open) → 尝试 Stop → 确认被 block
3. **Hook L3**：有 open ddrp-req 时 git push → 确认被 block
4. **编排脚本**：无依赖场景 1 轮退出；单依赖场景 spawn+wait+re-run
5. **端到端**：在实际 new-feature 中触发 DDRP → 验证子特性被自动完成
