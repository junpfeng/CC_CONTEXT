# 文档盘点报告

> 生成时间：2026-03-26 | 文档总数：88 个 .md 文件 + 3 个 temp 数据文件 + 7 个 Version 非 md 文件

## 子目录结构

| 子目录 | 文件数 | 说明 |
|--------|--------|------|
| `design/` | 63 | 设计方案（含 ai/ 子目录树） |
| `knowledge/` | 10 | 工程领域知识 |
| `postmortem/` | 4+INDEX | 经验总结 |
| `reference/` | 1+INDEX | 参考资料 |
| `tools/` | 2 | 工具文档 |
| `temp/` | 3 (json) | 临时数据文件（非文档） |
| `Version/` | 10 md + 7 非 md | 版本工作记录 |

---

## design/ — 设计方案

### design/ai/npc/ (6 文件)

| 文件 | 行数 | 主题 | 关键实体 | 最后修改 | 引用数 |
|------|------|------|---------|---------|--------|
| npc-v2-decision-execution-redesign.md | 910 | V2正交管线需求：4维度决策执行解耦 | OrthogonalPipeline, PlanHandler | 03-10 | 1 (INDEX) |
| npc-v2-decision-execution-redesign-tech-design.md | 772 | 正交管线技术设计+18任务 | PlanExecutor, DimensionSlot | 03-10 | 1 (INDEX) |
| npc-gta5-behavior-implementation.md | 809 | GTA5行为实现（14行为+客户端同步） | GTA行为, 警察追捕 | 03-21 | 1 (INDEX) |
| npc-combat-expansion.md | 435 | 战斗扩展多技能配置 | CombatBtHandler, NpcSkillSet | 03-21 | 1 (INDEX) |
| npc-v2-file-inventory.md | 286 | V2系统完整文件清单 | Proto, Brain, Handler | 03-10 | 2 (INDEX, resource/README) |
| npc-v2-btree-framework.md | 264 | V2独立行为树框架 | BehaviorTree, BtPlanHandler | 03-10 | 1 (INDEX) |

### design/ai/emotion/ (6 文件)

| 文件 | 行数 | 主题 | 关键实体 | 最后修改 | 引用数 |
|------|------|------|---------|---------|--------|
| ped-ai-emotion-server.md | 377 | 路人情绪服务端需求 | EmotionState, moodLevel, LOD | 03-10 | 1 (INDEX) |
| ped-ai-emotion-client.md | 241 | 路人情绪客户端FSM | FleeComp, GawkComp, PhoneComp | 03-10 | 1 (INDEX) |
| ped-ai-emotion-animation-design.md | 244 | 情绪动画表现设计 | 3阶段通话, 动画Key映射 | 03-12 | 1 (INDEX) |
| ped-ai-emotion-tasks.md | 144 | 情绪系统30项任务清单 | 协议4+服务器15+客户端11 | 03-21 | 1 (INDEX) |
| ped-ai-emotion-review.md | 110 | 情绪系统审查报告 | S1-S5严重, G1-G8建议 | 03-21 | 1 (INDEX) |
| ped-ai-emotion-bugfix-design.md | 107 | 情绪Bug修复方案 | trip_fall, pendingSpread | 03-10 | 1 (INDEX) |

### design/ai/schedule/ (14 文件)

