# DDRP: 递归 new-feature 依赖解决协议

> 版本：v5 | 状态：设计完成，待实现

## 问题

new-feature 执行引擎（dev-workflow/auto-work）在 develop 阶段发现缺失依赖系统时，task 编译失败被 discard，无自动解决机制。

## 方案概述

通过**递归 spawn 子 new-feature 进程**实现缺失依赖，每层实例都有完整的 plan → develop → verify → DDRP 能力。进程间纯文件通信，无递归深度限制，上下文完全隔离，引擎零修改。

---

## 核心设计

### 1. idea.md 是唯一的通信载体

父进程为子 feature 预填 idea.md，子进程的 Step 0 断点恢复机制检测到 `## 确认方案` 存在 → 自动跳到 Step 4。所有决策信息编码在 idea.md 中：

| idea.md 字段 | 顶层（用户填） | 子 feature（父进程填） | 效果 |
|-------------|--------------|---------------------|------|
| `## 确认方案` | Step 3 互动后追加 | 预填 | 触发跳转 Step 4 |
| `### 执行引擎` | 无（Step 4 询问用户） | `auto-work` | Step 4 直接使用，不询问 |
| `### 锁定决策` | 用户确认 | 父进程基于调用需求生成 | 下游引擎作为硬约束 |
| `### 验收标准` | 用户定义 | 编译通过 + 核心接口存在 | 轻量验收 |

**子进程不知道自己是子进程**，只是碰巧 idea.md 信息更完整，自然走了更短的路径。

### 2. DDRP 循环在 new-feature Step 4

**每个 new-feature 实例都有 DDRP 循环**（包括子 feature），递归天然成立：

```
Step 4 循环:
  运行引擎（run_in_background）
  等待引擎完成通知
  检查 ddrp-req-*.md 文件（两道防线）
  无 open → break，进入 Step 5
  有 open → 逐个解决:
    查 registry → 已完成/开发中/失败/未注册
    未注册 → 准备子 idea.md → spawn claude -p（run_in_background）
  等待子进程完成通知
  重置被阻塞 task → 重跑引擎
```

### 3. 防碰撞：版本级注册表

`docs/version/{VERSION}/ddrp-registry.json`：

```jsonc
{
  "dependencies": [
    {
      "name": "npc_emotion_system",
      "feature_dir": "docs/version/0.0.3/npc_emotion_system/",
      "requested_by": ["npc_social_behavior"],
      "status": "developing|completed|failed"
    }
  ]
}
```

spawn 前查表：
- `completed` → grep 验证关键符号 → 标记请求 resolved
- `developing` → 等待（`timeout 1800 bash -c 'while [ ! -f acceptance-report.md ]; do sleep 30; done'`，通过 `run_in_background`，仅 2 turns）
- `failed` → 标记请求 failed，当前 feature 继续（降级）
- 不存在 → 注册 + spawn

**循环依赖**：A→B→A 时，B spawn A 发现 A 已 `developing` → 等待 → 但 A 也在等 B → 超时 30min → 双方 failed → 降级继续。

### 4. 非交互 fallback

`claude -p` 中 AskUserQuestion 不可用。所有交互点有 fallback：

| 交互点 | fallback 条件 | fallback 行为 |
|--------|-------------|--------------|
| Step 0 版本/目录确认 | idea.md 已存在 | 从目录路径推导 |
| Step 3 方案互动 | `## 确认方案` 已存在 | 跳过（断点恢复） |
| Step 4 引擎选择 | `### 执行引擎` 字段存在 | 直接使用指定引擎 |
| developing 第二步 范围确认 | `## 确认方案` 存在 | 从 plan file_list 的 side 字段推断 |
| developing 第四步 优化建议 | 同上 | 不提建议，只做 plan 要求的 |

### 5. DDRP 请求的两道防线

**防线一（task 主动上报）**：developing 阶段发现缺失依赖时按 `ddrp-protocol.md` 规则写入 `ddrp-req-{TASK_ID}.md`。

**防线二（编译错误自动推导）**：若防线一无 open 条目，但有 discarded task，DDRP 循环自动分析编译错误：
- 读取 `failure-lessons.md` 和 discarded task 的 develop-log
- 提取未定义类型/接口（`type not found`、`undefined`）
- grep 确认确实不存在（排除拼写错误）
- 符合子系统规模 → **自动生成 ddrp-req 文件**
- 生成的 ddrp-req 从编译错误提取具体类型名和方法签名（比 task 手写更精确）

---

## 文件协议

### ddrp-req 文件

每个 task 写独立文件（避免并发写碰撞）：`{FEATURE_DIR}/ddrp-req-{TASK_ID}.md`

```markdown
# DDRP-REQ: {系统名}
- status: open
- 核心能力：{调用方需要的接口/功能描述}
- 预估规模：{N 文件, ~M 行}
- 阻塞的 task：{task ID 或描述}
- 参考实现：{最相似已有系统路径}
```

**worktree 环境**：ddrp-req 文件必须使用主工作区绝对路径，不写 worktree 副本。PROJECT_ROOT 发现：若 CWD 包含 `.worktrees/`，取其前缀；否则取 CWD。

### 子 feature 的 idea.md 模板

