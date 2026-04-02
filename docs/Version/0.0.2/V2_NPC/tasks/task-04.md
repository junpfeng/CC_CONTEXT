---
name: WalkZone 配额计算器
status: discarded
---

## 范围
- 新增: P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/bigworld_walk_zone.go — WalkZoneConfig / ZoneEntry / QuotaResult 数据结构定义；WalkZoneQuotaCalculator 实现（NewWalkZoneQuotaCalculator / Calculate / GetZoneForPos / IsInZone）；loadWalkZoneConfig 从 JSON 加载配置；配额计算逻辑（玩家 AOI 覆盖检测 + densityWeight 归一化分配 + recycleHysteresis 回收控制）

## 验证标准
- 服务端 make build 编译通过
- WalkZoneConfig 可从 npc_zone_quota.json 正确反序列化
- Calculate 方法正确计算各 zone 的 quota/deficit/surplus
- 未被玩家 AOI 覆盖的 zone 配额为 0
- 各 zone 配额不超过 maxNpc 硬上限
- recycleHysteresis 阈值在 surplus 计算中生效

## 依赖
- 无
