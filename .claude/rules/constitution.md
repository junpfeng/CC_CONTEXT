---
paths:
---

# 工作空间宪法

以下规则具有最高优先级，任何情况下不得违反。

## 禁止手动编辑的区域

1. `config/RawTables/` — 策划配置来自数据系统，勿手动修改

## 工作流程

2. 修改代码前必须查阅对应项目的 `.claude/rules/`，包括其 `constitution.md`
3. 仅在需要阅读或修改某个子工程时，才加载其 `CLAUDE.md` 和 rules，不要一次性全部加载

## 子工程索引

| 工程 | CLAUDE.md | Rules 路径 | 说明 |
|------|-----------|-----------|------|
| P1GoServer | `P1GoServer/CLAUDE.md` | `P1GoServer/.claude/rules/` | Go 游戏服务器 |
| server_old | `server_old/CLAUDE.md` | — | 旧版服务器（Rust），目前仅 scene 进程在使用 |
| config | `config/CLAUDE.md` | — | 策划配置（自动生成） |
| proto | `proto/CLAUDE.md` | — | 协议工程 |
