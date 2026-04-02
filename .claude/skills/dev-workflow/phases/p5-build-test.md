# Phase 5：构建与测试

> 领域依赖：无

## 执行模式

- **常规需求**（task < 6）：主 agent 直接执行构建和测试
- **大需求**（task ≥ 6）：构建验证委托给 subagent，主 agent 只收 pass/fail + 错误摘要

## 构建验证

> **注**：P4（4.1.7）已完成 Post-wave 编译验证并写入 `waves.wave-N.compile_ok: true`。

**P5 编译策略**：检查 progress.json 中 `waves.wave-N.compile_ok`：
- `true` → 跳过编译，直接进入测试
- `false` 或缺失 → 执行完整编译验证

## 测试执行

按各子工程测试规范执行：单元测试 → 集成测试 → 回归测试。

### 上下文控制

- 测试失败日志：主 agent 只保留**每个失败用例的前 10 行输出**，总计不超过 50 行
- MCP 截图/日志证据：写入文件，主 agent 只持有文件路径
- 修复派发：传递失败用例摘要（用例名 + 错误类型 + 位置），不传完整 stack trace

## Unity MCP 验收测试

当设计文档包含「验收测试」章节时，执行 Unity MCP 真人模拟测试。

### 执行流程

1. **读取测试方案**：从设计文档中提取所有 `[TC-XXX]` 测试用例
2. **环境准备**（任一步失败则自主排障，参见 CLAUDE.md 自主闭环规则）：
   - `editor-application-get-state` 确认 Unity Editor 状态。MCP 不通 → 执行 `scripts/unity-restart.ps1` 恢复
   - 如未在 Play 模式 → `editor-application-set-state` 进入 Play 模式，等待初始化完成
   - 如未登录游戏 → 调用 `/unity-login` 完成登录。登录失败 → 检查服务器状态并重试
   - 确认前置条件满足（场景、道具、状态等）
3. **逐用例执行**：按用例顺序依次执行每个操作步骤
4. **验证与记录**：每步验证后记录结果（通过 / 失败 + 截图/日志证据）
5. **异常场景**：执行用例中定义的异常场景测试

### BLOCKED 处理（环境阻塞自主排障）

> **BLOCKED ≠ FAIL**。FAIL 是代码有 bug，BLOCKED 是环境缺依赖。BLOCKED 不允许直接跳过——必须先尝试解决。

用例因环境依赖无法执行时（如：无测试实体、场景未加载、Manager 未初始化）：

1. **分析阻塞原因**：区分"环境依赖"（缺实体/未初始化）vs"代码缺陷"（初始化逻辑有 bug）
2. **尝试 workaround**（按优先级）：
   - GM 命令生成测试实体（如 `/ke* gm spawn_vehicle`）
   - `script-execute` 直接 Instantiate/初始化依赖对象
   - 修复依赖系统的初始化逻辑（如果是本功能范围内的遗漏）
3. **workaround 成功** → 继续执行被 BLOCKED 的用例
4. **workaround 全部失败**（≥3 种方案均不可行）→ 标记 BLOCKED + 详细原因 + 已尝试方案，但**不允许绕过 commit 前检查**（见下方 Keep/Discard 决策）

### 失败处理

- 用例失败时截图 + 抓取日志作为证据，不中断后续用例
- 明确区分：**代码 bug**（需回 Phase 4 修复）vs **测试方案问题**（调整用例）

### 修复循环

1. 如有失败用例 → 分析根因 → 退出 Play 模式（`editor-application-set-state`）→ 回 Phase 4 修复代码 → 重新构建确认编译通过
2. 重新进入 Play 模式 + 登录 → 执行失败的用例（不需要重跑已通过的）
3. **最多循环 3 轮**，仍有失败则标注在报告的「遗留问题」章节，**仍继续进入 P6**（P6 审查会再次发现这些问题）

### 遗留问题登记

修复循环 3 轮后仍有失败用例时，在继续进入 P6 之前：

1. 对每个遗留失败用例，调用 `bug:report` 登记到 `docs/bugs/{version}/{feature}/`
2. 将映射写入 `{design_doc_dir}/p5-residual-bugs.md`：
   ```markdown
   # P5 遗留问题 → Bug 映射

   | TC 编号 | Bug # | 失败现象 | 状态 |
   |---------|-------|---------|------|
   | TC-03 | {N} | {现象} | OPEN |
   ```
3. **不阻塞后续流程**——P6 审查、P7 沉淀照常进行
4. P7 完成后由 7.4.0 检查并启动独立进程修复遗留 bug

## Keep/Discard 决策

**仅对 status="compiled" 的 task 执行**，已 discarded/timeout 的 task 自动跳过。

| 条件 | 决策 |
|------|------|
| 编译通过 + 测试通过 | **Keep**：status `compiled` → `tested`，更新 progress.json |
| 编译通过 + 测试有失败但修复轮触顶 | **Keep with issues**：status `compiled` → `tested`，遗留问题记入报告 |
| 编译失败连续 3 次 | **Discard wave**：status → `discarded`，回滚 wave 检查点 |
| 修复后问题数量增加 | **回滚本轮修复**（质量棘轮），task 保持 `compiled`，跳出修复循环 |

### Discard 操作

优先回滚到 P4 保存的 **task 级检查点**（`git_checkpoints.TASK-XXX`）：
```bash
cd P1GoServer && git reset --hard {CKPT_server}
cd freelifeclient && git reset --hard {CKPT_client}
cd old_proto && git reset --hard {CKPT_proto}
```
仅在 task 间文件重叠时退化为 **wave 级检查点**（`git_checkpoints.wave-N`）。

标记 task `status: "discarded"`，记录 `error_summary` 供 P7 分析。

### 记录到 results.tsv

每轮 Keep/Discard 决策后，向 `{design_doc_dir}/results.tsv` 追加一行：
- `phase`：P5
- `action`：test-pass / test-fix / test-discard
- `compile_ok`：true（P5 阶段已编译通过）
- `review_critical` / `review_high`：填 `0`（P6 才填实际值，数值类型统一）
- **多轮修复**：每轮 fix 追加一行（action=test-fix），attempt 不变（同一次尝试内的修复，不算新 attempt）

### 质量棘轮（P5 测试修复轮）

每轮修复前保存 fix checkpoint（`git stash` 或记录当前 HEAD）。修复后重新计数：

**P5 棘轮指标 = 测试失败用例数**（不含编译错误，编译已在 P4 解决）：
- `new_fail_count < prev_fail_count` → 继续修复
- `new_fail_count >= prev_fail_count` → 回滚本轮修复到 fix checkpoint，保留修复前版本，跳出循环

> 注：P5 棘轮针对**测试失败用例数**，P6 棘轮针对 **review 的 critical+high 数**，两者独立运作、指标不同。

## 验证清单

- [ ] 构建通过
- [ ] 静态检查无错误
- [ ] 单元测试通过
- [ ] 涉及的生成代码已更新
- [ ] Unity MCP 验收测试通过（如有测试方案）
- [ ] 所有 kept task 的 progress.json 已更新

**全部通过后自动进入 Phase 6。**
