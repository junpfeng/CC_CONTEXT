---
name: schedule-moveto-targetpos-align-review
description: 审查 behaviorType=1 两段式移动设计，两轮审查记录
type: project
---

## 第一轮（2026-03-18）
1. ScenarioPhase 复用残留值风险 → 已修复：改为独立 MoveToPhase 字段
2. GetPointPos 坐标单位不明 → 已修复：文档补充说明
3. faceDirection 缺失 → 已修复：phase 2 到达后设置朝向
4. 到达检测仅距离 → 已修复：双信号（IsMoving OR 距离）

## 第二轮（2026-03-18）
严重问题：
1. SetEntityFaceDirection 不存在于 SceneAccessor 接口，伪代码调用会编译失败。需新增接口方法或改用其他机制。
2. phase 0 fallthrough 到 case 2 时 sched.TargetPos 未赋值（零值 Vec3），移动目标错误。

建议改进：
3. case 2 入口的 MoveToPhase != 2 判定逻辑可简化
4. toVecList 辅助函数应明确复用现有指针→值转换逻辑

确认无问题：MoveToPhase 的 Snapshot 同步（值类型自动拷贝）、OnExit 重置清单、常量阈值。

## 第三轮（2026-03-18）
已修复：移除 SetEntityFaceDirection、TargetPos 提前赋值、phase1 检测移入 switch 内部、GetPointPos 使用 MapInfo.roads、case2 清理。

## 第四轮（2026-03-18）
严重问题：
1. GetPointPos 实现放在 MapRoadNetworkMgr 上，但 RoadNetQuerier 实际实现者是 *Map（scene_impl.go:261 roadNetQ = roadNetMgr.MapInfo）。必须改为 Map 的方法。

确认无问题：字段名一致（MapInfo/*Map, roads/[]*RoadNetwork, GetPointByID）、case0 fallback→phase2 只需到达检测（移动指令已发出）、MoveToPhase 独立字段、双信号检测、重置点覆盖。

**Why:** 接口实现者的确认必须追溯到注入点（scene_impl.go），不能仅看类型名猜测。
**How to apply:** 设计文档中新增接口方法时，必须确认接口的实际实现者是哪个类型，追溯到依赖注入处核实。
