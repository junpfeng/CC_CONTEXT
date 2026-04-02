---
description: 暂存变更并生成规范的commit
argument-hint: [commit message (可选)]
---

## 任务

暂存当前变更并创建一个规范的 git commit。

## 工作流程

### 第一步：检查变更

并行执行以下命令：
- `git status`：查看所有未暂存和未追踪的文件
- `git diff`：查看已修改文件的具体变更
- `git diff --cached`：查看已暂存的变更
- `git log --oneline -5`：查看最近 5 条 commit 消息，了解本仓库的消息风格

### 第二步：分析变更并暂存

1. 分析所有变更，理解本次修改的目的和范围
2. **排除敏感文件**：不暂存 `.env`、`credentials.json`、密钥文件等。如果发现此类文件，警告用户
3. **精确暂存**：使用 `git add <具体文件>` 暂存相关文件，**不要使用 `git add .` 或 `git add -A`**
4. 如果没有任何变更可以提交，告知用户并结束

### 第三步：生成 commit 消息

用户传入的参数：`$ARGUMENTS`

**如果用户提供了 commit message**：直接使用用户提供的消息作为 commit 消息的基础，可以适当润色但保留原意。

**如果用户没有提供 commit message**：根据变更内容自动生成，遵循以下规则：

**消息格式：**
```
<type>: <简洁描述>

<详细说明（可选，当变更复杂时添加）>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

**type 枚举：**
- `feat`：新功能
- `fix`：Bug 修复
- `refactor`：重构（不改变功能）
- `docs`：文档变更
- `test`：测试相关
- `chore`：构建/工具/配置变更
- `style`：代码风格调整（不影响逻辑）

**消息规范：**
- 第一行不超过 70 字符
- 用中文描述（与项目风格一致）
- 聚焦"为什么"而不是"是什么"
- 多文件变更时在 body 中用要点列出关键修改

### 第四步：执行 commit

使用 HEREDOC 格式执行 commit：

```bash
git commit -m "$(cat <<'EOF'
<commit message>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

### 第五步：确认结果

执行 `git status` 确认 commit 成功，向用户展示 commit hash 和摘要。

如果 commit 因 pre-commit hook 失败：
1. 分析失败原因
2. 修复问题
3. 重新暂存修复后的文件
4. 创建**新的** commit（不要用 `--amend`）

---

## 禁止事项

1. **禁止 `git add .` 或 `git add -A`**：必须逐个文件暂存
2. **禁止 `--no-verify`**：不跳过 pre-commit hooks
3. **禁止 `--amend`**：除非用户明确要求
4. **禁止 `git push`**：只 commit 不 push，push 需要用户单独指示
5. **禁止提交敏感文件**：`.env`、密钥、证书等