| 文件 | 行数 | 主题 | 关键实体 | 最后修改 | 引用数 |
|------|------|------|---------|---------|--------|
| tech-design.md | 876 | 日程系统完整技术架构 | PopSchedule, DaySchedule, Patrol | 03-21 | 1 (INDEX) |
| scenario-p0-design.md | 713 | 场景点P0 GTA风格设计 | ScenarioSystem, SpatialGrid | 03-17 | 2 (INDEX, MEMORY) |
| server.md | 650 | 服务端日程三层架构 | DayScheduleManager, ScheduleEntry | 03-11 | 1 (INDEX) |
| tech-design-review.md | 81 | 审查报告5必须+7推荐 | FieldAccessor, nil防护 | 03-21 | 1 (INDEX) |
| tasks.md | 363 | 26个任务全覆盖清单 | TASK-01至TASK-26 | 03-21 | 1 (INDEX) |
| v2-schedule-config.md | 315 | V2日程独立配置体系 | ScheduleTemplate, V2隔离 | 03-14 | 2 (INDEX, changelog) |
| client.md | 254 | 客户端日程FSM表现层 | PatrolState, ScenarioState | 03-17 | 1 (INDEX) |
| protocol.md | 238 | 协议扩展4枚举+3子消息+5Ntf | NpcScheduleData, NpcPatrolData | 03-17 | 1 (INDEX) |
| schedule-moveto-targetpos-align.md | 159 | MoveTo两段式对齐方案 | MoveToPhase, 路网fallback | 03-16 | 1 (INDEX) |
| scenario-p0-tasks.md | 139 | 场景点P0 12个工作项 | T01-T12 | 03-21 | 2 (INDEX, MEMORY) |
| v2-schedule-tasks.md | 98 | V2日程配置11个任务 | T1-T11 | 03-21 | 1 (INDEX) |
| review-report.md | 83 | Phase6审查FIX-1~FIX-9 | distanceSq改XZ, PatrolHandler | 03-11 | 1 (INDEX) |
| v2-schedule-changelog.md | 74 | V2变更清单14+28+1 | schedule_config.go | 03-14 | 1 (INDEX) |
| v2-schedule-donna-example.md | 65 | Donna旅馆经理V2示例 | templateId=1014, 12段日程 | 03-14 | 0 |

### design/ai/traffic/ (9 文件)

| 文件 | 行数 | 主题 | 关键实体 | 最后修改 | 引用数 |
|------|------|------|---------|---------|--------|
| client.md | 411 | 客户端交通AI实现（⚠️部分已迁移大世界） | JunctionDecisionFSM, PersonalityComp | 03-21 | 3 (INDEX, system-design, big_world) |
| road-network.md | 317 | S1Town路网数据与启用步骤 | WaypointGraph, GleyNav | 03-17 | 2 (INDEX, town-vehicle) |
| review-report.md | 298 | 审查报告6严重+6中等+4轻微 | S1Town场景, LOD, 路口决策 | 03-17 | 1 (INDEX) |
| system-design.md | 257 | 早期通用交通设计（⚠️大世界已另案） | TrafficLightMgr, VehicleAIComp | 03-21 | 4 (INDEX, protocol, client, road-network) ⚠️高引用 |
| protocol.md | 247 | 交通AI协议与配置表 | TrafficLightCommand, CfgJunction | 03-21 | 2 (INDEX, system-design) |
| town-vehicle-client-drive.md | 201 | S1Town车辆Catmull-Rom优化 | TownTrafficMover, 闭环路径 | 03-18 | 1 (INDEX) |
| design-town-traffic-enhancement.md | 100 | 小镇交通增强方案 | 碰撞避让, AI LOD | 03-21 | 1 (INDEX) |
| minimap-traffic-vehicle-icon-legend.md | 57 | 小地图车辆图标图例 | MapTrafficVehicleLegend | 03-21 | 1 (INDEX) |
| verification-todo.md | 39 | S1Town启用验证清单 | LoadScene.cs, 配置表 | 03-14 | 3 (INDEX, road-network, client) |

### design/ai/big_world_traffic/ (13 文件)

