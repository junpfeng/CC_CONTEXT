---
description: 修复Bug并固化经验为skill/rule
argument-hint: [version] [feature_name] [bug编号或描述] — 无参数则自动修复所有未修复bug
---

## 参数解析

用户传入的原始参数：`$ARGUMENTS`

**参数格式：** `<version> <feature_name> [bug编号或描述]`

- `version`：版本号（如 `0.0.1`）
- `feature_name`：功能名称（如 `match`、`login`）
- `bug编号或描述`（可选）：指定要修复的具体 Bug 编号

**Bug 文档路径自动解析：** `docs/bugs/$version/$feature_name/$feature_name.md`

**参数缺失处理：**

1. **两个参数都有** → 拼接路径 `docs/bugs/$version/$feature_name/$feature_name.md`，读取文件
2. **只有 version** → 列出 `docs/bugs/$version/` 下的子目录，用 AskUserQuestion 让用户选择功能模块
3. **参数为空** → 进入**批量修复模式**（见下方独立章节）
4. **文件不存在** → 报错并用 AskUserQuestion 请用户确认路径

---

## 单模块/单 Bug 执行

参数解析完成后，使用 Bash 工具执行以下命令启动自动闭环修复流程：

```bash
# 单模块所有 Bug
bash .claude/scripts/bug-fix-loop.sh "{version}" "{feature_name}"

# 指定 Bug 编号
bash .claude/scripts/bug-fix-loop.sh "{version}" "{feature_name}" "{bug_index}"
```

脚本会自动完成以下阶段，**全程无需人工干预**：

### 阶段零-A：客户端运行时错误诊断（自动）
- 读取 Unity Editor.log，提取 Exception/Error/NullReference/StackTrace 等
- 通过 Unity MCP（`mcp__unityMCP__read_console`）读取 Unity Console 错误和警告
- 收集的诊断信息自动注入后续阶段的上下文，作为根因分析的重要线索
- MCP 不可用时自动降级为仅 Editor.log

### 阶段一：根因分析（每个 Bug 独立 Claude 实例）
- 读取 Bug 文档和设计文档
- **利用阶段零-A 收集的客户端错误信息**辅助定位
- **客户端 Bug 深度诊断**：通过 Unity MCP 读取 Console + Editor.log 中的堆栈信息直接定位出错文件和行号
- 定位问题代码（客户端/服务端/协议/配置）
- 输出结构化根因分析报告
- 产出：`docs/bugs/{version}/{feature}/{N}/analysis.md`

### 阶段二：修复迭代循环（核心闭环）
- **奇数轮**：实施修复 / 修复 Review 问题（独立 Claude 实例）
  - 客户端修复前：读取 Editor.log + Unity MCP Console 确认当前错误状态
  - 客户端修复后：通过 Unity MCP 触发重编译并验证无新增错误
  - 编译验证（Server `make build` + `make test` + Client Unity 双保险）
  - 编译失败时自动启动修复（最多重试 3 次）
- **偶数轮**：Review 修复质量（独立 Claude 实例，使用 `bug/fix-review` 命令）
  - 验证根因修复、合宪性、副作用、最小化修改
  - 输出结构化 counts 元数据
- **收敛判断**：
  - Critical=0 且 High≤2 → 质量达标，通过
  - 问题总数未减少 → 稳定不变，终止
  - 达到最大轮次（默认10轮）→ 强制终止
- 产出：`docs/bugs/{version}/{feature}/{N}/fix-review-report.md`

### 阶段三：经验固化 + 文档更新（独立 Claude 实例）
- 根据根因分析判断是否需要固化为 skill/rule
- 更新 Bug 文档：从未修复列表移除 → 追加到已修复记录
- 输出修复报告

### 阶段四：提交修复（自动 Git Commit）
- 每个 Bug 修复完成后，自动将所有变更提交到 Git
- Commit 消息格式：`fix(<模块>): 修复 Bug #N - <描述>`
- 使用 `/git:commit` 命令执行，失败时降级为直接 git commit

**每个阶段完成后自动进入下一阶段，每个步骤使用独立的 Claude 实例防止上下文污染。**

---

## 批量修复模式（无参数）

当 `$ARGUMENTS` 为空时进入此模式。**不调用 shell 脚本**，由当前会话直接编排。

### 步骤一：扫描所有未修复 Bug

遍历 `docs/bugs/` 下所有版本和模块，收集未修复条目：

```
对每个 docs/bugs/{version}/{feature}/{feature}.md：
  提取所有 "- [ ]" 行 → 记录 (version, feature, bug_number, bug_text)
```

输出扫描结果表格：

