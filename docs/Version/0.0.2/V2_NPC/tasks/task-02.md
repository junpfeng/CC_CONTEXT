---
name: Map 路网按类型过滤查询接口
status: discarded
---

## 范围
- 修改: P1GoServer/servers/scene_server/internal/ecs/res/road_network/map.go — 新增 roadsByType map[RoadNetworkType][]*RoadNetwork 索引字段，Init 时自动构建；新增 FindNearestPointIDByType、FindPathByType、GetPointsByType 三个按类型过滤的查询方法；原有 FindNearestPointID 和 FindPath 行为不变（向后兼容）

## 验证标准
- 服务端 make build 编译通过
- roadsByType 索引在 Init 时从现有 RoadNetwork 列表自动构建
- FindNearestPointIDByType 仅在指定 type 的子路网中查找
- FindPathByType 仅在指定 type 的子路网中执行 A* 寻路
- 原有 FindNearestPointID / FindPath 行为不变（回归安全）
- 如涉及 RoadNetQuerier 接口扩展，确保现有实现编译通过

## 依赖
- 无
