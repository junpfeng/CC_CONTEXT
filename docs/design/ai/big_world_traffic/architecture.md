# 总体架构

## 系统分层

对标 GTA5 四层架构，结合项目现有基础：

```
┌─────────────────────────────────────────────────────────────┐
│                      数据层 (Data)                           │
│  路网图 · 路口数据 · 信号灯配置 · 限速区 · 驾驶人格表        │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                    决策层 (Decision)                         │
│  路口决策FSM · 碰撞闪避FSM · 变道决策 · 巡航目标选择         │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                   控制层 (Control)                           │
│  转向控制 · 油门/制动 · 变道执行 · 侧闪偏移                  │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                   执行层 (Execution)                         │
│  DotsCity ECS 物理驱动 · AI LOD · 距离剔除 · 贴地修正        │
└─────────────────────────────────────────────────────────────┘
```

## 服务端 vs 客户端职责

| 职责 | 服务端 | 客户端 |
|------|--------|--------|
| 信号灯相位计时 | ✅ 权威源 | 接收执行 |
| 路口指令下发 | ✅ 计算+广播 | 接收执行 |
| 驾驶人格分配 | ✅ 生成时分配 | 接收应用 |
| 载具生成/回收 | ✅ 权威 | 请求+表现 |
| 限速区配置 | ✅ 配置表 | 运行时查询 |
| 路径跟随 | — | ✅ 本地计算 |
| 碰撞躲避 | — | ✅ 本地计算 |
| 变道决策 | — | ✅ 本地计算 |
| AI LOD | — | ✅ 本地管理 |
| 物理控制 | — | ✅ DotsCity |

## 模块依赖图

```
                    RoadNetwork (路网数据)
                   /     |      \       \
                  /      |       \       \
     TrafficLight   JunctionFSM  Pathfinder  SpeedZone
     (信号灯)      (路口决策)    (寻路)      (限速)
           \          |         /         /
            \         |        /         /
             VehicleIntelligence (车辆智能体)
             /        |        \
            /         |         \
     AvoidanceFSM  LaneChange  PersonalityDriver
     (碰撞闪避)    (变道)      (人格驱动)
            \         |         /
             \        |        /
           VehicleController (控制层)
                      |
              DotsCity ECS (物理执行)
```

## 与现有系统的关系

### 复用（不改动）

| 模块 | 说明 |
|------|------|
| DotsCity ECS 物理引擎 | 车辆物理模拟、碰撞检测 |
| Gley TrafficSystem 编辑器 | 道路/路口编辑工具 |
| WaypointGraph 寻路层 | CustomWaypoint 邻接表、Octree 索引 |
| VehicleAI 组件框架 | CarAI、PathPlanning、Movement 组件 |
| 现有协议定义 | DriverPersonality、TrafficLightCommand、JunctionCommand |

### 增强（在现有基础上扩展）

| 模块 | 改动 |
|------|------|
| DrivingAI | 集成路口决策 FSM + 人格参数驱动 |
| NormalStyle | 应用人格参数到行为控制 |
| TrafficLightManager | 接入服务端信号灯状态 |
| traffic_vehicle_system.go | 增加信号灯相位计时 + 路口指令计算 |

### 新增

| 模块 | 说明 |
|------|------|
| JunctionDecisionFSM | 6 态路口决策状态机（客户端） |
| AvoidanceUpgradeChain | 碰撞闪避 6 态升级链（客户端） |
| LaneChangeController | 变道决策+执行（客户端） |
| TrafficLightPhaseTimer | 信号灯相位计时器（服务端） |
| DensityManager | 动态密度管理（服务端+客户端） |

## 数据流

### 车辆生命周期

```
服务端                              客户端
  │                                   │
  │ 1. 密度管理器决定生成             │
  │    → 选择路网节点+车型+人格       │
  │                                   │
  │ ──── VehicleSpawnNtf ──────────→ │
  │      (位置/车型/人格参数)         │
  │                                   │ 2. 创建 GameObject
  │                                   │    → 初始化 VehicleAI
  │                                   │    → 应用人格参数
  │                                   │    → 开始巡航
  │                                   │
  │ ──── TrafficLightStateNtf ─────→ │ 3. 信号灯状态更新
  │      (路口ID/相位/剩余时间)       │    → 查询当前路口
  │                                   │    → 路口决策 FSM
  │                                   │
  │ ←── VehicleApproachJunctionReq ── │ 4. 接近路口上报
  │                                   │
  │ ──── JunctionCommandNtf ────────→ │ 5. 路口指令
  │      (GO/WAIT/GIVEWAY)            │    → 执行停/行
  │                                   │
  │ ←── VehicleLeaveJunctionReq ───── │ 6. 离开路口上报
  │                                   │
  │ 7. 超出 AOI / 密度回收           │
  │ ──── VehicleDestroyNtf ─────────→ │ 8. 销毁
```

### 信号灯时序

```
服务端 TrafficLightPhaseTimer:
  Green(25s) → Amber(3s) → Red(25s) → 循环
  每次切换 → AOI 内广播 TrafficLightStateNtf

客户端 TrafficLightManager:
  收到 Ntf → 更新路口信号灯状态
  → 车辆查询当前路口信号 → 路口决策 FSM 响应
```

## 阶段划分

按 GTA5 复刻路线图，分 6 阶段实施。每阶段独立可交付：

| 阶段 | 内容 | 优先级 | 依赖 |
|------|------|--------|------|
| 1 | 路网寻路 + 转向控制 | P0 | — |
| 2 | 信号灯 + 路口决策 | P0 | 阶段1 |
| 3 | 驾驶人格 | P1 | 阶段1+2 |
| 4 | 碰撞闪避升级 | P1 | 阶段1 |
| 5 | 变道系统 | P1 | 阶段1+3 |
| 6 | 密度与生成管理 | P2 | 阶段1 |

> 阶段 1 已在小镇实现原型（TownRoadGraph + TownPathfinder + TownVehicleDriver），大世界需适配 50K 路点规模和 DotsCity 集成。
