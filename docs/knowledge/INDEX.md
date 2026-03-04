# knowledge/ 索引

> 系统原理与架构概览。

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| `architecture-login-network-sync.md` | 5 大系统：登录认证流程、网络层（proxy/路由）、同步机制（snapshot/AOI）、Player 鉴权（token/session/权限/反作弊）、Redis key 设计 | 登录、网络、同步、AOI、鉴权、Redis |
| `architecture-ecs-场景框架.md` | ECS 核心接口（Entity/Component/Resource/System）、Scene 生命周期、ComponentMap 优化、89 种组件、43 种 Resource、System 初始化时序、三级脏标记 | ECS、Scene、Entity、Component、Resource、System、脏标记 |
| `architecture-微服务通信.md` | 20 个服务器职责、RPC Session（Call/Push/Ack）、Proxy 星形路由、RegisterClient 服务发现、App Runnable 生命周期、Gateway 双网络、消息协议格式 | 微服务、RPC、Proxy、Gateway、服务发现、消息路由 |
| `architecture-ai-决策与行为树.md` | DecisionSystem 1 秒决策、Executor Plan 调度、BtRunner 核心方法、BtContext + Blackboard 三阶段、四层节点类型、Service/Decorator/Abort 机制、复合树模式、JSON 树格式 | AI、决策、行为树、Brain、Plan、Blackboard、Abort |
| `architecture-npc-生命周期.md` | NPC 创建两层模式、Town/Sakura/MainWorld 差异、Sensor→Feature→Decision 数据流、NpcMoveComp 双寻路、日程系统、警察警戒值状态机、视野系统 | NPC、创建、Sensor、Feature、日程、警察、视野 |
| `architecture-伤害管线.md` | Shot→Hit→Explosion→DealDamage 流水线、CheckManager 反作弊、GAS 属性系统、HateComp 双向仇恨追踪、事件广播 SnapshotMgr、伤害免疫规则 | 伤害、射击、命中、爆炸、反作弊、GAS、仇恨 |
| `architecture-载具系统.md` | 载具 Entity 组件组成、SpawnTrafficVehicle、上下车流程、DriveVehicle 高频更新、TouchedStamp 自动消失、车门/喇叭管理、场景类型限制 | 载具、上下车、驾驶、交通、自动消失 |
| `architecture-小镇经济与任务.md` | TownMgr 等级经验、TradeManager 订单状态机、TaskManager 事件驱动观察者、OrderDropSystem 定时投放、产品/垃圾/供货商/公共容器子系统、Resource 协作关系 | 小镇、交易、订单、任务、事件驱动、产品、供货商 |
| `architecture-物理与导航.md` | PhysX CGO 集成（Linux 存根/Windows 完整）、NavMesh（Recast/Detour + DetourCrowd）、路网 A* 寻路、Grid 空间划分、NPC 双寻路引擎、三层导航体系 | 物理、PhysX、NavMesh、寻路、A*、Grid、导航 |
| `architecture-ai-决策与行为树.md` | Brain（1 秒决策）→ Executor（Plan 调度）→ BtRunner（逐帧 Tick）→ 节点树，完整 NPC 智能行为系统 | DecisionSystem、Executor、BtRunner、BtTickSystem、行为树节点、Service/Decorator、组合树模式 |
| `architecture-ecs-场景框架.md` | Scene Server 核心架构：Entity/Component/Resource/System 接口、ComponentMap、89 种 Component、43 种 Resource | ECS、Entity、Component、Resource、System、ComponentMap、场景框架 |
| `architecture-npc-生命周期.md` | NPC 完整生命周期：实体创建、组件挂载、Sensor/Feature 管线、Schedule 系统、Police 系统、视觉系统 | NPC、生命周期、Sensor、Feature、Schedule、Police、Vision |
| `architecture-伤害管线.md` | Shot → Hit → Explosion → Damage 完整管线、CheckManager 反作弊校验、GAS 系统集成、仇恨追踪 | 射击、命中、爆炸、伤害、反作弊、GAS、仇恨 |
| `architecture-小镇经济与任务.md` | 小镇等级经验、交易订单流程、任务事件驱动、订单部署、产品管理、垃圾刷新、供应商欠债、公共容器 | 小镇、经济、任务、交易、订单、产品、供应商 |
| `architecture-微服务通信.md` | 20 个微服务拓扑、RPC 通信框架、服务注册发现、消息路由全链路 | 微服务、RPC、服务发现、消息路由、拓扑 |
| `architecture-载具系统.md` | 载具上下车、座位管理、交通载具自动消失、车门状态、NPC 驾驶 | 载具、上下车、座位、车门、交通载具、NPC驾驶 |
