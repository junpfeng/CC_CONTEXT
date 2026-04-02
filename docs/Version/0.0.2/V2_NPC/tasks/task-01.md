---
name: 行人路网与巡逻路线数据生成
status: completed
---

## 范围
- 新增: scripts/generate_ped_road.py — 从车辆路网 road_traffic_miami.json 派生行人路网，沿车道法线偏移生成 footwalk 路点，按 K-means 聚类划分 5 个 WalkZone，输出 miami_ped_road.json + zone AABB
- 新增: scripts/generate_patrol_routes.py — 从行人路网自动生成 15-25 条环形巡逻路线（每条 8-15 节点），30% 节点带 duration+behaviorType，输出到 ai_patrol/bigworld/
- 新增: freelifeclient/RawTables/Json/Server/npc_zone_quota.json — WalkZone 配额配置（totalNpcBudget=50, recycleHysteresis=5, 5 个分区）
- 新增: freelifeclient/RawTables/Json/Server/miami_ped_road.json — 行人路网数据（脚本生成产物）
- 新增: freelifeclient/RawTables/Json/Server/ai_patrol/bigworld/*.json — 巡逻路线数据（脚本生成产物）

## 验证标准
- generate_ped_road.py 可重复运行，输出 miami_ped_road.json 格式与 road_point.json 一致
- 所有路点 type=footwalk，坐标在 -4096~4096 范围内
- 至少 5 个 WalkZone 分区，各分区内路网连通
- generate_patrol_routes.py 输出 15-25 条路线 JSON，每条含 walkZone 字段
- npc_zone_quota.json 格式正确，5 个 zone 的 AABB 覆盖主要区域

## 依赖
- 无
