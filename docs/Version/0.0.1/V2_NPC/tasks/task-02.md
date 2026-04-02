---
name: Server 四维度 Handler 实现
status: completed
---

## 范围
- 新增: P1GoServer/common/ai/execution/handlers/bigworld_engagement_handler.go — 大世界 engagement 维度 Handler（P0 简化版：仅支持 Idle/Alert 两种状态，玩家靠近时切 Alert）
- 新增: P1GoServer/common/ai/execution/handlers/bigworld_expression_handler.go — 大世界 expression 维度 Handler（P0 简化版：基础情绪驱动表情，衰减/恢复机制）
- 新增: P1GoServer/common/ai/execution/handlers/bigworld_locomotion_handler.go — 大世界 locomotion 维度 Handler（Walk/Run/Idle 移动模式切换，速度写入 NpcMoveComp.RunSpeed）
- 新增: P1GoServer/common/ai/execution/handlers/bigworld_navigation_handler.go — 大世界 navigation 维度 Handler（A* 寻路 + Y 坐标 Raycast 修正 + 三级降级策略 + 红绿灯感知 + 车辆避让 5m 检测；TrafficManager 通过 SceneImplI 接口获取，nil 时跳过车辆检测默认通行）

## 验证标准
- `cd P1GoServer && make build` 编译通过
- 四个 Handler 均实现 Handler 接口（Execute 方法签名正确）
- NavigationHandler 中 Raycast 降级三级策略完整：Raycast → SphereCast → lastValidY → 连续 30 帧 despawn
- NavigationHandler 不直接 import TrafficManager（通过 SceneImplI 接口）
- 角度变量命名带单位后缀（headingRad/headingDeg），无弧度与度数混用

## 依赖
- 依赖 task-01（Pipeline 注册后 Handler 才有挂载点）
