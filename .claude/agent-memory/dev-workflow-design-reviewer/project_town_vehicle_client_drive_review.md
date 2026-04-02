---
name: Town Vehicle Client Drive Review
description: S1Town 交通车辆客户端驱动设计审查（2026-03-20），核心问题：设计未基于已有 TownTrafficMover 实现，提出了架构不一致的全新方案
type: project
---

S1Town 交通车辆客户端驱动 + 移动平滑优化设计审查，结论：不通过。

核心问题：
1. 设计提出新建 VehicleClientDriveComp (ECS Comp) + Catmull-Rom，但项目已有完整实现 TownTrafficMover (MonoBehaviour) + 线性插值 + Y 平滑
2. 服务端 IsClientDrive 字段冗余——客户端已通过 ExternalDisableNetTransform 忽略服务端 Transform
3. 超时清理机制无闭环——300s 后车辆被清理但无重建逻辑

**Why:** 设计文档未调研现有代码就提出方案，导致重复建设和架构不一致风险
**How to apply:** 审查设计方案时，首先检查是否已有相关实现，要求设计基于现有代码做增量改进
