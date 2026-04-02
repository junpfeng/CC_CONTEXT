---
description: 对 freelifeclient/P1GoServer/Proto 三个工程推送当前分支到远程仓库
argument-hint: [remote branch (可选)]
---

## 任务

将 Client、Server、Proto 三个 git 仓库的当前分支分别推送到各自的远程仓库。

## 工作流程

### 第一步：检查所有仓库状态

对以下三个目录**并行**执行检查：
- `freelifeclient/`
- `P1GoServer/`
- `old_proto/`

每个仓库执行：
- `git -C <dir> status`
- `git -C <dir> branch -vv`
- `git -C <dir> log --oneline origin/$(git -C <dir> branch --show-current)..HEAD 2>/dev/null`

### 第二步：逐仓库安全检查

对每个仓库：

1. **未提交变更警告**：如果有未暂存或未提交的变更，提醒用户是否需要先用 `/git/gta-commit` 提交
2. **主分支保护**：如果当前分支是 `main` 或 `master`，正常 push（不允许 force push）
3. **无 commit 可推**：如果没有新 commit 需要推送，标记为跳过

筛选出有新 commit 需要推送的仓库。如果三个仓库都没有需要推送的 commit，告知用户并结束。

### 第三步：解析参数并执行 push

用户传入的参数：`$ARGUMENTS`

对每个需要推送的仓库：

**如果用户提供了参数**：按 `remote branch` 解析，执行 `git -C <dir> push <remote> <branch>`
**如果用户没有提供参数**：
- 如果当前分支已有远程追踪分支 → `git -C <dir> push`
- 如果当前分支没有远程追踪分支 → `git -C <dir> push -u origin <当前分支名>`

### 第四步：汇总结果

展示每个仓库的推送结果：

```
✓ Client: 推送 3 个 commit 到 origin/plan/plan_b_weapon
✓ Server: 推送 1 个 commit 到 origin/plan/plan_b_weapon
✓ Proto:  推送 2 个 commit 到 origin/master
- Client: 无新 commit，跳过
```

如果推送失败：
- **rejected（非 fast-forward）**：提示用户需要先 pull，**绝不自动 force push**
- **认证失败**：提示用户检查 git 凭证配置
- **其他错误**：展示错误信息

---

## 禁止事项

1. **禁止 `git push --force` 或 `git push -f`**：除非用户明确要求
2. **禁止 force push 到 main/master**：即使用户要求也要警告
3. **禁止推送敏感信息**：如果发现最近 commit 包含 `.env`、密钥等，警告用户
