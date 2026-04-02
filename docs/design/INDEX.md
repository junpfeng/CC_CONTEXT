# design/ 索引

> 快速定位设计文档。按主题分组，关键词辅助搜索。

## AI 系统（`ai/`）

### NPC V2 架构（`ai/npc/`）

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| [`ai/npc/npc-v2-decision-execution-redesign.md`](ai/npc/npc-v2-decision-execution-redesign.md) | V2正交管线需求：4维度(Engagement/Expression/Locomotion/Navigation)、全局守卫、PlanHandler、MoveTarget优先级仲裁、InteractionLock | NPC, 正交管线, OrthogonalPipeline, PlanHandler, MoveTarget |
| [`ai/npc/npc-v2-decision-execution-redesign-tech-design.md`](ai/npc/npc-v2-decision-execution-redesign-tech-design.md) | V2正交管线技术设计+任务清单：数据结构、Pipeline代码骨架、DimensionSlot、18任务(T01-T18) | NPC, 正交管线, 技术设计, 任务清单 |
| [`ai/npc/npc-v2-btree-framework.md`](ai/npc/npc-v2-btree-framework.md) | V2行为树框架：节点体系、BtPlanHandler适配器、与PlanExecutor集成 | NPC, 行为树, BtPlanHandler |
| [`ai/npc/npc-v2-file-inventory.md`](ai/npc/npc-v2-file-inventory.md) | V2系统完整文件清单：协议、服务端AI、客户端表现、配置 | NPC, 文件清单, 代码索引 |
| [`ai/npc/npc-combat-expansion.md`](ai/npc/npc-combat-expansion.md) | 战斗扩展完整方案：需求(P0-P2)+配置表设计+接口契约+任务清单(T01-T18)+审查结论 | NPC, 战斗, 需求, 技术设计, 任务清单 |
| [`ai/npc/npc-gta5-behavior-implementation.md`](ai/npc/npc-gta5-behavior-implementation.md) | GTA5行为移植完整方案：14行为实现、V2管线集成、客户端同步 + 附录(GTA5参考/审查报告) | NPC, GTA5, 战斗, 逃跑, 调查, 审查 |

### 场景点系统（`ai/scenario/`）

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| [`ai/scenario/scenario-orthogonal-integration.md`](ai/scenario/scenario-orthogonal-integration.md) | ⚠️ **未实施** — 场景点集成正交管线设计方案 | NPC, 场景点, Scenario, 正交管线 |
| [`ai/scenario/scenario-orthogonal-tasks.md`](ai/scenario/scenario-orthogonal-tasks.md) | ⚠️ **未实施** — 场景点集成任务清单 | NPC, 场景点, 任务清单 |

### NPC 资源文件索引（`ai/resource/`）

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| [`ai/resource/README.md`](ai/resource/README.md) | NPC资源文件总索引 | NPC, 资源, 索引 |
| [`ai/resource/server-config.md`](ai/resource/server-config.md) | 服务端配置：TOML/JSON/NavMesh | NPC, 服务端, 配置 |
| [`ai/resource/excel-tables.md`](ai/resource/excel-tables.md) | Excel配置表源文件 | NPC, 配置表, Excel |
| [`ai/resource/client-assets.md`](ai/resource/client-assets.md) | 客户端美术资源：Prefab/动画/音频 | NPC, Prefab, 动画 |
| [`ai/resource/protocol.md`](ai/resource/protocol.md) | Proto协议定义 | NPC, 协议, Proto |

