# Scene Server 详细实现分析

本文档详细分析 `servers/scene_server` 的完整实现，包括 ECS 架构、AI 系统、AOI 优化等核心内容。

## 一、目录结构

```
servers/scene_server/
├── cmd/                          # 启动入口
│   ├── main.go                   # 程序入口
│   ├── config.go                 # 配置加载
│   └── initialize.go             # 初始化逻辑
└── internal/
    ├── common/                   # 核心接口定义
    │   ├── ecs.go                # ECS 核心接口
    │   ├── com.go                # 组件基类
    │   ├── com_type.go           # 80+ 组件类型常量
    │   ├── scene.go              # Scene 接口
    │   ├── resource_type.go      # 资源类型常量
    │   └── ai/                   # AI 系统
    │       ├── bt/               # 行为树
    │       ├── decision/         # 决策系统（FSM、GOAP、GSS）
    │       ├── fsm/              # 有限状态机
    │       └── value/            # AI 数据值
    ├── ecs/
    │   ├── entity/               # 实体实现
    │   │   ├── entity.go         # 基础实体类
    │   │   ├── player.go         # 玩家实体
    │   │   └── factory.go        # 实体工厂
    │   ├── com/                  # 40+ 组件实现
    │   │   ├── cplayer/          # 玩家相关组件
    │   │   ├── cgas/             # GAS 能力系统组件
    │   │   ├── cbackpack/        # 背包组件
    │   │   ├── cbehavior/        # 行为树组件
    │   │   └── ...               # 更多组件
    │   ├── system/               # 20+ 系统实现
    │   │   ├── system.go         # 系统基类
    │   │   ├── net_update/       # 网络同步系统
    │   │   ├── decision/         # AI 决策系统
    │   │   ├── sensor/           # 传感器系统
    │   │   ├── npc/              # NPC 移动系统
    │   │   ├── vision/           # 视野系统
    │   │   ├── police/           # 警察系统
    │   │   └── ...               # 更多系统
    │   ├── scene/                # 场景核心
    │   │   ├── scene.go          # 场景实现（~670行）
    │   │   ├── scene_impl.go     # Tick 逻辑（~590行）
    │   │   ├── scene_mgr.go      # 场景管理器
    │   │   ├── player_func.go    # 玩家相关函数
    │   │   └── aoi/              # AOI 系统
    │   └── res/                  # 15+ 资源实现
    │       ├── grid.go           # 网格管理器
    │       ├── player.go         # 玩家管理器
    │       ├── navmesh/          # 导航网格
    │       ├── town/             # 小镇相关资源
    │       └── time_mgr/         # 时间管理器
    ├── service/                  # RPC 服务实现
    └── net_func/                 # 网络功能处理
        ├── player/               # 玩家操作处理
        ├── npc/                  # NPC 操作处理
        └── object/               # 场景对象处理
```

**代码规模：**
- 总共 **323 个 Go 文件**
- 40+ 个具体组件实现
- 20+ 个系统实现
- 15+ 个资源实现

---

## 二、启动流程

### 2.1 程序入口

```go
// cmd/main.go
func main() {
    cfg, err := LoadConfig(*configPath)  // 加载配置
    app := initialize(cfg)                // 初始化
    app.Run()                             // 运行
}
```

### 2.2 初始化过程

```
initialize(cfg)
├─ 设置全局配置
├─ 初始化日志系统
├─ 加载所有配置（NPC、场景、任务等）
├─ 加载 GAS 配置
├─ 加载 AI Decision 配置
├─ 创建数据库连接（dbEntry）
├─ 创建场景管理器（SceneMgr）
├─ 创建 RPC 服务处理器
├─ 创建 App 实例并注册服务
└─ 返回 App 实例
```

### 2.3 场景初始化

