---
description: C# 日志字符串禁止 $"" 插值，必须用 + 拼接
globs:
alwaysApply: true
---

# C# 日志禁止字符串插值

## 触发条件
当编写或修改 C# 代码中的日志语句时触发：
- `MLog.Info?.Log(...)`, `MLog.Warning?.Log(...)`, `MLog.Error?.Log(...)`
- 任何写入日志的字符串参数

## 规则内容
1. **日志参数禁止使用 `$""` 字符串插值**，必须用 `+` 拼接
2. 正确：`MLog.Warning?.Log("未知状态ID: " + serverStateId)`
3. 错误：`MLog.Warning?.Log($"未知状态ID: {serverStateId}")`
4. 原因：`$""` 每次调用产生字符串堆分配（GC 压力），`+` 拼接在编译器优化下更高效
5. 编码完成后，对新增/修改的 `.cs` 文件 grep `\$"` 出现在 `MLog` 行中的情况，逐一替换

## 来源
auto-work meta-review #2，基于 0.0.1/V2_NPC task-06 的工作数据。
task-06 的 2 个 HIGH 全部是日志 `$""` 插值问题（BigWorldNpcFsmComp.cs:167、BigWorldNpcAnimationComp.cs:98），属于编码规范层面的机械性错误，可通过规则完全避免。