| 文件 | 行数 | 主题 | 关键实体 | 最后修改 | 引用数 |
|------|------|------|---------|---------|--------|
| design-gta5-refactor.md | 405 | GTA5式重构总设计 | 四层架构, 6阶段 | 03-20 | 1 (INDEX) |
| design-junction-signal-broadcast.md | 282 | 路口信号灯广播方案 | 信号灯, AOI广播 | 03-21 | 1 (INDEX) |
| density-spawn.md | 180 | 动态密度生成与回收 | 密度系统, 类型规则 | 03-19 | 1 (INDEX) |
| junction-decision.md | 173 | 路口决策6态FSM | 停车排队, 让行 | 03-19 | 1 (INDEX) |
| road-network.md | 167 | 路网+A*寻路 | 50K路点, RoadGraph | 03-19 | 1 (INDEX) |
| implementation-plan.md | 167 | 实施计划阶段划分 | 6阶段依赖图 | 03-21 | 1 (INDEX) |
| lane-change.md | 162 | 变道系统 | OtherLanes | 03-19 | 1 (INDEX) |
| driving-personality.md | 162 | 驾驶人格5种预设 | 17参数体系 | 03-19 | 1 (INDEX) |
| collision-avoidance.md | 160 | 碰撞避让6态升级链 | 蠕行, 停车 | 03-19 | 1 (INDEX) |
| architecture.md | 154 | 四层架构设计 | 系统分层, 数据流 | 03-19 | 1 (INDEX) |
| traffic-light.md | 143 | 信号灯系统设计 | 相位计时, 协议 | 03-19 | 1 (INDEX) |
| todo-gta5-refactor.md | 94 | 功能完成度总结(7完成+3待完善) | 大世界, GTA5 | 03-21 | 1 (INDEX) |
| tasks-gta5-refactor.md | 76 | 重构任务清单 | 任务清单 | 03-21 | 1 (INDEX) |
| README.md | 47 | 总览索引 | 9文档链接 | 03-19 | 3 (INDEX, traffic/client, traffic/system-design) |

### design/ai/resource/ (5 文件)

| 文件 | 行数 | 主题 | 关键实体 | 最后修改 | 引用数 |
|------|------|------|---------|---------|--------|
| client-assets.md | 97 | 客户端美术资源(Prefab/动画/音频) | 270动画片段, NpcAnimation.xlsx | 03-11 | 1 (INDEX) |
| protocol.md | 73 | Proto协议定义入口 | old_proto/, NpcState枚举 | 03-11 | 1 (INDEX) |
| excel-tables.md | 65 | Excel配置表清单 | npc.xlsx, TownNpc | 03-11 | 2 (INDEX, client-assets) |
| server-config.md | 64 | 服务端配置目录 | TOML, AI JSON, NavMesh | 03-11 | 1 (INDEX) |
| README.md | 14 | 资源索引 | 4文档链接 | 03-21 | 1 (INDEX) |

### design/ai/scenario/ (2 文件)

| 文件 | 行数 | 主题 | 关键实体 | 最后修改 | 引用数 |
|------|------|------|---------|---------|--------|
| scenario-orthogonal-integration.md | 416 | ⚠️未实施 — 场景点正交管线集成 | ScenarioHandler, Brain配置 | 03-21 | 1 (INDEX) |
| scenario-orthogonal-tasks.md | 188 | ⚠️未实施 — 场景点集成任务清单 | 13项任务 | 03-21 | 1 (INDEX) |

### design/ai/misc/ (3 文件)

| 文件 | 行数 | 主题 | 关键实体 | 最后修改 | 引用数 |
|------|------|------|---------|---------|--------|
| map-npc-chase-v2.md | 353 | 追击体验优化V2 | F1-F4功能 | 03-17 | 1 (INDEX) |
| map-npc-chase.md | 289 | 大地图NPC追击 | NavMesh路点, PlayerAutoMoveComp | 03-17 | 1 (INDEX) |
| minimap-npc-tracking.md | 246 | 小地图NPC实时追踪 | MapLegendControl, 池化复用 | 03-17 | 1 (INDEX) |

### design/ai/animal/ (7 文件)