```
Scene.init()
├─ 创建全局实体（GlobalEntity）
├─ 初始化资源（Resources）
│   ├─ PlayerManager       # 玩家管理
│   ├─ GridMgr            # 地格/AOI 管理
│   ├─ SnapshotMgr        # 快照管理
│   ├─ TimeMgr            # 时间管理
│   ├─ SubTransformMgr    # 子变换管理
│   ├─ InitObjectManager  # 初始化对象
│   ├─ SpawnPointManager  # 出生点
│   └─ NavMeshMgr         # 导航网格
├─ 根据场景类型初始化
│   ├─ 小镇场景（TownSceneInfo）
│   │   ├─ 加载小镇数据
│   │   ├─ 初始化小镇资源
│   │   ├─ 加载导航网格
│   │   ├─ 添加 Sensor 系统
│   │   ├─ 添加 AI Decision 系统
│   │   ├─ 添加 Vision 系统
│   │   ├─ 添加 Police 系统
│   │   └─ 添加 BeingWanted 系统
│   └─ 樱校场景（SakuraSceneInfo）
│       └─ 加载樱校数据
├─ 初始化 FSM（有限状态机）
├─ 初始化所有系统（Systems）
└─ 初始化 NPC 和场景对象
```

---

## 三、ECS 架构实现

### 3.1 Entity（实体）

```go
type entity struct {
    identity common.EntityIdentity  // { ID, EntityType }
    scene    common.Scene           // 所属场景
    coms     []common.Component     // 组件列表
    handler  []common.Handler       // 事件处理器
}

// 实体类型
const (
    EntityType_Base    // 基础实体
    EntityType_Player  // 玩家实体
    EntityType_Npc     // NPC 实体
    EntityType_Vehicle // 载具实体
    EntityType_Object  // 物体实体
)

// 关键方法
GetComponent(comType ComponentType) Component  // O(n) 遍历查找
AddComponent(com Component) bool               // 添加到实体和场景
RemoveComponent(comType ComponentType) bool    // 移除组件
ComList() []Component                          // 获取所有组件
```

**实体工厂：**
```go
type factory struct {
    idIdx uint64  // 单调递增的实体ID生成器
}

func (f *factory) NewEntity(scene Scene) Entity {
    // 为每个新实体分配唯一递增的ID
}
```

### 3.2 Component（组件）

**组件基类：**
```go
type ComponentBase struct {
    CompAndResBase      // 继承：scene、dirtyFlag
    compType ComponentType
    identity *CompIdentity  // 指向实体身份
}

// 脏标志机制（2 bit）
dirtyFlagSync = 1 << 0  // 需要同步给客户端
dirtyFlagSave = 1 << 1  // 需要保存到数据库

// 关键方法
SetSync() / ClearSync() / IsNeedSync()
SetSave() / ClearSave() / IsNeedSave()
InitIdentify(entity Entity)  // 添加到实体后初始化
Type() ComponentType
CompIdentity() *CompIdentity
```

**组件类型常量（80+）：**

| 类别 | 组件类型 | 说明 |
|------|---------|------|
| **基础组件** | | |
| | ComponentType_Transform | 位置和旋转 |
| | ComponentType_Movement | 移动数据 |
| | ComponentType_BaseStatus | 基本状态（死亡等）|
| | ComponentType_Gas | GAS 能力系统 |
| | ComponentType_Physics | 物理碰撞 |
| | ComponentType_Trigger | 触发器 |
| **玩家组件** | | |
| | ComponentType_PlayerBase | 玩家基础（ID、等级等）|
| | ComponentType_Backpack | 背包 |
| | ComponentType_Equip | 装备 |
| | ComponentType_PersonStatus | 人物状态 |
| | ComponentType_Team | 队伍 |
| | ComponentType_Camp | 阵营 |
| | ComponentType_Statistics | 统计（等级、经验、身价等）|
| | ComponentType_PlayerShop | 商店 |
| | ComponentType_Residence | 住宅 |
| **NPC 组件** | | |
| | ComponentType_NpcBase | NPC 基础 |
| | ComponentType_BehaviorTree | 行为树 |
| | ComponentType_NpcSchedule | 日程 |
| | ComponentType_NpcPolice | 警察属性 |
| | ComponentType_Vision | 视野 |
| | ComponentType_AIDecision | AI 决策 |
| **小镇组件** | | |
| | ComponentType_TownNpc | 小镇 NPC |
| | ComponentType_TownInventory | 小镇道具栏 |
| **物体组件** | | |
| | ComponentType_ObjInteract | 交互点 |
| | ComponentType_ObjectBase | 物体基础 |
| | ComponentType_MovableDoor | 可移动门 |
| | ComponentType_Furniture | 家具 |

