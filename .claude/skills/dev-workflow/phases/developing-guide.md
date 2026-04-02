# 开发执行指南

> 本文档供 P4 的 subagent / CLI 进程引用，确保所有执行单元行为一致。

## 执行步骤

1. **Read 设计文档**：找到自己负责的 TASK-XXX 定义，理解范围和验收标准
2. **Read 工程规范**：进入目标工程目录，读取 CLAUDE.md 和 `.claude/rules/`
3. **Read 对标代码**：找到设计文档中引用的参考实现，理解现有模式
4. **实现代码**：按设计文档逐项实现，不偏离设计（偏离必须在结果中说明原因）
5. **机械规则扫描**：
   - C#：grep `MLog.*\$"` 检查日志插值 → 改 `+` 拼接
   - C#：检查 async 方法带 CancellationToken
   - C#：检查 using 是否需要 Vector3 alias
   - Go：grep `%[ds]` 在 log 行 → 改 `%v`
   - Go：grep 日志字段命名统一 `npc_entity_id=` 格式
6. **编译验证**：Server `cd P1GoServer && make build`；Client `console-get-logs`
7. **完成性声明**：返回结果中必须包含 `ALL_FILES_IMPLEMENTED: true/false` + 文件列表

## 硬性约束

- **禁止留 TODO/占位符**：配置值从设计文档 + 已有代码模式推断填写
- **禁止偏离设计而不报告**：如因技术原因简化了设计，在结果的 issues 字段说明
- **先验证后执行**：涉及状态变更时，先检查前置条件再执行操作
- **错误必须处理**：不忽略错误，包装上下文信息，Go 用 `log.Errorf`，C# 用 `MLog.Error?.Log`
