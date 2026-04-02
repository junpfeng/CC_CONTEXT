# 大世界交通系统 GTA5 级复刻 — 设计方案

> 目标：将 GTA5 交通系统一比一复刻到大世界（Miami/Sakura）场景

## 文档索引

| 文档 | 内容 |
|------|------|
| [architecture.md](architecture.md) | 总体架构：系统分层、模块职责、数据流 |
| [road-network.md](road-network.md) | 路网系统：数据格式、加载、寻路、路口检测 |
| [traffic-light.md](traffic-light.md) | 信号灯系统：服务端相位计时、客户端执行、协议 |
| [junction-decision.md](junction-decision.md) | 路口决策：6 态 FSM、停车排队、让行逻辑 |
| [driving-personality.md](driving-personality.md) | 驾驶人格：参数体系、预设、行为调制 |
| [collision-avoidance.md](collision-avoidance.md) | 碰撞闪避：6 态升级链、侧闪、绕行寻路 |
| [lane-change.md](lane-change.md) | 变道系统：决策、执行、车道数据 |
| [density-spawn.md](density-spawn.md) | 密度与生成：动态密度、类型规则、限速区 |
| [implementation-plan.md](implementation-plan.md) | 实施计划：阶段划分、依赖图、任务清单 |

## 背景

### 为什么从小镇转向大世界

小镇（S1Town）场景缺乏关键资源：
- 路网仅 484 节点（大世界 50,523 节点）
- 无信号灯数据（大世界 295 个路口，含 cycle 相位）
- 无多车道标记（大世界 29% 路点有 OtherLanes）
- 道路类型单一（大世界有 road_type 区分主干道/支路）

### 现有基础

大世界交通系统已有 60% 框架：
- **路网数据**：50,523 路点 + 295 路口 + 信号灯相位 + 车道关联
- **协议定义**：DriverPersonality（16 参数）、TrafficLightCommand（8 种）、JunctionCommand（5 种）
- **客户端框架**：DotsCity ECS 交通引擎 + Gley TrafficSystem + VehicleAI 组件体系
- **服务端框架**：交通载具系统 + 刷车规则配置表 + 道路类型配置表

缺失的核心能力：
- 服务端信号灯相位计时与广播
- 路口决策 FSM（客户端）
- 驾驶人格参数实际应用到行为
- 碰撞闪避升级链（侧闪+绕行）
- 变道决策与执行
- 动态密度管理

### GTA5 参考

GTA5 交通系统四层架构：数据层（RoadSpeedZone）→ 决策层（DriverPersonality）→ 智能体（VehicleIntelligence）→ 控制层（CVehPIDController）。本方案以此为蓝本，结合项目现有基础设计。