**主要组件实现：**

| 组件类型 | 文件位置 | 功能说明 |
|---------|--------|---------|
| PlayerBaseComp | cplayer/player_base.go | 玩家基础信息 |
| BackpackComp | cbackpack/backpack.go | 背包管理 |
| TransformComp | com/transform.go | 位置变换 |
| PersonStatusComp | com/person_status.go | 人物状态 |
| GasComp | cgas/gas.go | 能力系统 |
| NpcBaseComp | cnpc/npc_base.go | NPC 基础 |
| TownNpcComp | ctown_npc/town_npc.go | 小镇 NPC |

### 3.3 Scene（场景）

**Scene 数据结构：**
```go
type scene struct {
    unique           uint64              // 场景唯一ID
    frame            uint64              // 当前帧数
    sceneType        common.ISceneType   // 场景类型
    serverUnique     uint32              // 服务器唯一ID

    // 实体和组件
    globalEntity     common.Entity       // 全局实体
    entities         []common.Entity     // 所有实体列表
    componentMap     *ComponentMap       // 按类型优化的组件存储

    // 系统
    globalSyses      []common.System     // 全局系统
    syses            []common.System     // 场景系统

    // 资源
    resources        []common.Resource   // 场景资源

    // 其他
    fsm              fsm.Fsm             // 场景状态机
    sceneCfg         *config.CfgSceneInfo // 场景配置
}
```

**Scene 接口：**
```go
type Scene interface {
    // 场景信息
    Unique() uint64
    Frame() uint64
    SceneType() ISceneType
    Config() *CfgSceneInfo

    // 实体管理
    NewEntity() Entity
    AddComponent(com Component, entity Entity) bool
    GetComponent(comType ComponentType, entityID uint64) Component
    RemoveComponent(com Component) bool
    GetEntity(entityID uint64) Entity
    EntityList() []Entity
    ComList(comType ComponentType) []Component
    EntityListByComponent(comTypes ...ComponentType) []Entity

    // 系统管理
    AddSystem(sys System) error
    GetSystem(sysType SystemType) System
    AddGlobalSystem(sys System) error
    GetGlobalSystem(sysType GlobalSystemType) System

    // 资源管理
    AddResource(res Resource) bool
    GetResource(resType ResourceType) Resource

    // Tick 和生命周期
    OnFixedUpdate()
    OnBeforeCreate(entities []Entity)
    OnAfterCreate(entities []Entity)
    OnBeforeDestroy(entities []Entity)
    OnAfterDestroy(entities []Entity)
}
```

### 3.4 System（系统）

**系统接口：**
```go
type System interface {
    Type() SystemType
    Scene() Scene

    OnBeforeTick()      // 每帧开始前调用
    Update()            // 每帧逻辑执行
    OnAfterTick()       // 每帧结束后调用
    OnMsg(msg any) error
    OnRpc(msg any) (any, error)
    OnDestroy()         // 销毁时调用
}
```

**系统类型常量（20+）：**

| 系统类型 | 更新频率 | 职责 |
|---------|---------|------|
| SystemType_NetUpdate | 每帧 | 网络同步 |
| SystemType_AIDecision | 1秒 | AI 决策 |
| SystemType_SensorFeature | 500ms | 传感器特征采集 |
| SystemType_NpcMove | 每帧 | NPC 移动 |
| SystemType_Vision | 每帧 | 视野检测 |
| SystemType_NpcPolice | 每帧 | 警察系统 |
| SystemType_BeingWanted | 每帧 | 通缉状态 |
| SystemType_TownUpdate | 每帧 | 小镇逻辑 |
| SystemType_TownNpcUpdate | 每帧 | 小镇 NPC 更新 |
| SystemType_TaskUpdate | 每帧 | 任务更新 |
| SystemType_Save | 定时 | 数据保存 |
| SystemType_RoleInfoSave | 定时 | 角色保存 |
| SystemType_SubTransform | 每帧 | 子变换 |
| SystemType_AiBt | 每帧 | AI 行为树 |

### 3.5 Resource（资源）

