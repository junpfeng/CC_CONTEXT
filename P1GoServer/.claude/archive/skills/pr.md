---
name: pr
description: 创建 Pull Request 并生成规范的描述
---

# Pull Request 创建助手

当用户调用此 skill 时，帮助创建规范的 Pull Request。

## 步骤

### 1. 分析当前分支状态
- 检查当前分支名称
- 对比 base 分支的差异
- 获取所有相关的 commit 历史

### 2. 生成 PR 标题
- 简洁明了，不超过 70 字符
- 描述主要变更内容
- 遵循项目命名规范

### 3. 生成 PR 描述

使用以下模板：

```markdown
## Summary
<!-- 1-3 个要点概述变更内容 -->
-
-
-

## Changes
<!-- 详细描述具体的变更 -->

### Added
-

### Changed
-

### Fixed
-

### Removed
-

## Test Plan
<!-- 测试计划和验证步骤 -->
- [ ] 单元测试通过
- [ ] 集成测试通过
- [ ] 手动测试验证

## Screenshots (if applicable)
<!-- 如果有 UI 变更，添加截图 -->

## Related Issues
<!-- 关联的 issue -->
Closes #

---
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

### 4. 创建 PR
- 确保代码已推送到远程
- 使用 `gh pr create` 创建 PR
- 返回 PR 链接

## 使用方式

- `/pr` - 基于当前分支创建 PR 到主分支
- `/pr base-branch` - 指定目标分支
- `/pr --draft` - 创建草稿 PR
