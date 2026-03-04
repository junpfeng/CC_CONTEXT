---
name: commit
description: 智能分析变更并生成规范的 Git 提交
---

# Git 提交助手

当用户调用此 skill 时，执行以下步骤：

## 步骤

1. **检查 Git 状态**
   - 运行 `git status` 查看所有变更文件
   - 运行 `git diff` 查看具体变更内容
   - 运行 `git diff --staged` 查看已暂存的变更

2. **分析变更**
   - 理解每个文件的变更目的
   - 识别变更类型（新功能、修复、重构、文档等）
   - 确定影响范围

3. **生成提交信息**
   遵循 Conventional Commits 规范：
   ```
   <type>(<scope>): <subject>

   <body>

   Co-Authored-By: Claude <noreply@anthropic.com>
   ```

   类型包括：
   - `feat`: 新功能
   - `fix`: 修复 bug
   - `docs`: 文档变更
   - `style`: 代码格式（不影响代码运行）
   - `refactor`: 重构
   - `perf`: 性能优化
   - `test`: 测试相关
   - `chore`: 构建过程或辅助工具变更

4. **执行提交**
   - 将相关文件添加到暂存区
   - 使用生成的提交信息创建提交
   - 显示提交结果

## 注意事项

- 不要提交包含敏感信息的文件（.env, credentials 等）
- 提交信息使用中文或英文（根据项目惯例）
- 如果变更较大，建议拆分为多个提交
