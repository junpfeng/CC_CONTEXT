---
name: 多窗口并行开发隔离方案审查（v1-v4，含v4深度审查）
description: Feature 级 Git Worktree 并行隔离方案v1-v5审查（2026-04-01），v5通过0C/0H/3M可进入实现
type: project
---

多窗口并行开发隔离方案审查 v1-v4（2026-04-01）

**Why:** 项目需要支持多个 Claude Code 窗口并行开发不同 feature / bug

**v5 审查状态: 通过 (0C/0H/3M)，可进入实现**

关键发现：
- CRITICAL: auto-work-loop.sh 使用 Client/Server/Proto 别名，但实际目录是 freelifeclient/P1GoServer/old_proto，task worktree 功能当前就是坏的
- HIGH: SKILL.md 中 `cd` 在 Claude Code 中不持久化（每次 bash 调用新 shell），必须用绝对路径或同一命令行内 cd
- HIGH: merge 后 proto 再生成的代码未自动 commit，导致主工作区 dirty
- HIGH: 打表 dir_file_server 指向绝对路径 Y:/dev/config，并行打表会互踩

**v4 已确认正确的部分:**
- 平级 worktree 的 proto 生成相对路径兼容性（dir_file 中 ../../freelifeclient 从 P1--xxx/old_proto/_tool_new/ 正确解析）
- mkdir 原子锁 + tasklist PID 检测的 Windows 兼容性
- merge 的 dry-run + pre_heads 回滚 + 串行锁三层保护
- Registry JSON + Python 操作避免 shell 注入

**关键模式（跨版本持续有效）:**
- dir_file 是 gitignored 配置文件，worktree 方案必须显式复制
- Shell->外部语言（Python）传参必须用 stdin/argv，禁止字符串拼接
- mkdir 锁的 pid 写入窗口必须处理崩溃场景
- 路径正则匹配必须约束 feature_name 字符集（禁止 `--`）
- Git Bash 在 Windows 上会将 `//` 解释为 UNC 路径，tasklist 参数需 MSYS_NO_PATHCONV=1
- Claude Code Bash 工具每次调用是新 shell，cd 不持久化，SKILL.md 中不能依赖 cd 切目录
- 打表工具 dir_file_server 指向绝对路径，并行 worktree 场景需要锁或路径隔离

**How to apply:** 审查 worktree/锁方案时：(1) 检查 gitignored 输入文件 (2) Shell->外部语言传参安全性 (3) 锁的崩溃恢复路径 (4) 路径模式匹配的边界 case (5) Windows Git Bash 路径转义 (6) LLM prompt 中 bash 命令的 CWD 假设