场景级别的共享数据：

| 资源类型 | 说明 |
|---------|------|
| PlayerManager | 玩家管理 |
| GridMgr | 网格/AOI |
| NavMeshMgr | 导航网格 |
| TimeMgr | 游戏时间 |
| SnapshotMgr | 快照管理 |
| SpawnPointManager | 出生点 |
| Physx | 物理引擎 |

---

## 四、场景 Tick 循环

```go
// 每 33ms 执行一次（约 30 FPS）
const TickInterval = 33 * time.Millisecond

func (s *scene) tick() {
    s.frame++  // 帧数递增

    // 1. 前置处理
    for _, sys := range s.syses {
        if sys == nil { continue }
        sys.OnBeforeTick()
    }

    // 2. 逻辑更新
    for _, sys := range s.syses {
        if sys == nil { continue }
        sys.Update()
    }

    // 3. 后置处理
    for _, sys := range s.syses {
        if sys == nil { continue }
        sys.OnAfterTick()
    }

    // 4. 数据保存
    s.doSaveData()
}
```

---

## 五、场景管理

### 5.1 场景创建

```go
func (mgr *sceneMgr) NewScene(unique uint64, req *proto.CreateSceneCommandReq) (common.Scene, error) {
    // 1. 检查场景是否已存在
    // 2. 加载场景类型
    // 3. 创建 Scene 实例
    // 4. 设置场景管理器引用
    // 5. 初始化场景（加载资源、系统等）
    // 6. 启动场景 Worker（绑定到 Tick 循环）
    // 7. 通知 Manager 场景已创建
}
```

### 5.2 场景销毁

```go
func (s *scene) AfterLoop() error {
    // 1. 保存场景数据到数据库
    s.Save()

    // 2. 通知 Manager 移除场景
    s.managerClient.RemoveScene(s.Unique())
    s.manager.RemoveScene(s.Unique())
}
```

### 5.3 玩家进入场景

```
1. 客户端发送进场请求
2. Scene 接收 EnterSceneCommand
3. 调用 player.PlayerEnterScene()
   ├─ 创建玩家实体（Entity）
   ├─ 添加玩家相关组件（20+）
   │   ├─ PlayerBaseComp         # 玩家基础信息
   │   ├─ TransformComp          # 位置和旋转
   │   ├─ BackpackComp           # 背包
   │   ├─ PropertyComp           # 属性
   │   ├─ PersonStatusComp       # 人物状态
   │   └─ ...
   ├─ 将玩家添加到场景（addEntity）
   ├─ 更新 PlayerManager
   └─ 返回进场响应（EnterSceneRes）
       ├─ 玩家信息（UserDataProto）
       ├─ 场景信息
       ├─ 时间信息
       └─ 任务信息
4. 客户端加载完成后同步其他玩家和 NPC
```

### 5.4 玩家离开场景

```
1. 客户端发送离开请求或掉线
2. Scene 接收 LeaveSceneCommand 或 OfflineSceneCommand
3. 调用 player.PlayerLeaveScene()
   ├─ 保存玩家数据（持久化）
   ├─ 移除玩家实体（RemoveEntity）
   │   ├─ 移除所有关联组件
   │   ├─ 从网格管理器移除
   │   └─ 清空实体列表
   ├─ 更新 PlayerManager
   ├─ 同步到其他玩家
   └─ 回收资源
```

---

## 六、AOI（兴趣区域）系统

### 6.1 网格管理器

```go
type GridMgr struct {
    gridCountX int      // X 方向网格数
    gridCountY int      // Y 方向网格数
    cellSizeX float32   // 网格大小
    cellSizeY float32

    grids     []Grid                         // 所有网格
    entityMap map[uint64]*GridEntityInfo     // 实体位置映射
}

type Grid struct {
    id        int
    entities  map[uint64]*GridEntityInfo    // 当前在网格内的实体
    leaveMap  map[uint64]*GridEntityInfo    // 即将离开
    enterMap  map[uint64]*GridEntityInfo    // 即将进入
    removeMap map[uint64]*GridEntityInfo    // 即将移除
}
```

### 6.2 九宫格查询

