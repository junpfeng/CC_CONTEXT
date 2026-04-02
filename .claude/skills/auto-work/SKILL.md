---
name: auto-work
description: "全自动需求开发工作流：给一个需求，AI 自动完成分类→调研→方案→开发→文档→推送全流程。基于多 CLI 进程编排，每阶段独立上下文零污染。"
user-invocable: true
argument-hint: <version_id> <feature_name> [需求描述]
---

# Auto-Work：全自动需求开发

启动时立即标记自动阶段：
```bash
echo "autonomous" > /tmp/.claude_phase
```

## 设计原则

### 0. 原子化与可观测性（最高原则）

每个变更控制为最小可独立评估的单位。

| 条件 | 说明 | 实现 |
|------|------|------|
| 固定评估基准 | 评估方法不变，变的只有被测对象 | 编译通过 + Review counts |
| 单一变量 | 每次只改一个东西 | 一个 task = 一个 commit |
| 机械判定标准 | 好坏有明确数值门槛 | 编译=0 errors, Review=Critical=0 && High<=2 |

**Keep/Discard 机制**：
- 每个 task 开始前保存 git 检查点（P1GoServer/freelifeclient/old_proto 各自 HEAD）
- 编译失败 3 次后 → discard（回滚到检查点）
- Review 修复后质量反而恶化 → discard 本轮修复
- 所有 keep/discard 决策记录到 `results.tsv`

### 1. 独立 CLI 进程，独立上下文

每个可独立完成的工作阶段启动独立 `claude -p` CLI 进程，拥有完全独立的上下文窗口，零历史污染。

### 2. 文档是唯一的跨进程通信方式

每个 CLI 进程的输入/输出必须持久化为文档，禁止依赖对话记忆。

### 3. 最小化单个进程职责

一个 CLI 进程只做一件事（调研/写 plan/review/编码）。

### 4. 编排层只做调度不做业务

`auto-work-loop.sh` 只负责阶段判断、启动进程、检查产出、决定下一步。

### 5. 质量优先的上下文管理

多启动一个 CLI 进程的 token 开销远小于上下文污染导致的返工成本。

### 6. 容错与原子性

每阶段写入完成标记，断点续跑时检查标记跳过已完成阶段。

---

## 参数解析

参数格式：`<version_id> <feature_name> [需求描述]`

- **version_id**：版本号（如 `v0.0.3`）
- **feature_name**：功能名称（如 `cooking-system`）
- **需求描述**（可选）：补充需求

**需求来源**（按优先级合并）：
1. `docs/Version/{version_id}/{feature_name}/idea.md`
2. 用户传入的需求描述
3. 两者都不存在时，使用 AskUserQuestion

---

## 执行

参数解析完成后，启动全自动流程：

```bash
bash .claude/scripts/auto-work-loop.sh "{VERSION_ID}" "{FEATURE_NAME}" "{补充需求}"
```

### 阶段零：需求分类
- 判断 research（需调研）还是 direct（直接开发）

### 阶段零-B：技术调研（仅 research）
- 复用 `research-loop.sh` 自动调研+Review 迭代

### 阶段一：生成 feature.json
- 结构化需求文档（JSON Schema）

### 阶段二：Plan 迭代循环
- 复用 `feature-plan-loop.sh`，收敛条件：Critical=0 && Important≤2

### 阶段三：任务拆分
- 将 plan 拆分为 `tasks/task-NN.md`，按依赖拓扑排序

### 阶段四：波次并行开发
- 拓扑排序为波次（wave），同波次内任务串行执行
- 每个 task 走原子化循环：检查点→编码→编译→Review→Keep/Discard
- 波次间 Meta-Review：分析反复错误，自动生成改进规则

### 阶段五：生成模块文档
- 归档到 `docs/Engine/Business/`

### 阶段六：推送远程仓库
- P1GoServer/freelifeclient/old_proto 三仓库推送

---

## 监控

- 总日志：`docs/Version/{VERSION_ID}/{FEATURE_NAME}/auto-work-log.md`
- 仪表盘：`tail -f docs/Version/{VERSION_ID}/{FEATURE_NAME}/dashboard.txt`
- 结果追踪：`docs/Version/{VERSION_ID}/{FEATURE_NAME}/results.tsv`

完成后清理阶段信号：
```bash
rm -f /tmp/.claude_phase 2>/dev/null
```