```markdown
# {系统名}

## 核心需求
{从 ddrp-req 文件提取的核心能力描述}

## 调研上下文
- 调用方：{FEATURE_NAME} 需要此系统
- 需要提供的核心接口：{从 req 文件提取}
- 参考实现：{从 req 文件提取的最相似路径}

## 范围边界
- 做：满足调用方需求的最小可用版本
- 不做：完整功能（后续独立迭代补充）

## 初步理解
{基于调用方需求和参考实现推导的系统职责}

## 确认方案

方案摘要：{系统名} — 最小可用版本

核心思路：{一句话描述}

### 锁定决策
{基于项目惯例和调用方需求生成的技术决策}

### 执行引擎
auto-work

### 待细化
无

### 验收标准
- 编译通过（涉及的所有工程）
- 核心接口存在且可被调用方引用
```

---

## DDRP 循环详细流程

### Step 4 DDRP 外循环

```
DDRP_ROUND = 0, MAX_DDRP_ROUNDS = 5

循环:
  1. DDRP_ROUND += 1；> MAX → 警告"未收敛"，进入 Step 5

  2. 运行引擎
     - auto-work: run_in_background 启动，等待完成通知
     - dev-workflow: 当前会话内直接执行

  3. 检查 DDRP 请求（两道防线）
     - 防线一：glob ddrp-req-*.md，收集 status:open
     - 防线二：无 open 但有 discarded task → 分析编译错误自动生成 ddrp-req
     - 均无 open → break

  4. 解决依赖（对每个 open 条目）
     a. 查注册表：completed/developing/failed/未注册
     b. 未注册 → 准备 DEP_FEATURE_DIR + idea.md + 注册
     c. spawn: claude -p "/new-feature {VERSION} {DEP_NAME}" (run_in_background, --max-turns 120)
     多个独立依赖可并行 spawn

  5. 等待完成
     - 本进程 spawn 的：run_in_background 自动通知
     - 外部 developing 的：timeout 1800 bash while loop (run_in_background, 2 turns)
     - 读取 acceptance-report.md 判断结果，更新 registry

  6. 判断重跑
     - 有新 resolved → 重置被阻塞 task (discarded → pending) → 回到步骤 1
       (auto-work 重跑自动跳过 Phase 0-3，只执行 Phase 4 pending task)
     - 无新 resolved → break
```

### Step 3.5 前置检测

可行性快检发现 BLOCK 项时：
1. 简单缺失（单函数/枚举/配置）→ 纳入 plan file_list 标注新建
2. 独立系统 → 使用 Step 4 DDRP 的 spawn 协议（步骤 b-c）解决
3. 仍有 BLOCK → 向用户报告（顶层）或记录后继续（子 feature）

---

## 发现与分级规则（ddrp-protocol.md）

| 规模 | 判断标准 | 处理 |
|------|----------|------|
| 内联 | ≤50 行、单文件、无外部依赖 | 当前 task 直接实现，develop-log 记录 `[DDRP-INLINE]` |
| 子任务 | 50-300 行、1-3 文件、自包含 | 暂停 → 实现 → 编译 → 恢复，记录 `[DDRP-SUBTASK]` |
| 子系统 | >300 行 或 3+ 文件 或 有自身依赖 | 写 ddrp-req 文件后继续尝试（引擎正常 discard） |

规则：
- 子系统必须上报（写 ddrp-req），禁止 developing 内部 spawn 进程
- DDRP 实现只做最小可用版本
- 写入 ddrp-req 后继续尝试当前 task（不要停下来等）
- worktree 环境下用主工作区绝对路径

---

## 修改清单

| 文件 | 操作 | 改动点 |
|------|------|--------|
| `.claude/rules/ddrp-protocol.md` | **新建** | 发现分级 + ddrp-req 格式 + worktree 路径规则 |
| `.claude/skills/new-feature/SKILL.md` | **修改** | Step 3.5 BLOCK 处理 + Step 4 引擎选择优先级 + Step 4 DDRP 外循环 |
| `.claude/commands/feature/developing.md` | **修改** | Step 2 断点恢复自动推断 + Step 4 DDRP 发现与上报 |

**不修改的文件**：`auto-work-loop.sh`、`p4-implementation.md`、`plan-creator.md`、`develop.md`、`develop-review.md`（引擎内部逻辑不变）。

---

## 已知局限

### L1. Registry 并发写竞态

两个进程同时发现同一缺失依赖 → 同时写入 → 可能重复 spawn。**不影响正确性**（registry 最终 completed）。可选用 `flock` 优化。

### L2. 接口不匹配风险

子 feature 实现的接口与父 task 预期不同 → 父 task 重跑仍失败 → 无新 ddrp-req → task 永久 discard。
**缓解**：ddrp-req 写明具体接口签名。防线二从编译错误提取签名更精确。

### L3. dev-workflow 重跑 task 重置（待验证）

auto-work 已确认支持（Phase 跳过 + wave builder）。dev-workflow 的等价 resume 机制需实现时验证。

---

## 验证清单

1. idea.md 驱动：含 `### 执行引擎: auto-work` 的 idea.md → spawn → 跳过交互 → 引擎执行
2. DDRP 发现：developing 模拟缺失依赖 → ddrp-req 正确生成（含 worktree 绝对路径）
3. DDRP 循环：discard → 检测 req → spawn 子 feature → 完成 → 重置 → 重跑成功
4. 递归：子 feature 发现缺失 → spawn 孙 feature → 链路收敛
5. 防重复：同一依赖两次请求 → registry 只 spawn 一次
6. 循环依赖：A→B→A → 等待超时 → failed → 降级
7. 防线二兜底：task 未写 ddrp-req → 编译错误自动推导 → 生成 req
8. 重跑效率：auto-work 跳过 Phase 0-3，只执行 Phase 4
9. 收敛：MAX_DDRP_ROUNDS=5 强制退出