```go
func (mgr *GridMgr) GetNineGridListByCentral(centralGridId int) map[int]struct{} {
    // 获取中心网格周围 8 个网格 + 中心网格 = 9 个网格
    // 用于 AOI（Area of Interest）查询
    // 返回可见范围内的所有实体
}

// 时间复杂度：O(1) - 直接计算
// 空间复杂度：O(1) - 最多 9 个网格
```

**AOI 优化效果：**
- 将场景分割成网格（默认 128 * 128 大小）
- 每个玩家只关注所在网格和周围 8 个网格
- 1000 个 NPC 的场景，每个玩家只需关注 10-20 个
- 减少 95% 的同步消息

### 6.3 ComponentMap 数据结构

```go
type ComponentMap struct {
    arrays []*ComponentArray  // 按 ComponentType 索引
}

type ComponentArray struct {
    components []Component      // 连续内存数组（高缓存命中）
    entityMap  map[uint64]int   // entityID -> 数组索引
}

// 操作复杂度
Add(com)           // O(1) 追加到数组末尾
Remove(entityId)   // O(1) 交换删除法
Get(entityId)      // O(1) Map 查找
GetByIndex(i)      // O(1) 数组访问
Slice()            // O(1) 返回数组引用
```

**设计优点：**
1. **O(1) 复杂度** - 增删查都是常数时间
2. **缓存友好** - 连续内存布局
3. **批量操作** - 可以一次性获取同类型的所有组件
4. **避免碎片** - 交换删除法保持内存连续

---

## 七、AI 系统

### 7.1 AI 决策方式

| 方式 | 位置 | 适用场景 |
|------|------|---------|
| FSM | `ai/fsm/` | 简单状态切换 |
| 行为树 | `ai/bt/` | 复杂行为序列 |
| GSS Brain | `ai/decision/gss_brain/` | 传感器驱动决策 |
| GOAP | `ai/decision/goap/` | 目标驱动规划 |

### 7.2 行为树系统

```
位置: internal/common/ai/bt/
├── bt_node.go        # 行为树节点基类
├── node_control.go   # 控制节点（选择器、序列等）
├── node_decorator.go # 装饰节点（条件、重试等）
└── node_leaf.go      # 叶子节点（动作）
```

### 7.3 有限状态机

```go
// 位置: internal/common/ai/fsm/state_machine.go

type StateMachine struct {
    currentState *State
    states       map[string]*State
    owner        interface{}
    enabled      bool
}

type State struct {
    Name     string
    OnEnter  func()          // 进入状态时
    OnUpdate func() State    // 每帧更新
    OnExit   func()          // 离开状态时
}

// 方法
SetCurrentState(name string)      // 切换状态
Trigger(event string) bool        // 触发事件
Update()                          // 每帧更新
```

### 7.4 GSS Brain 系统

```
位置: internal/common/ai/decision/gss_brain/
├── config/           # 配置加载和管理
├── condition/        # 条件判断
├── feature/          # 特征值系统
├── sensor/           # 传感器
├── transition/       # 状态转移
└── fsm/              # GSS 脑的状态机
```

**GSS 决策流程：**
1. Sensor 采集特征值（Feature）
2. 根据 Transition 条件和 Feature 值确定是否需要转移
3. 如果条件满足，执行转移到新的 Plan
4. 每个 Plan 定义一系列的 Action（动作）

### 7.5 GOAP 系统

```
位置: internal/common/ai/decision/goap/
├── planner.go        # GOAP 规划器
├── action.go         # 可执行动作
├── worldstate.go     # 世界状态
└── node.go           # 规划树节点
```

**GOAP 特点：**
- 目标驱动
- 自动规划动作序列
- 适合复杂 AI 决策

### 7.6 传感器系统

```go
type SensorFeatureSystem struct {
    eventSensorFeature    *EventSensorFeature     // 事件感知
    scheduleSensorFeature *ScheduleSensorFeature  // 日程感知
    distanceSensor        *DistanceSensor         // 距离感知
    visionSensor          *VisionSensor           // 视觉感知
    stateSensor           *StateSensor            // 状态感知
    miscSensor            *MiscSensor             // 杂项感知
}

const UpdateInterval = 500 * time.Millisecond  // 500ms 更新一次
```