| 文件 | 行数 | 主题 | 关键实体 | 最后修改 | 引用数 |
|------|------|------|---------|---------|--------|
| server.md | 461 | 动物服务端AI行为 | AnimalIdleHandler, OrthogonalPipeline | 03-23 | 2 (INDEX, technical_design) |
| client.md | 390 | 动物客户端表现FSM | AnimalController, AnimalFsmComp | 03-23 | 2 (INDEX, technical_design) |
| technical_design.md | 274 | 动物技术总体设计 | 生成/销毁事务, AI LOD | 03-23 | 0 |
| protocol.md | 244 | 动物协议设计 | AnimalType, AnimalState | 03-23 | 2 (INDEX, technical_design) |
| bigworld_animal_completion.md | 109 | 大世界遗留任务方案 | BtTickSystem, 背包喂食 | 03-22 | 0 |
| review_2026_03_23.md | 70 | 动物系统审查(2严重+4建议) | BtTickSystem, 模块路径 | 03-23 | 0 |
| task_list.md | 68 | 任务完成清单+验收 | 27完成+5遗留已解决 | 03-24 | 0 |

### design/ 根 (2 文件)

| 文件 | 行数 | 主题 | 关键实体 | 最后修改 | 引用数 |
|------|------|------|---------|---------|--------|
| INDEX.md | 111 | 设计方案总索引 | 全部设计文档链接 | 03-21 | 2 (README, .claude/INDEX) |
| remove-server-traffic-bigworld.md | 133 | 移除大世界服务器交通 | GTA5TrafficSystem废弃 | 03-23 | 0 |

---

## knowledge/ — 工程领域知识 (10 文件)

| 文件 | 行数 | 主题 | 关键实体 | 最后修改 | 引用数 |
|------|------|------|---------|---------|--------|
| p1goserver-npc-framework.md | 536 | 服务端NPC AI框架 | GSS Brain, 行为树, 日程 | 03-10 | 2 (INDEX, freelifeclient-npc) |
| client-vehicle.md | 461 | 客户端载具物理/AI | WheelCollider, Seat, FSM | 03-10 | 2 (INDEX, server-vehicle) |
| p1goserver-gateway.md | 362 | Gateway网关架构 | Proxy, RPC, Token | 03-03 | 2 (INDEX, P1GoServer/CLAUDE.md) |
| error-patterns.md | 339 | 错误模式库15个EP | Redis重连, 动画参数 | 03-26 | 2 (INDEX, dev-debug skill) |
| p1goserver-login.md | 340 | 登录验证流程 | Firebase, TapTap OAuth | 03-03 | 1 (INDEX) |
| p1goserver-protocol.md | 322 | 自定义RPC协议 | Varint, ModuleID | 03-03 | 2 (INDEX, P1GoServer/CLAUDE.md) |
| freelifeclient-npc.md | 322 | 客户端NPC双系统 | TownNpc, SakuraNpc, FSM | 03-08 | 1 (INDEX) |
| server-vehicle.md | 268 | 服务端载具ECS | 座位/门/喇叭, 权限 | 03-10 | 2 (INDEX, client-vehicle) |
| bigworld-traffic.md | 248 | 大世界交通系统 | TrafficRoadGraph, A*, DrivingAI | 03-21 | 1 (INDEX) |
| debug-guide.md | 68 | 调试指南 | MLog, Unity日志, CrashSight | 03-10 | 3 (INDEX, dev-debug skill×2) ⚠️高引用 |
| INDEX.md | 24 | 知识文档索引 | 10文档链接 | 03-20 | 2 (README, .claude/INDEX) |

---

## postmortem/ — 经验总结 (5 文件)

