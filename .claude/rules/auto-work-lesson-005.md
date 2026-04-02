---
description: 编码完成后必须对照 plan 逐项自查关键设计点，防止简化实现偏离设计被 review 打回
globs:
alwaysApply: true
---

# 编码后 Plan 合规自查

## 触发条件
当 feature:developing 编码完成、准备提交 review 之前

## 规则内容
1. **重新打开 plan.json**，逐条检查当前 task 的设计要求
2. **对照检查清单**（每条回答 YES/NO/偏离）：
   - 数据结构是否按 plan 定义实现（字段名、类型、层级）
   - 算法/策略是否按 plan 描述实现（不是"用更简单的方式替代"）
   - 接口签名是否与 plan 一致
   - 配置参数是否齐全（plan 要求的参数不能硬编码为魔法数字）
3. **偏离必须记录**：如果因技术原因简化了 plan 的某项设计，必须在 develop-log 中记录偏离点和原因。未记录的偏离视为遗漏
4. **已有规则扫描**：编码完成后，对新增/修改的文件扫描已知的机械性规则：
   - C# 文件：grep MLog.*$" 检查日志插值（lesson-003）
   - C# 文件：检查 async 方法是否带 CancellationToken（feedback_unitask_cancellation）
   - C# 文件：检查 using 是否需要 Vector3 alias（feedback_netmodule_using_alias）
   - Go 文件：grep log 语句中的 `%d`/`%s` 格式符，必须改为 `%v`（P1GoServer logging.md）
   - Go 文件：grep NPC 相关日志中的 `entityID=`/`cfgId=`，必须改为 `npc_entity_id=`/`npc_cfg_id=`（P1GoServer logging.md）
   - Go 文件：grep 日志模块标签格式，统一 `[ClassName]` 方括号格式（P1GoServer logging.md）

## 来源
auto-work meta-review #3/#4，基于 0.0.1/V2_NPC 的工作数据。
task-05 的主要 HIGH 是"LOD 插值参数未按 plan 实现"——编码时用帧间隔硬编码替代了 plan 要求的三级 LOD 插值时间窗口和曲线策略，未记录偏离，直到 review 才被发现。
task-06 的 2 个 HIGH 是 $"" 日志插值，属于已有规则（lesson-003）可机械检查的问题，编码时未执行扫描。
task-04 的 5/5 HIGH 全部是 Go 日志格式违规（已有 logging.md 规则），编码时未执行 Go 侧扫描。MR#4 补充 Go 扫描项。