```
扫描结果：共 N 个未修复 Bug
| # | 版本 | 模块 | Bug | 涉及端 |
|---|------|------|-----|--------|
| 1 | 0.0.3 | V2_NPC | xxx | 客户端+服务端 |
| 2 | 0.0.3 | traffic | yyy | 仅客户端 |
```

如果未找到任何未修复 Bug，输出提示后结束。

### 步骤二：并行性判断

**并行条件**：不同 `(version, feature)` 组合的 bug 可以并行修复。

**冲突检测**（满足任一则标记为串行）：
1. **同模块同版本**：同一个 `{version}/{feature}` 下的多个 bug 必须串行（共享代码区域）
2. **跨端共享协议**：如果两个不同模块的 bug 都涉及 Proto 协议修改（`old_proto/`），标记为串行
3. **共享基础设施**：如果两个模块的 bug 都涉及同一个基础组件（如 `BigWorldNpcController`），标记为串行

**判断方法**：
- 快速阅读每个 bug 描述和所在模块的索引文件
- 按 `(version, feature)` 分组，每组内串行
- 不同组之间默认并行，除非检测到上述冲突

输出并行计划：

```
并行计划：
  组 A（串行）：0.0.3/V2_NPC bug#1, bug#2
  组 B（串行）：0.0.3/traffic bug#1
  → 组 A 和组 B 可并行执行
```

### 步骤三：并行执行修复

对每个可并行的组，使用 **Agent 工具**启动独立 agent：

- 每个 agent 调用 `bash .claude/scripts/bug-fix-loop.sh "{version}" "{feature_name}"` 修复该组的所有 bug
- **受主 agent 并发限制（单轮最多 3 个 Agent）**：超过 3 组时分批启动，前一批完成后启动下一批
- 每个 agent 使用 `isolation: "worktree"` 隔离工作目录，避免并行修复互相覆盖文件

**Agent prompt 模板**：
```
修复 docs/bugs/{version}/{feature}/ 下的所有未修复 Bug。

执行命令：
bash .claude/scripts/bug-fix-loop.sh "{version}" "{feature_name}"

完成后报告：
1. 修复了几个 bug，失败了几个
2. 每个 bug 的一句话总结
3. 是否有需要手动关注的问题
```

### 步骤四：汇总结果

所有 agent 完成后，汇总输出：

```
═══════════════════════════════════════
  批量修复完成
═══════════════════════════════════════
  总 Bug: X
  已修复: Y
  失败: Z
  总耗时: Ns

  详情：
  | 版本 | 模块 | Bug | 状态 | 耗时 |
  |------|------|-----|------|------|
  | ... |
═══════════════════════════════════════
```

### 步骤四点五：Worktree 合并回主工作目录

每个 agent 使用 `isolation: "worktree"` 后，其变更在独立分支上。需逐组合并回主分支。

**合并流程**：

1. **收集分支**：从每个 agent 返回结果中提取 worktree 分支名（Agent tool 返回值包含 branch 信息）
2. **逐组合并**（按组内 bug 数从多到少排序，大组优先）：
   ```bash
   git merge --no-ff <worktree-branch> -m "merge: batch fix {version}/{feature}"
   ```
3. **冲突处理**：如果 merge 产生冲突
   - 启动独立 Agent 解决冲突：prompt 包含 `git diff --name-only --diff-filter=U` 输出 + 两组修复的意图说明
   - Agent 解决后 `git add . && git commit`
   - 如果 Agent 也无法解决，标记该组为"需手动合并"并 `git merge --abort`
4. **合并后验证**：每次 merge 后执行编译验证
   ```bash
   cd P1GoServer && make build  # 服务端
   # + Unity MCP console-get-logs 检查客户端
   ```
   编译失败则回滚该组 `git reset --hard HEAD~1`，标记为"合并后编译失败，需手动处理"
5. **清理**：合并完成后删除 worktree 和临时分支
   ```bash
   git worktree remove <path> 2>/dev/null
   git branch -d <branch> 2>/dev/null
   ```

**降级策略**：如果所有组都合并失败，输出各 worktree 分支名和路径，提示用户手动 cherry-pick。

---

## 注意事项

- 脚本需要 `claude` CLI 可用
- 全程无人工干预，所有决策自主完成
- 每个 Bug 的修复日志：`docs/bugs/{version}/{feature}/{N}/fix-log.md`
- 如果某个 Bug 修复失败，不影响后续 Bug 的修复
- 并行修复时注意编译验证可能冲突（两个 agent 同时 `make build`），worktree 隔离可避免此问题

---

请先完成参数解析，然后执行对应流程。
