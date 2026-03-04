---
name: git
description: Git 操作助手，处理分支、合并、冲突等
---

# Git 操作助手

当用户调用此 skill 时，帮助处理各种 Git 操作。

## 常用操作

### 1. 分支管理

```bash
# 创建并切换分支
git checkout -b feature/xxx

# 查看所有分支
git branch -a

# 删除本地分支
git branch -d branch-name

# 删除远程分支
git push origin --delete branch-name

# 重命名分支
git branch -m old-name new-name
```

### 2. 查看变更

```bash
# 查看状态
git status

# 查看差异
git diff                  # 工作区 vs 暂存区
git diff --staged         # 暂存区 vs HEAD
git diff HEAD~1           # 与上一个提交比较
git diff branch1..branch2 # 两个分支比较

# 查看文件历史
git log --oneline -n 10
git log --follow -p -- file.go
git blame file.go
```

### 3. 撤销操作

```bash
# 撤销工作区修改
git checkout -- file.go

# 撤销暂存
git reset HEAD file.go

# 撤销最近一次提交（保留修改）
git reset --soft HEAD~1

# 修改最近一次提交
git commit --amend
```

### 4. 合并与变基

```bash
# 合并分支
git merge feature-branch

# 变基
git rebase main

# 交互式变基（整理提交）
git rebase -i HEAD~3

# 解决冲突后继续
git add .
git rebase --continue
```

### 5. Stash 暂存

```bash
# 暂存修改
git stash
git stash save "message"

# 查看暂存列表
git stash list

# 恢复暂存
git stash pop
git stash apply stash@{0}

# 删除暂存
git stash drop stash@{0}
```

### 6. 标签管理

```bash
# 创建标签
git tag v1.0.0
git tag -a v1.0.0 -m "Release version 1.0.0"

# 推送标签
git push origin v1.0.0
git push origin --tags

# 删除标签
git tag -d v1.0.0
git push origin --delete v1.0.0
```

## 冲突解决指南

### 1. 识别冲突
```
<<<<<<< HEAD
当前分支的代码
=======
合并分支的代码
>>>>>>> feature-branch
```

### 2. 解决步骤
1. 打开冲突文件
2. 理解两边的修改意图
3. 手动合并代码（删除冲突标记）
4. 测试代码是否正常工作
5. `git add` 标记解决
6. 继续合并/变基操作

### 3. 工具辅助
```bash
# 使用合并工具
git mergetool

# 放弃合并
git merge --abort
git rebase --abort
```

## 分支命名规范

| 类型 | 格式 | 示例 |
|------|------|------|
| 功能 | feature/xxx | feature/user-auth |
| 修复 | fix/xxx | fix/login-bug |
| 热修复 | hotfix/xxx | hotfix/security-patch |
| 发布 | release/x.x.x | release/1.0.0 |

## 使用方式

- `/git status` - 显示当前状态
- `/git branch` - 分支操作
- `/git merge` - 帮助合并分支
- `/git conflict` - 帮助解决冲突
- `/git history` - 查看历史
