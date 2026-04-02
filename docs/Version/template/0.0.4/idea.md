# 大世界 NPC V2 移动方案升级

## 做什么

将大世界 NPC 的移动系统从 P0 占位方案（`BigWorldDefaultPatrolHandler` 随机游荡）升级为正式的 V2 管线驱动移动，修复 spawn Y 偏低、路径节点 Y 错误、走路速度不对齐等已知缺陷，使大世界 NPC 的移动质量对齐小镇 V2 NPC。

## 涉及端

server（主要）+ client（速度参数对齐，无逻辑变更）

## 触发方式

- 自动触发：NPC 生成后由 BtTickSystem 驱动 V2 正交管线 → locomotion 维度决策 → navigation 维度执行
- 无需玩家操作，NPC 自主行为

## 预期行为

正常流程：
1. NPC 生成时 `BigWorldNpcSpawner.spawnNpcAt` 对 spawn 坐标 Y 做 RaycastGroundY 修正，确保 NPC 出生在地面上方
2. BtTickSystem 每帧 tick → locomotion 维度：
   - 无日程/巡逻数据时：执行修订后的 `BigWorldDefaultPatrolHandler`（修复 ResetWritableFields 契约、正确游荡）
   - 有巡逻路线数据（`PatrolRouteId > 0`）时：切换到 `PatrolHandler` 沿路线移动
3. navigation 维度 `NavigateBtHandler` 执行 A* 寻路，对所有路径节点（包括中间节点）做 RaycastGroundY 修正，确保路径在地面以上
4. `NpcMoveSystem` 沿修正后的路径推进坐标，客户端收到位置更新，NPC 在地面上正常行走

异常/边界情况：
- RaycastGroundY 失败时：降级为 SphereCast → lastValidY 兜底，超过 30 帧仍无有效 Y 则 despawn
- A* 路网找不到路径时：降级为直线路径（SetEntityDirectPath），避免 NPC 永久静止
- spawn 点附近无路网覆盖：使用 spawn 坐标直接生成，走路时依赖 navigation handler Y 修正

## 不做什么

- 不新增 NPC AI 行为类型（情绪/对话/战斗等，属于其他特性）
- 不修改客户端动画逻辑（动画播放由位置差值自动驱动，无需改）
- 不新增网络协议（复用现有 MoveControl / Transform 同步）
- 不实现大世界 NPC 日程系统（Schedule 数据配置属于内容工作，超出本期范围）
- 不修改小镇 V2 NPC 逻辑

## 参考

- 小镇 V2 管线：`v2_pipeline_defaults.go` 的 `townDimensionConfigs()`——schedule/patrol/scenario handler 注册方式
- 当前大世界管线：`v2_pipeline_defaults.go` 的 `bigworldDimensionConfigs()`
- `BigWorldDefaultPatrolHandler`（`bigworld_default_patrol.go`）——已有 Fix A-D，本期在此基础上继续优化
- `bigworld_navigation_handler.go` 的 `correctTargetY`——路径终点 Y 修正已有实现，需扩展到中间节点
- 小镇 `bigworld_npc_spawner.go` 的 `spawnNpcAt`——spawn Y 修正在此处添加
- `feedback_bigworld_y_offset`：路网 Y 不可信，必须从 Y=200 Raycast Grounds 层修正
- `feedback_roadnet_path_gap`：A* 路径终点≠实际目标，追加目标点防止死循环

## 优先级

| 优先级 | 内容 | 说明 |
|--------|------|------|
| P0 | spawn Y Raycast 修正 | NPC 出生在地面以上，解决插地问题 |
| P0 | A* 路径中间节点 Y 修正 | NPC 沿地面路径移动，解决地下行走问题 |
| P0 | 走路速度对齐（服务端 1.4 → 1.2 或客户端 1.2 → 1.4） | 消除动画与移速视觉不同步 |
| P1 | `BigWorldDefaultPatrolHandler` 游荡半径/停留时间配置化 | 当前硬编码 60m/3-8s，改为可配置 |
| P1 | 路网稀疏区域降级策略优化 | A* 失败时直线路径的 Y 也需修正 |

## 约束

- 性能：路径节点 Y 修正需缓存，不能每帧每节点都做 Raycast（高频路径上有 20-50 个节点，全量修正会有 CPU 峰值）
- 兼容：不破坏小镇 V2 NPC 移动逻辑，`townDimensionConfigs` 保持不变
- 协议：复用现有 `MoveControlProto` + `TransformProto`，不新增字段
- 路网：大世界路网 A* 已有 50K 路点/295 路口（`reference_bigworld_road_files`），直接复用
