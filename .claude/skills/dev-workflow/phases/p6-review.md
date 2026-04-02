# Phase 6：产出审查

> 领域依赖：无

## 第零步：确定审查范围

仅审查 progress.json 中 status="tested" 的 task（跳过 discarded/timeout）。提取这些 task 涉及的文件列表作为审查输入。

## 第一步：3 Agent 并行审查

同时启动 3 个 subagent，每个传入：**设计文档路径 + requirements.json 路径 + git diff 范围**。

| Agent | 职责 |
|-------|------|
| **dev-workflow-code-reviewer** | 代码质量、Rules 合规、编码规范、事务性（验证顺序、回滚机制、锁/并发、幂等、超时、资源泄漏） |
| **dev-workflow-security-reviewer** | 注入、凭证泄露、越权访问、跨工程安全边界 |
| **dev-workflow-test-designer** | 测试覆盖充分性 |

## 第二步：综合审查

- **常规需求**（task < 6）：主 agent 直接执行综合审查
- **大需求**（task ≥ 6）：综合审查委托给第 4 个 subagent，主 agent 只收报告

综合审查内容：

1. 提取设计文档中所有功能点和验收标准
2. 分工程 git diff 查看改动
3. 逐项核对功能实现完整性
4. 协议/配置/DB 一致性检查
5. 事务性检查（边界、回滚、并发、幂等是否与设计一致）
6. 跨工程集成检查（数据流是否连通）
7. 运行构建测试确认通过
8. 汇总 3 个 Agent 审查结果
9. **跨 skill 经验索引检查**：若 `docs/knowledge/consolidation-index.md` 存在，读取 `## Error Patterns` 和 `## Review Checklist Additions` section，将其中的检查项作为补充审查清单逐条核对

## 输出审查报告

包含：功能完整性核对表、各工程改动汇总、一致性核对（协议/配置/DB/事务）、Agent 审查汇总、问题修复建议、测试覆盖情况。

每个 Agent 必须返回：**问题列表**（每项含位置、问题描述、修改建议）和**结论**（通过 / 不通过）。

## 审查循环（含质量棘轮）

1. 汇总 3 个 Agent + 综合审查的结果，记录 `total = critical + high`
2. 若有问题 → **保存 fix checkpoint**（各仓库 `git rev-parse HEAD`）→ 主 agent 逐项修复 → 重新派发审查
3. 修复后重新计数 `new_total`：
   - `new_total < prev_total` → 继续下一轮修复
   - `new_total >= prev_total` → **回滚到 fix checkpoint**，保留修复前版本

> 注：P6 棘轮针对 review 的 critical+high，与 P5 编译/测试棘轮独立运作。
4. 若全部通过（critical=0 且 high<=2）→ 审查结束
5. **最多循环 10 轮**，第 10 轮仍有问题则标注在审查报告的「遗留问题」章节，**仍继续进入 P7**
6. 每轮 issue 计数写入 progress.json 的 `review_rounds` 数组供 P7 Meta-Review 分析
7. **记录到 results.tsv**：每轮审查结果追加到 `{design_doc_dir}/results.tsv`，`phase` 填 `P6`，填写 `review_critical` 和 `review_high` 实际值

> **P6 不执行 Task Discard**：与 P4/P5 不同，P6 只做修复回滚（质量棘轮），不将 task 标记为 discarded。原因：代码已通过编译和测试（P4/P5），审查问题属于质量提升而非功能缺陷。未解决的审查问题标注在「遗留问题」章节，由后续版本处理。
>
> **P6 fix checkpoint 清理**：每轮修复回滚后（或审查通过后），删除该轮的 fix checkpoint（git stash drop 或从 progress.json 移除临时 HEAD 记录），避免 checkpoint 无限累积。

**审查通过（或标注遗留后）自动进入 Phase 7。**
