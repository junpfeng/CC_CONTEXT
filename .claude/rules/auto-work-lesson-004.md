---
description: Review 修复轮只改被标记的问题，禁止扩散修改，防止引入新 bug 导致棘轮 discard
globs:
alwaysApply: true
---

# Review 修复纪律：只改标记问题，禁止扩散

## 触发条件
当 feature:develop-review 返回 HIGH/CRITICAL 问题需要修复时（即进入 fix 轮次）

## 规则内容
1. **逐条修复**：只修改 review 报告中明确标记的 HIGH/CRITICAL 问题，不"顺手"重构、优化或改动周边代码
2. **修复前列清单**：在动手前，将所有待修复项列为 checklist，逐项完成，每项改动后立即验证编译通过
3. **禁止新增文件**：fix 轮次原则上不新增文件。如果必须新增，需在 commit message 中说明原因
4. **回归自检**：fix 完成后，对每个被修改的函数，检查其调用者是否受影响。重点关注：
   - 新参数是否传递到所有调用点
   - 删除/重命名的字段是否有遗漏的引用
   - 构造函数/初始化路径是否完整赋值所有必要字段
5. **不引入新抽象**：fix 轮次禁止引入新接口、新基类、新设计模式。用最小改动解决标记问题

## 来源
auto-work meta-review #3，基于 0.0.1/V2_NPC 的工作数据。
task-05 修复轮 HIGH 从 3->4 触发棘轮 discard（浪费 ~800s）。
task-03 修复轮从 0C/3H->1C/3H，修复中引入新 CRITICAL（spawnNpcAt 生成位置未写入实体——核心功能失效）。
2/7 任务（29%）因 fix 轮引入新问题被 discard，MR#1/#2 连续提议此规则但未落地，本次为第 3 次提议后正式创建。
