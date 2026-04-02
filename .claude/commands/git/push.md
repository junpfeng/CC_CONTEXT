---
description: 推送当前分支到远程仓库
argument-hint: [remote branch (可选)]
---

## 任务

将当前分支的 commit 推送到远程仓库。

## 工作流程

### 第一步：检查状态

并行执行以下命令：
- `git status`：确认工作区状态（是否有未提交的变更）
- `git log --oneline origin/$(git branch --show-current)..HEAD`：查看将要推送的 commit 列表
- `git branch -vv`：确认当前分支的远程追踪关系

### 第二步：安全检查

1. **未提交变更警告**：如果有未暂存或未提交的变更，提醒用户是否需要先 commit
2. **主分支保护**：如果当前分支是 `main` 或 `master`，正常 push（不允许 force push）
3. **无 commit 可推**：如果没有新 commit 需要推送，告知用户并结束

### 第三步：解析参数并执行 push

用户传入的参数：`$ARGUMENTS`

**如果用户提供了参数**：按 `remote branch` 解析，执行 `git push <remote> <branch>`
**如果用户没有提供参数**：
- 如果当前分支已有远程追踪分支 → `git push`
- 如果当前分支没有远程追踪分支 → `git push -u origin <当前分支名>`

### 第四步：确认结果

执行成功后，向用户展示：
- 推送的 commit 数量和范围
- 远程分支 URL（如果可用）

如果推送失败：
- **rejected（非 fast-forward）**：提示用户需要先 pull，**绝不自动 force push**
- **认证失败**：提示用户检查 git 凭证配置
- **其他错误**：展示错误信息

---

## 禁止事项

1. **禁止 `git push --force` 或 `git push -f`**：除非用户明确要求
2. **禁止 force push 到 main/master**：即使用户要求也要警告
3. **禁止推送敏感信息**：如果发现最近 commit 包含 `.env`、密钥等，警告用户