| 文件 | 行数 | 主题 | 关键实体 | 最后修改 | 引用数 |
|------|------|------|---------|---------|--------|
| docs-review-2026-03-19.md | 214 | 日程系统文档审查14问题 | 配置路径, 数据结构 | 03-17 | 1 (INDEX) |
| npc-move-animation-bugfix.md | 121 | NPC动画Bug四层修复 | FSM映射, StateId | 03-16 | 1 (INDEX) |
| postmortem-v2-npc-roadnet-init-order.md | 84 | V2路网初始化时序Bug | roadNetMgr nil | 03-14 | 1 (INDEX) |
| review-cross-project-deps.md | 73 | 跨工程依赖闭环Review | 协议/配置/编译流 | 03-10 | 1 (INDEX) |
| INDEX.md | 10 | 经验总结索引 | 4文档链接 | 03-21 | 2 (README, .claude/INDEX) |

---

## reference/ — 参考资料 (2 文件)

| 文件 | 行数 | 主题 | 关键实体 | 最后修改 | 引用数 |
|------|------|------|---------|---------|--------|
| research-traffic-system-comparison.md | 291 | 交通系统技术对比 | GTA5, Miami, S1Town | 03-19 | 1 (INDEX) |
| INDEX.md | 42 | 参考资料索引 | GTA5逆向文档映射 | 03-19 | 3 (README, .claude/INDEX, MEMORY) ⚠️高引用 |

---

## tools/ — 工具文档 (2 文件)

| 文件 | 行数 | 主题 | 关键实体 | 最后修改 | 引用数 |
|------|------|------|---------|---------|--------|
| watchdog-scripts.md | 119 | 监控与自动化脚本 | 崩溃恢复, MCP断连 | 03-17 | 1 (CLAUDE.md) |
| server-ps1.md | 38 | 微服务管理脚本 | 9微服务, 启停顺序 | 03-10 | 2 (CLAUDE.md×2) |

---

## temp/ — 临时数据 (3 文件, 非文档)

| 文件 | 大小 | 说明 |
|------|------|------|
| new_traffic_routes.json | 113KB | 交通路线JSON |
| temp_augmented.json | 21KB | 增强数据 |
| temp_routes.json | 26KB | 临时路线 |

---

## Version/ — 版本工作记录 (10 md + 7 非 md)

| 文件 | 行数 | 主题 | 引用数 |
|------|------|------|--------|
| auto-work-log.md | 17 | 自动化工作启动日志 | 0 |
| plan-review-report.md | 63 | 功能规划设计评审 | 0 |
| plan-iteration-log.md | 17 | 规划8轮迭代记录 | 0 |
| develop-log.md | 44 | Task-01开发日志 | 0 |
| develop-iteration-log-task-01.md | 5 | Task-01迭代总结 | 0 |
| tasks/README.md | 24 | 4任务拆分清单 | 0 |
| tasks/task-01~04.md | 19-28 | 各任务详细说明 | 0 |

非 md 文件：.metrics.jsonl, classification.txt, feature.json, plan.json, .auto-work-log.md.swp, results.tsv, dashboard.txt

---

## 高引用文档（≥3次）

| 文档 | 引用数 | 引用方 | 变更风险 |
|------|--------|--------|---------|
| docs/design/ai/traffic/system-design.md | 4 | INDEX, protocol, client, road-network | ⚠️高 |
| docs/knowledge/debug-guide.md | 3 | INDEX, dev-debug skill×2 | ⚠️高 |
| docs/reference/INDEX.md | 3 | README, .claude/INDEX, MEMORY | ⚠️高 |
| docs/design/ai/big_world_traffic/README.md | 3 | INDEX, traffic/client, traffic/system-design | ⚠️高 |
| docs/design/ai/traffic/verification-todo.md | 3 | INDEX, road-network, client | ⚠️高 |
| docs/design/ai/traffic/client.md | 3 | INDEX, system-design, big_world | 中 |

---

## 文档总行数统计

- design/: ~12,200 行
- knowledge/: ~3,290 行
- postmortem/: ~502 行
- reference/: ~333 行
- tools/: ~157 行
- Version/: ~217 行
- **总计: ~16,700 行**
