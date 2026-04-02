---
description: Review发现同类型机械性问题时必须全量扫描修复，不能只改标记的几处
globs:
alwaysApply: true
---

# 同类型机械性问题全量扫描修复

## 触发条件
当 Review 报告中发现 ≥2 个相同类型的机械性问题时（如日志格式、命名规范、import 缺失、字符串拼接方式等）

## 规则内容
1. **全量扫描**：不要只修 review 标记的几处。用 grep/ripgrep 在所有相关文件中搜索同类违规，列出完整清单
2. **一次性修复**：对扫描结果逐一修复，确保零残留
3. **修复后验证**：再次 grep 确认同类违规数量为 0
4. **与 lesson-004 的关系**：lesson-004 要求"只改标记问题类型"，本规则在此基础上扩展——同类型问题必须全量覆盖，但禁止跨类型扩散。即：review 标记了 `%d` 格式符问题，就修所有 `%d`；但不要顺手改其他类型的问题

### 典型同类型问题及扫描命令
| 问题类型 | 扫描命令 |
|---------|---------|
| Go `%d`/`%s` 格式符 | `grep -rn '%[ds]' --include='*.go'` 在 log 语句行 |
| Go NPC 字段命名 | `grep -rn 'entityID=\|cfgId=' --include='*.go'` 在 log 语句行 |
| C# `$""` 日志插值 | `grep -rn 'MLog.*\$"' --include='*.cs'` |
| C# using alias 缺失 | 新建 .cs 文件中 `using FL.NetModule` 但无 Vector3 alias |

## 来源
auto-work meta-review #4，基于 0.0.1/V2_NPC task-04 的工作数据。
task-04 的 5/5 HIGH 全部是同类型日志格式违规（%d/%s + 字段命名），4 轮 fix（8 总轮次）始终无法收敛（2C/7H → 1C/3H → 0C/3H → 0C/5H），原因是每轮只修 review 标记的点，同文件其他同类违规在下轮 review 被发现为新 HIGH。8 轮迭代全部浪费。