### 情绪系统（`ai/emotion/`）

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| [`ai/emotion/ped-ai-emotion-server.md`](ai/emotion/ped-ai-emotion-server.md) | 服务端情绪系统：指数衰减、事件触发、LOD分级、传播 | 情绪, EmotionSystem |
| [`ai/emotion/ped-ai-emotion-client.md`](ai/emotion/ped-ai-emotion-client.md) | 客户端情绪表现：状态同步、动画/表情 | 情绪, 客户端, 动画 |
| [`ai/emotion/ped-ai-emotion-animation-design.md`](ai/emotion/ped-ai-emotion-animation-design.md) | 情绪动画设计 | 情绪, 动画 |
| [`ai/emotion/ped-ai-emotion-bugfix-design.md`](ai/emotion/ped-ai-emotion-bugfix-design.md) | 情绪系统 bugfix 方案 | 情绪, bugfix |
| [`ai/emotion/ped-ai-emotion-review.md`](ai/emotion/ped-ai-emotion-review.md) | 情绪系统审查报告 | 情绪, 审查 |
| [`ai/emotion/ped-ai-emotion-tasks.md`](ai/emotion/ped-ai-emotion-tasks.md) | 情绪系统任务清单 | 情绪, 任务清单 |

### 日程系统（`ai/schedule/`）

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| [`ai/schedule/tech-design.md`](ai/schedule/tech-design.md) | 日程系统技术设计 | 日程, Schedule |
| [`ai/schedule/server.md`](ai/schedule/server.md) | 服务端日程 | 日程, 服务端 |
| [`ai/schedule/client.md`](ai/schedule/client.md) | 客户端日程 | 日程, 客户端 |
| [`ai/schedule/protocol.md`](ai/schedule/protocol.md) | 日程协议 | 日程, 协议 |
| [`ai/schedule/tasks.md`](ai/schedule/tasks.md) | 日程任务清单 | 日程, 任务清单 |
| [`ai/schedule/scenario-p0-design.md`](ai/schedule/scenario-p0-design.md) | 场景点 P0 设计（日程关联） | 场景点, P0 |
| [`ai/schedule/scenario-p0-tasks.md`](ai/schedule/scenario-p0-tasks.md) | 场景点 P0 任务清单 | 场景点, 任务清单 |
| [`ai/schedule/v2-schedule-*.md`](ai/schedule/) | V2 日程配置/示例/变更日志 | V2, 日程 |
| [`ai/schedule/schedule-moveto-targetpos-align.md`](ai/schedule/schedule-moveto-targetpos-align.md) | MoveTo 目标位置对齐 | 日程, MoveTo |
| [`ai/schedule/tech-design-review.md`](ai/schedule/tech-design-review.md) | 日程技术设计审查 | 日程, 审查 |
| [`ai/schedule/review-report.md`](ai/schedule/review-report.md) | 日程审查报告 | 日程, 审查 |

### 小镇交通系统（`ai/traffic/`）— S1Town 遗留，仅供小镇场景参考

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| [`ai/traffic/system-design.md`](ai/traffic/system-design.md) | 交通AI总设计方案（S1Town 轻量方案） | 交通, 小镇 |
| [`ai/traffic/design-town-traffic-enhancement.md`](ai/traffic/design-town-traffic-enhancement.md) | 小镇交通基础增强：碰撞避让、速度差异化、AI LOD | 小镇, 碰撞避让 |
| [`ai/traffic/minimap-traffic-vehicle-icon-legend.md`](ai/traffic/minimap-traffic-vehicle-icon-legend.md) | 小地图交通车辆图标图例 | 小地图, 图标 |
| [`ai/traffic/protocol.md`](ai/traffic/protocol.md) | 交通AI协议（基础消息） | 交通, 协议 |
| [`ai/traffic/client.md`](ai/traffic/client.md) | 交通AI客户端（Gley 插件架构） | 交通, 客户端 |
| [`ai/traffic/road-network.md`](ai/traffic/road-network.md) | 路网数据 | 路网, 路点 |
| [`ai/traffic/town-vehicle-client-drive.md`](ai/traffic/town-vehicle-client-drive.md) | 小镇载具客户端直驱 | 载具, 客户端 |
| [`ai/traffic/review-report.md`](ai/traffic/review-report.md) | 交通系统审查报告 | 交通, 审查 |
| [`ai/traffic/verification-todo.md`](ai/traffic/verification-todo.md) | 验证待办 | 交通, 验证 |
| [`ai/traffic/assets/`](ai/traffic/assets/) | 小镇路网可视化图片/脚本/数据 | 小镇, 路网, 图片 |

