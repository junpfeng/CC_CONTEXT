---
name: 配置表补全与打表
status: completed
---

## 范围
- 修改: freelifeclient/RawTables/icon.xlsx — LegendType_c 表新增行：ID=127, Name=BigWorldNpc, Icon=icon_npc_common, Color=#87CEEB, EdgeDisplay=0（确认 ID 不与现有条目冲突）
- 修改: freelifeclient/RawTables/scene.xlsx — Miami 大世界场景（id=16）补填 pedWaypointFile 字段，值为行人路网文件名
- 修改: freelifeclient/RawTables/NpcCreator.xlsx — 新增 patrolRouteIds（候选巡逻路线 ID 列表）和 patrolSpeedScale（步行速度缩放因子，默认 1.0）字段
- 运行打表工具，确保服务端和客户端配置代码正确生成

## 验证标准
- icon.xlsx 新增条目 ID=127 无冲突
- scene.xlsx Miami 场景 pedWaypointFile 指向正确文件
- NpcCreator.xlsx 新字段有默认值
- 打表成功，服务端 make build 编译通过
- 客户端配置生成代码无编译错误

## 依赖
- 依赖 task-01（需要行人路网文件名确定 pedWaypointFile 值）
