# git-commit-push 已知问题与处理经验

> 此文件由 skill 在运行过程中自动维护。遇到新异常后追加记录，处理策略成熟后迁移到 SKILL.md 的异常表格。

## 记录格式

```
### [日期] <异常简述>
- **工程**：<触发工程>
- **现象**：<错误信息或行为描述>
- **处理方式**：<执行了什么操作>
- **结果**：成功 / 失败（需人工介入）
- **备注**：<补充说明，如是否已迁移到 SKILL.md>
```

---

### [2026-03-12] commit-msg hook 格式限制（client）
- **工程**：freelifeclient
- **现象**：hook 拒绝 `chore:` 和 `build:` 格式，报错要求格式为 `<type>(scope) description`，type 限于 `ci|build|docs|feat|fix|pref|refactor|style|test`
- **处理方式**：读取 `.git/hooks/commit-msg` 获取正则 `^<(ci|build|docs|feat|fix|pref|refactor|style|test)>\(.+\)[ ]*.+$`，将 message 改为 `<build>(npc) ...` 格式
- **结果**：成功
- **备注**：三个工程统一使用此格式（server/proto 无 hook 但应保持一致）

### [2026-03-12] 分支无上游导致 push 失败（client）
- **工程**：freelifeclient
- **现象**：`plan/plan_b_npc` 为新分支，push 时报 `fatal: The current branch has no upstream branch`
- **处理方式**：自动改用 `git push --set-upstream origin plan/plan_b_npc`
- **结果**：成功
- **备注**：已将此情形补充到 SKILL.md 异常自动处理表格中

### [2026-03-19] HTTPS 凭据失效自动重试一次（client）
- **工程**：freelifeclient
- **现象**：push 报 `Authentication failed`（exit code 128）
- **处理方式**：自动重试一次，重试成功
- **结果**：成功
- **备注**：用户明确要求凭据失败时重试一次，已覆盖 SKILL.md 默认"不重试"策略