### 大世界交通系统（`ai/big_world_traffic/`）

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| [`ai/big_world_traffic/README.md`](ai/big_world_traffic/README.md) | 总览索引 | 大世界, 交通 |
| [`ai/big_world_traffic/todo-gta5-refactor.md`](ai/big_world_traffic/todo-gta5-refactor.md) | **功能完成度总结**（7项已完成 + 3项待完善） | 大世界, 完成度 |
| [`ai/big_world_traffic/design-gta5-refactor.md`](ai/big_world_traffic/design-gta5-refactor.md) | GTA5 式重构总设计 | 大世界, GTA5 |
| [`ai/big_world_traffic/architecture.md`](ai/big_world_traffic/architecture.md) | 四层架构设计 | 架构, 四层 |
| [`ai/big_world_traffic/road-network.md`](ai/big_world_traffic/road-network.md) | 路网 + A* 寻路 | 路网, A*, 50K路点 |
| [`ai/big_world_traffic/junction-decision.md`](ai/big_world_traffic/junction-decision.md) | 路口决策 FSM（6态） | 路口, FSM, 信号灯 |
| [`ai/big_world_traffic/traffic-light.md`](ai/big_world_traffic/traffic-light.md) | 信号灯系统设计 | 信号灯, 相位 |
| [`ai/big_world_traffic/design-junction-signal-broadcast.md`](ai/big_world_traffic/design-junction-signal-broadcast.md) | 路口信号灯广播方案 | 信号灯, 广播 |
| [`ai/big_world_traffic/collision-avoidance.md`](ai/big_world_traffic/collision-avoidance.md) | 碰撞避让 6 态升级链 | 避让, 蠕行, 停车 |
| [`ai/big_world_traffic/driving-personality.md`](ai/big_world_traffic/driving-personality.md) | 驾驶人格（5种预设） | 人格, 参数化 |
| [`ai/big_world_traffic/lane-change.md`](ai/big_world_traffic/lane-change.md) | 变道设计 | 变道, OtherLanes |
| [`ai/big_world_traffic/density-spawn.md`](ai/big_world_traffic/density-spawn.md) | 动态密度生成 | 密度, 生成, 回收 |
| [`ai/big_world_traffic/implementation-plan.md`](ai/big_world_traffic/implementation-plan.md) | 实施计划 | 计划, 阶段 |
| [`ai/big_world_traffic/tasks-gta5-refactor.md`](ai/big_world_traffic/tasks-gta5-refactor.md) | 重构任务清单 | 任务清单 |
| [`ai/big_world_traffic/assets/`](ai/big_world_traffic/assets/) | 大世界路网可视化/图片 | 路网, 图片 |

### 动物系统（`ai/animal/`）

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| [`ai/animal/protocol.md`](ai/animal/protocol.md) | 📋 设计阶段 — 动物系统协议 | 动物, 协议 |
| [`ai/animal/server.md`](ai/animal/server.md) | 📋 设计阶段 — 动物系统服务端：AI行为/感知/战斗 | 动物, 服务端 |
| [`ai/animal/client.md`](ai/animal/client.md) | 📋 设计阶段 — 动物系统客户端：FSM/动画/Boid | 动物, 客户端 |

### 杂项（`ai/misc/`）

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| [`ai/misc/minimap-npc-tracking.md`](ai/misc/minimap-npc-tracking.md) | 小地图NPC实时追踪 | 小地图, NPC追踪 |
| [`ai/misc/map-npc-chase.md`](ai/misc/map-npc-chase.md) | 大地图点击NPC自动寻路追击 | 寻路, 追击 |
| [`ai/misc/map-npc-chase-v2.md`](ai/misc/map-npc-chase-v2.md) | 追击 V2 | 寻路, 追击 |

## 工作流

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| [`design-ddrp-recursive-dependency-resolution.md`](design-ddrp-recursive-dependency-resolution.md) | DDRP 递归依赖解决协议：new-feature 发现缺失依赖时递归 spawn 子 new-feature 实现，文件通信、无深度限制、引擎零修改 | DDRP, 依赖解决, new-feature, 递归, auto-work |
