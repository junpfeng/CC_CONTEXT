---
description: 对 freelifeclient/P1GoServer/Proto 三个工程暂存变更并生成规范的 commit
argument-hint: [commit message (可选)]
---

## 任务

对 Client、Server、Proto 三个 git 仓库分别检查变更并创建规范的 commit。

## 工作流程

### 第一步：检查所有仓库变更

对以下三个目录**并行**执行检查：
- `freelifeclient/`
- `P1GoServer/`
- `old_proto/`

每个仓库执行：
- `git -C <dir> status`
- `git -C <dir> diff`
- `git -C <dir> diff --cached`
- `git -C <dir> log --oneline -3`

### 第二步：筛选有变更的仓库

只处理有实际变更（未暂存或未追踪文件）的仓库。没有变更的仓库跳过并告知用户。

如果三个仓库都没有变更，告知用户并结束。

### 第三步：逐仓库分析并暂存

对每个有变更的仓库：

1. 分析变更内容，理解修改目的
2. **排除敏感文件**：不暂存 `.env`、`credentials.json`、密钥文件等
3. **精确暂存**：使用 `git -C <dir> add <具体文件>` 逐个暂存，**不要使用 `git add .` 或 `git add -A`**

### 第四步：生成 commit 消息

用户传入的参数：`$ARGUMENTS`

**如果用户提供了 commit message**：三个仓库使用相同的消息基础，可根据各仓库变更内容适当调整。

**如果用户没有提供 commit message**：根据各仓库的变更内容分别自动生成。

**消息格式：**
```
<type>: <简洁描述>

<详细说明（可选，当变更复杂时添加）>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

**type 枚举：** `feat` / `fix` / `refactor` / `docs` / `test` / `chore` / `style`

**消息规范：**
- 第一行不超过 70 字符
- 用中文描述
- 聚焦"为什么"而不是"是什么"

### 第五步：逐仓库执行 commit

对每个有变更的仓库，使用 HEREDOC 格式执行 commit：

```bash
git -C <dir> commit -m "$(cat <<'EOF'
<commit message>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

### 第六步：汇总结果

展示每个仓库的 commit 结果：

```
✓ Client: <commit hash> <commit message 摘要>
✓ Server: <commit hash> <commit message 摘要>
✓ Proto:  <commit hash> <commit message 摘要>
- Client: 无变更，跳过
```

如果某个仓库 commit 因 pre-commit hook 失败，修复后创建**新的** commit。

---

## 禁止事项

1. **禁止 `git add .` 或 `git add -A`**：必须逐个文件暂存
2. **禁止 `--no-verify`**：不跳过 pre-commit hooks
3. **禁止 `--amend`**：除非用户明确要求
4. **禁止 `git push`**：只 commit 不 push
5. **禁止提交敏感文件**