**传感器特征：**

| 传感器 | 采集内容 |
|-------|---------|
| EventSensorFeature | 触发事件的特征值 |
| ScheduleSensorFeature | NPC 日程信息、当前时间 |
| DistanceSensor | 与周围实体的距离 |
| VisionSensor | 视野内的实体 |
| StateSensor | NPC 自身状态、其他 NPC 状态 |
| MiscSensor | 自定义特征 |

### 7.7 配置驱动的 AI

```json
{
    "name": "npc_name",
    "init_plan": "idle",
    "plan_interval": 1000,
    "plans": [
        {
            "name": "idle",
            "actions": [...]
        },
        {
            "name": "walk",
            "actions": [...]
        }
    ],
    "transitions": [
        {
            "from": "idle",
            "to": "walk",
            "index": 1,
            "conditions": [...]
        }
    ],
    "sensors": {
        "event_sensors": [...],
        "schedule_sensors": [...],
        "distance_sensors": [...],
        "vision_sensors": [...]
    }
}
```

---

## 八、物理和碰撞检测

### 8.1 物理引擎

```go
type Physx struct {
    common.ResourceBase
    physx *physics.Physx
}

func NewPhysx() (*Physx, error) {
    physx := physics.NewPhysx()
    if err := physx.Init(); err != nil {
        return nil, err
    }
    return &Physx{physx: physx}, nil
}
```

### 8.2 导航网格

```go
type NavMeshMgr struct {
    ResourceBase
    // 管理多个导航网格
}

// 加载导航网格
navMeshMgr.LoadMap("town", navmeshResPath, config)

// 用于 NPC 路径规划和移动
```

---

## 九、RPC 接口

### 9.1 玩家相关

| 方法 | 说明 |
|------|------|
| MoveReq | 玩家移动 |
| Teleport | 传送 |
| TeleportFinish | 传送完成 |
| TeleportToNearestRebornPoint | 传送到复活点 |
| Reborn | 复活 |
| Suicide | 自杀 |
| StartInteractToNpc | 开始与 NPC 交互 |
| StopInteractToNpc | 停止交互 |
| InteractWithNpc | 与 NPC 交互 |

### 9.2 AI 和 NPC 控制

| 方法 | 说明 |
|------|------|
| ControlAiActionNew | 控制 AI 动作 |
| UpdateBehaviorTreeBlackboard | 更新行为树黑板 |
| AiVehicleMove | AI 驾驶 |
| NpcPhoneCallFinish | NPC 电话结束 |
| GetNpcScheduleInfo | 获取 NPC 日程信息 |

### 9.3 载具相关

| 方法 | 说明 |
|------|------|
| OnVehicle | 上车 |
| OffVehicle | 下车 |
| DriveVehicle | 驾驶 |
| SwitchVehicleSeat | 切换座位 |
| OpenVehicleDoor | 打开车门 |
| CloseVehicleDoor | 关闭车门 |
| LockVehicleDoor | 锁定车门 |
| UnlockVehicleDoor | 解锁车门 |

### 9.4 背包和物品

| 方法 | 说明 |
|------|------|
| UseProps | 使用道具 |
| DropItem | 丢弃物品 |
| TransferItem | 转移物品 |
| LockBackpackCell | 锁定背包格子 |
| UnLockBackpackCellReq | 解锁背包格子 |

### 9.5 犯罪和警察系统

| 方法 | 说明 |
|------|------|
| AddCrimeWantedScore | 增加通缉分数 |
| SetCrimeWantedLevel | 设置通缉等级 |
| TeleportToPoliceStation | 传送到警察局 |

### 9.6 小镇特定

| 方法 | 说明 |
|------|------|
| AcceptMission | 接受任务 |
| MissionDisplayFinish | 任务展示完成 |
| ZoneBeforeStart | 任务区开始前 |
| ZoneInviteResult | 任务区邀请结果 |
| GetShopGoodList | 获取商店商品列表 |
| PurchaseGood | 购买商品 |

### 9.7 场景对象

