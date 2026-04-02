---
name: NPC 日程系统技术设计审查
description: 2026-03-13 审查 schedule tech-design.md 发现的关键问题和模式
type: project
---

NPC 日程与巡逻系统技术设计审查完成（docs/design/ai/schedule/tech-design.md）。

关键发现：
1. **CurrentPlan 路由机制存在一帧延迟**：ScheduleHandler 写入 CurrentPlan 后，Brain 在下一帧才读取到（因 snapshot 是帧初生成），导致 plan 切换有一帧空转。需要改为同帧内切换或直接 dispatch。
2. **FieldAccessor 未注册新增字段**：5 个新 ScheduleState 字段需在 field_accessor.go 的 resolveSchedule 中注册，否则 Brain 表达式无法解析。

**Why:** 这些问题会导致运行时行为异常（路由延迟）或直接功能失效（字段解析 error）。

**How to apply:** 实现阶段必须先解决 S1/S2，S1 建议 ScheduleHandler 内部直接 dispatch 子 Handler 而非二次走 Brain 决策。