| 方法 | 说明 |
|------|------|
| AddSceneObject | 添加场景对象 |
| RemoveSceneObject | 移除场景对象 |
| MoveObjectPosition | 移动对象位置 |
| OccupyFurnitureInteractPoint | 占用家具交互点 |
| ReleaseFurnitureInteractPoint | 释放家具交互点 |

---

## 十、性能优化策略

| 策略 | 说明 |
|------|------|
| **Tick 分帧** | AI 决策 1 秒更新，传感器 500ms 更新，避免每帧都执行 |
| **NPC 批处理** | 每帧最多处理 100 个 NPC，避免单帧时间过长 |
| **九宫格 AOI** | 只同步周围 9 格内的实体，减少 95% 同步消息 |
| **脏标记** | 只同步/保存有变化的数据，减少网络和数据库操作 |
| **ComponentMap** | 连续内存布局，O(1) 查找，高缓存命中率 |
| **NPC 缓存** | 缓存 NPC 列表，避免每帧重新遍历所有实体 |
| **交换删除** | 保持数组连续性，避免内存碎片 |

---

## 十一、关键源码文件

| 功能 | 文件路径 |
|------|---------|
| 场景核心 | `internal/ecs/scene/scene.go` |
| Tick 循环 | `internal/ecs/scene/scene_impl.go` |
| 场景管理 | `internal/ecs/scene/scene_mgr.go` |
| 玩家函数 | `internal/ecs/scene/player_func.go` |
| 实体工厂 | `internal/ecs/entity/factory.go` |
| 实体基类 | `internal/ecs/entity/entity.go` |
| 组件基类 | `internal/common/com.go` |
| 组件类型 | `internal/common/com_type.go` |
| 系统基类 | `internal/ecs/system/system.go` |
| AOI 网格 | `internal/ecs/res/grid.go` |
| 玩家管理 | `internal/ecs/res/player.go` |
| AI 决策系统 | `internal/ecs/system/decision/` |
| 传感器系统 | `internal/ecs/system/sensor/` |
| 视野系统 | `internal/ecs/system/vision/` |
| 网络同步 | `internal/ecs/system/net_update/` |

---

## 十二、扩展指南

### 12.1 添加新组件

```go
// 1. 在 com_type.go 添加类型常量
const ComponentType_MyNew ComponentType = xxx

// 2. 创建组件文件
type MyNewComp struct {
    common.ComponentBase
    // 数据字段
}

// 3. 实现 Component 接口
func (c *MyNewComp) Type() common.ComponentType {
    return common.ComponentType_MyNew
}

// 4. 在需要的地方添加到实体
entity.AddComponent(myNewComp)
```

### 12.2 添加新系统

```go
// 1. 在 system_type.go 添加类型常量
const SystemType_MyNew SystemType = xxx

// 2. 创建系统文件
type MyNewSystem struct {
    *system.SystemBase
}

// 3. 实现 System 接口
func (s *MyNewSystem) Type() common.SystemType {
    return common.SystemType_MyNew
}

func (s *MyNewSystem) Update() {
    // 每帧逻辑
}

// 4. 在场景初始化时添加
scene.AddSystem(myNewSystem)
```

### 12.3 添加新 AI 行为

只需配置 JSON 文件，无需修改代码：

```json
{
    "name": "new_npc",
    "init_plan": "idle",
    "plans": [
        { "name": "idle", "actions": [...] },
        { "name": "patrol", "actions": [...] }
    ],
    "transitions": [
        { "from": "idle", "to": "patrol", "conditions": [...] }
    ],
    "sensors": { ... }
}
```

---

## 总结

Scene Server 是一个**生产级别**的 ECS 游戏场景服务器：

1. **ECS 架构** - 清晰的数据与逻辑分离，易于扩展
2. **高效数据结构** - ComponentMap、Grid 等优化设计
3. **完善 AI 系统** - 多种决策方式（FSM、GSS、GOAP、行为树）
4. **实时网络同步** - AOI 九宫格优化，脏数据标记
5. **模块化设计** - 组件、系统、资源三层架构
6. **性能优化** - Tick 分帧、缓存策略、九宫格等多项优化
7. **配置驱动** - JSON 配置 AI，无需修改代码
8. **完备 RPC** - 100+ 个方法，覆盖游戏各功能
