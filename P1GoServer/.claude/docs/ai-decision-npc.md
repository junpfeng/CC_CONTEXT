# AI 决策系统与 NPC 详解

本文档详细分析 scene_server 中的 AI 决策系统和 NPC 实现。

## 一、AI 决策系统整体架构

### 1.1 分层架构设计

```
应用层（ECS 系统）
    ↓
决策执行层（Executor）
    ↓
决策代理层（Agent - GSS Brain / NDU Brain）
    ↓
特征/传感器层（Feature / Sensor）
    ↓
数据存储层（Value Manager）
```

### 1.2 核心接口

**文件位置**：`servers/scene_server/internal/common/ai/decision/types.go`

| 接口 | 职责 |
|------|------|
| Agent | 决策代理，维护决策状态和生成计划 |
| Brain | 具体决策模型（GSS Brain、NDU Brain）|
| Executor | 执行由 Agent 生成的计划 |
| Decision | 全局决策管理器，创建和管理所有 Agent |

### 1.3 决策流程

```
Agent.Tick()
    ↓
Brain.Tick()
    ↓
状态机转移（Init → WaitConsume → WaitCreateNotify）
    ↓
计划创建/获取
    ↓
Executor.OnPlanCreated() 执行计划
    ↓
Task 执行（Entry/Main/Exit/Transition）
```

---

## 二、GSS Brain（Goal-Sensor-State Brain）

GSS Brain 是主要的 AI 决策模型，基于目标-传感器-状态的设计模式。

### 2.1 核心结构

**文件位置**：`servers/scene_server/internal/common/ai/decision/agent/gss.go`

```go
type gssBrain struct {
    id             uint32                  // NPC 实体 ID
    feature        gss.Feature             // 世界知识存储
    config         *config.Config          // 决策配置
    cfgMgr         *config.ConfigMgr       // 配置管理
    curPlan        *decision.Plan          // 当前执行计划
    curTransitions []config.Transition     // 当前可转移的状态
    step           DecisionStep            // 决策步骤
    conditionMgr   *condition.ConditionMgr // 条件管理器
    fsm            *fsm.GssBrainFSM        // 有限状态机
}
```

**决策步骤**：
| 步骤 | 值 | 说明 |
|------|---|------|
| DecisionStepInit | 1 | 初始化，创建初始计划 |
| DecisionStepWaitConsume | 2 | 等待计划消费 |
| DecisionStepWaitCreateNotify | 3 | 等待创建通知 |

### 2.2 Config 配置系统

**文件位置**：`servers/scene_server/internal/common/ai/decision/gss_brain/config/config.go`

```go
type Config struct {
    Name           string                   // 配置名称（唯一标识）
    InitPlan       string                   // 初始计划名称
    PlanInterval   int64                    // 做计划间隔（毫秒）
    Plans          []Plan                   // 所有计划列表
    Transitions    []Transition             // 所有状态转移
    Sensors        Sensors                  // 传感器配置
    Features       map[string]interface{}   // 特征初始值
    transitionsMap map[string][]*Transition // 优化查询：from → [Transitions]
}

type Plan struct {
    Name      string  // 计划名称
    EntryTask string  // 进入任务
    ExitTask  string  // 退出任务
    MainTask  string  // 主任务
}

type Transition struct {
    Name           string     // 转移名称
    From           string     // 来源计划
    To             string     // 目标计划
    Priority       int64      // 优先级（高优先级优先）
    Probability    int64      // 概率权重
    Condition      Condition  // 转移条件
    TransitionTask string     // 转移任务
    FromPlan       *Plan      // 来源计划指针
    ToPlan         *Plan      // 目标计划指针
}
```

**配置加载流程**：
1. `Init(configPath)` - 初始化配置路径
2. `CfgMgr.Parse(path)` - 扫描目录下所有 JSON 文件
3. `parseFile(path)` - 解析单个配置文件
4. `checkIfValid()` - 验证嵌套条件深度（最多 5 层）
5. `prepareForUse()` - 建立优化的查询索引

### 2.3 Condition（条件）系统

**文件位置**：`servers/scene_server/internal/common/ai/decision/gss_brain/config/transition.go`

```go
type Condition struct {
    Op         LogicOp          // "and" 或 "or"
    Conditions []ConditionItem  // 条件项列表
    OpEnum     LogicOpEnum      // 枚举值（优化）
}

type ConditionItem struct {
    Key           string      // Feature 键名
    Op            CompareOp   // 比较操作符
    Value         any         // 比较值
    OpEnum        CompareOpEnum
    NestCondition *Condition  // 嵌套条件（支持树形）
}
```

**支持的比较操作符**：

| 操作符 | 说明 |
|-------|------|
| eq | 相等 |
| ne | 不相等 |
| gt | 大于 |
| ge | 大于等于 |
| lt | 小于 |
| le | 小于等于 |

**条件执行**（`gss_brain/condition/mgr.go`）：
```go
type ConditionMgr struct {
    conditions map[config.LogicOpEnum]ConditionExcutor
}

// 支持递归条件树
func (m *ConditionMgr) ExecuteConditionTree(condition *Condition, feat Feature) (CondExecResult, error) {
    // AND：所有子条件都为 Success 才为 Success
    // OR：任何子条件为 Success 就为 Success
}
```

### 2.4 Feature（特征/世界知识）系统

**文件位置**：`servers/scene_server/internal/common/ai/decision/gss_brain/feature/feature.go`

```go
type Feature interface {
    Init(values *value.ValueMgr, config *config.Config) error
    GetValue(key string) (value.Value, bool)
    UpdateValue(key string, v any) (value.Value, error)
    GetAllValues() map[string]value.Value
}

type feature struct {
    values *value.ValueMgr  // 值管理器
}
```

**初始化流程**：
1. 从 `Config.Features` 读取所有特征定义
2. 使用 `CheckValueType()` 确定值类型
3. 通过 `ValueMgr.NewValue()` 创建对应类型的值对象

### 2.5 Sensor（传感器）配置

**文件位置**：`servers/scene_server/internal/common/ai/decision/gss_brain/config/sensor.go`

```go
type Sensors struct {
    View     *ViewSensor     // 视野传感器
    Event    *EventSensor    // 事件传感器
    Distance *DistanceSensor // 距离传感器
}

type ViewSensor struct {
    ViewSightHeight         float64 // 视野高度
    ViewSightDistance       float64 // 视野距离
    ViewSightHorizotalAngle float64 // 水平视角
    ViewSightVerticalAngle  float64 // 垂直视角
    UpdateRate              int     // 更新率
}
```

### 2.6 FSM（有限状态机）

**文件位置**：`servers/scene_server/internal/common/ai/decision/fsm/gss_brain_fsm.go`

**三个核心状态**：

| 状态 | 进入 | 更新 | 退出 |
|------|------|------|------|
| InitState | 无 | 创建初始计划，转到 WaitConsume | 无 |
| WaitConsumeState | 无 | 保持，等待外部消费计划 | 无 |
| WaitCreateNotifyState | 无 | 创建新计划，转到 WaitConsume | 无 |

**状态转移图**：
```
Init → WaitConsume → WaitCreateNotify → WaitConsume → ...
            ↓               ↓
        GetNextPlan     创建新计划
```

### 2.7 计划生成流程

**初始计划创建**（`createInitialPlan()`）：
1. 获取初始计划配置
2. 打包 Entry/Exit/Main 任务
3. 返回 Plan 对象并转移到 WaitConsume 状态

**新计划创建**（`createNewPlanImpl()`）：
1. `getPassedTransitions()` - 获取条件满足的转移
2. `choiceTransitionByProbability()` - 基于概率权重随机选择
3. `createPlanByTransition()` - 创建转移计划

**任务执行顺序**：
```
1. Transition Task  (转移任务)
2. Exit Task        (退出来源状态)
3. Entry Task       (进入目标状态)
4. Main Task        (主任务)
```

---

## 三、行为树（BehaviorTree）

**文件位置**：`servers/scene_server/internal/common/ai/bt/`

### 3.1 BT 节点基类

```go
type IBtNode interface {
    Begin(scene common.Scene) BtNodeStatus   // 开始执行
    End(scene common.Scene) BtNodeStatus     // 结束执行
    Tick(scene common.Scene) BtNodeStatus    // 每帧逻辑
    Execute(scene common.Scene) BtNodeStatus // 完整执行周期

    NowStatus() BtNodeStatus
    SetStatus(status BtNodeStatus)
    ResetStatus()
    IsRunning() bool
    IsCompleted() bool

    ControlTick(scene, entity, context)      // 控制节点 Tick
    ActionTick(scene, entity, context)       // 动作节点 Tick
}
```

**节点状态**：
| 状态 | 值 | 说明 |
|------|---|------|
| BtNodeStatusInit | 0 | 初始状态 |
| BtNodeStatusRunning | 1 | 运行中 |
| BtNodeStatusSuccess | 2 | 成功 |
| BtNodeStatusFailed | 3 | 失败 |

**节点类型**：
| 类型 | 值 | 说明 |
|------|---|------|
| BTNodeTypeNone | 0 | 无 |
| BTNodeTypeControl | 1 | 控制节点（序列、选择、并行）|
| BTNodeTypeDecorator | 2 | 装饰器 |
| BTNodeTypeLeaf | 3 | 叶子节点（动作、条件）|

### 3.2 执行生命周期

```go
Execute() {
    if !IsRunning() {
        Begin()      // 首次执行
    }
    status := Tick()
    SetStatus(status)
    if IsCompleted() {
        End()        // 执行完成
    }
    return status
}
```

### 3.3 目录结构

```
bt/
├── tree/
│   └── node/
│       ├── bt_node.go        # 节点基类
│       ├── node_control.go   # 控制节点（序列、选择等）
│       ├── node_decorator.go # 装饰节点（条件、重试等）
│       └── node_leaf.go      # 叶子节点（动作）
```

---

## 四、GOAP 系统（Goal-Oriented Action Planning）

**文件位置**：`servers/scene_server/internal/common/ai/decision/goap/`

### 4.1 核心组件

**Action 类**（`action.go`）：
```go
type Action struct {
    Name          string
    Cost          int              // 动作代价
    Preconditions map[int]bool     // 前置条件
    Effects       map[int]bool     // 动作效果
}

func (a *Action) OperableOn(ws *WorldState) bool  // 检查是否可执行
func (a *Action) ActOn(ws *WorldState) *WorldState // 应用动作
```

**WorldState 类**（`worldstate.go`）：
```go
type WorldState struct {
    Vars map[int]bool  // 世界状态变量
}

func (ws *WorldState) DistanceTo(goal *WorldState) int  // 启发式距离
func (ws *WorldState) MeetsGoal(goal *WorldState) bool  // 检查是否满足目标
func (ws *WorldState) Clone() *WorldState               // 克隆
```

**Planner 类**（`planner.go`）：
```go
type Planner struct {
    Open   NodeList  // A* 开放列表
    Closed NodeList  // A* 关闭列表
}

func (p *Planner) Plan(start, goal *WorldState, actions []*Action) ([]*Action, error)
```

### 4.2 A* 规划算法

```
1. 初始化：start 节点加入 Open 列表
2. 循环：
   a. 弹出 F 值最小的节点
   b. 检查是否到达目标
   c. 如果是，重构计划并返回
   d. 如果否，尝试所有可执行的动作
   e. 生成新节点或更新现有节点
3. 最多 1000 次迭代防止无限循环
```

---

## 五、FSM 状态机系统

**文件位置**：`servers/scene_server/internal/common/ai/fsm/state_machine.go`

### 5.1 通用状态机

```go
type StateMachine struct {
    currentState *State           // 当前状态
    states       map[string]*State // 状态映射
    owner        interface{}       // 所有者对象
    enabled      bool             // 是否启用
}

type State struct {
    Name     string
    OnEnter  func()           // 进入回调
    OnUpdate func() State     // 更新逻辑
    OnExit   func()           // 退出回调
}
```

### 5.2 状态转移

```go
func (sm *StateMachine) SetCurrentState(stateName string) error {
    // 1. 调用旧状态的 OnExit
    // 2. 设置新状态
    // 3. 调用新状态的 OnEnter
}

func (sm *StateMachine) Update() {
    if currentState.OnUpdate != nil {
        nextState := currentState.OnUpdate()
        if nextState != currentState {
            // 转移状态
        }
    }
}
```

---

## 六、特征值系统（Value）

**文件位置**：`servers/scene_server/internal/common/ai/value/`

### 6.1 Value 接口

```go
type Value interface {
    Type() ValueType
    Value() any
    Update(v any) error
    Equal(v any) (bool, bool)
    Bigger(v any) (bool, bool)
    Smaller(v any) (bool, bool)
    EqualOrBigger(v any) (bool, bool)
    EqualOrSmaller(v any) (bool, bool)
    String() string
    IsSet() bool
    Query(queryType QueryType) bool
}
```

**值类型**：
| 类型 | 值 | 说明 |
|------|---|------|
| ValueTypeInt | 1 | 整数 |
| ValueTypeUint | 2 | 无符号整数 |
| ValueTypeFloat | 3 | 浮点数 |
| ValueTypeString | 4 | 字符串 |
| ValueTypeBool | 5 | 布尔值 |
| ValueTypeVector | 6 | 向量 |

### 6.2 ValueMgr（值管理器）

```go
type ValueMgr struct {
    values map[string]*CallbackValue
}

func (mgr *ValueMgr) NewValue(key string, valueType ValueType, srcValue any) (*CallbackValue, bool)
func (mgr *ValueMgr) UpdateValue(key string, srcValue any) error
func (mgr *ValueMgr) GetValue(key string) (*CallbackValue, bool)
func (mgr *ValueMgr) PushCBFunc(key string, updateCBFunc, delCBFunc, cbData any)  // 注册回调
```

---

## 七、NPC 组件详解

### 7.1 NpcBase 组件

**文件位置**：`servers/scene_server/internal/ecs/com/cnpc/npc_comp.go`

```go
type NpcComp struct {
    common.ComponentBase
    NpcID        int32               // NPC 配置 ID
    Name         string              // NPC 名称
    Gender       uint32              // 性别
    PartList     []*proto.AvatarPart // 外观部件
    InteractRand float32             // 交互半径
    BodyTimeSec  int32               // 尸体存在时间
    Killer       uint64              // 击杀者 ID
    MonsterDirty bool                // 怪物脏标记
    DeadDropItem string              // 死亡掉落物品
}
```

### 7.2 NpcSchedule 组件（日程系统）

**文件位置**：`servers/scene_server/internal/ecs/com/cnpc/schedule_comp.go`

```go
type NpcScheduleComp struct {
    common.ComponentBase
    cfg              *confignpcschedule.NpcSchedule  // 日程配置
    NowState         *confignpcschedule.CfgNode      // 当前日程节点
    gssStateTransCfg *configNpcGssBrain.Config       // GSS 配置
    orderedMeeting   int32                           // 已预约会议 ID
    MeetingState     int32                           // 会议状态
    MeetingPointID   int32                           // 会议地点 ID
}

// 会议状态
const (
    MeetingStateNone  = 0  // 没有预定
    MeetingStateOrder = 1  // 预定但未开始
    MeetingStateOn    = 2  // 正在进行
)
```

**日程接口**：
```go
func (c *NpcScheduleComp) GetNowSchedule(nowTime int64) *confignpcschedule.CfgNode
func (c *NpcScheduleComp) SetOrderMeeting(meetingID int32) bool
func (c *NpcScheduleComp) ClearMeeting()
```

### 7.3 NpcMove 组件（移动）

**文件位置**：`servers/scene_server/internal/ecs/com/cnpc/npc_move.go`

```go
type NpcMoveComp struct {
    common.ComponentBase
    speed           float32           // 当前速度
    RunSpeed        float32           // 奔跑速度
    BaseSpeed       float32           // 基础速度
    NowKey          string            // 当前路径关键字
    pointList       []*transform.Vec3 // 路点列表
    nowIndex        int               // 当前路点索引
    targetDirection *transform.Vec3   // 目标方向
    eState          int32             // 移动状态
    prevEState      int32             // 之前的状态（暂停/恢复用）
    ePathFindType   int32             // 寻路方式
    NavMesh         NavMeshData       // NavMesh 数据
}
```

**移动状态**：
| 状态 | 值 | 说明 |
|------|---|------|
| EMoveState_Stop | 0 | 停止 |
| EMoveState_Move | 1 | 移动 |
| EMoveState_Run | 2 | 奔跑 |

**寻路类型**：
| 类型 | 值 | 说明 |
|------|---|------|
| EPathFindType_None | 0 | 无 |
| EPathFindType_RoadNetWork | 1 | 路点寻路 |
| EPathFindType_NavMesh | 2 | NavMesh 寻路 |

**关键方法**：
```go
func (c *NpcMoveComp) SetPointList(key string, points []*transform.Vec3, targetDir *transform.Vec3) bool
func (c *NpcMoveComp) StartMove()
func (c *NpcMoveComp) StartRun()
func (c *NpcMoveComp) StopMove()
func (c *NpcMoveComp) PauseState()   // 暂停（保存状态）
func (c *NpcMoveComp) ResumeState()  // 恢复
```

### 7.4 AIDecision 组件

**文件位置**：`servers/scene_server/internal/ecs/com/caidecision/decision.go`

```go
type DecisionComp struct {
    common.ComponentBase
    agent         decision.Agent    // AI 决策代理
    dialogContext *DialogContext    // 对话上下文
}

type DialogContext struct {
    PlayerId uint64
    DialogId int32
}
```

**创建方法**：
```go
func CreateAIDecisionComp(executor decision.Executor, scene common.Scene,
                          entityID uint64, gssTempID string) (*DecisionComp, error)
```

**关键方法**：
```go
func (c *DecisionComp) Update()
func (c *DecisionComp) UpdateFeatureCommand(req decision.UpdateFeatureReq) error
func (c *DecisionComp) UpdateFeature(req decision.UpdateFeatureReq) error
func (c *DecisionComp) GetFeatureValue(key string) value.Value
func (c *DecisionComp) TriggerCommand() error
```

### 7.5 Vision 组件（视野）

**文件位置**：`servers/scene_server/internal/ecs/com/cvision/vision_comp.go`

```go
type VisionComp struct {
    common.ComponentBase
    VisionRadius    float32          // 视野半径（米）
    VisionAngle     float32          // 视野角度（0-360）
    visibleEntities map[uint64]bool  // 视野内实体集合
    isEnabled       bool             // 是否启用
    AlertEntity     uint64           // 正被通缉的实体 ID
}
```

**方法**：
```go
func (v *VisionComp) IsEntityInVision(entityID uint64) bool
func (v *VisionComp) UpdateVisibleEntities(entities []uint64)
func (v *VisionComp) GetVisibleEntities() []uint64
func (v *VisionComp) GetVisibleEntityCount() int
func (v *VisionComp) SetVisionRadius(radius float32)
func (v *VisionComp) SetVisionAngle(angle float32)
```

### 7.6 NpcPolice 组件（警察）

**文件位置**：`servers/scene_server/internal/ecs/com/cpolice/police_comp.go`

```go
type NpcPoliceComp struct {
    common.ComponentBase
    IsPolice                  bool
    config                    *PoliceConfig
    suspicionMap              map[uint64]*PlayerSuspicion  // 警戒信息
    arrestingPlayer           *PlayerSuspicion             // 正在逮捕的玩家
    investigatePlayerEntityID uint64                       // 正在调查的玩家
    lastArrestingFinishTime   int64                        // 逮捕完成时间
    estate                    int32                        // 警察状态
}

type PoliceConfig struct {
    ZeroDistace        float32  // 最近距离阈值
    NearDistance       float32  // 近距离阈值
    MidDistance        float32  // 中距离阈值
    FarDistance        float32  // 远距离阈值
    MaxIncrement       int32    // 近距离警戒增量
    MidIncrement       int32    // 中距离警戒增量
    FarIncrement       int32    // 远距离警戒增量
    SuspicionThreshold int32    // 警戒阈值
    DecayTime          int64    // 衰减开始时间
    DecayRate          int32    // 衰减速率
    ArrestingCD        int64    // 逮捕 CD
    ArrestingDistance  float32  // 逮捕距离
}
```

---

## 八、NPC 创建流程

### 8.1 实体创建步骤

```go
// 1. 创建基础组件
npcComp := cnpc.NewNpcComp(npcID, name, gender, partList, interactRand, bodyTimeSec)

// 2. 创建日程组件
scheduleComp := cnpc.NewNpcScheduleComp(scheduleCfg)

// 3. 创建移动组件
moveComp := cnpc.NewNpcMoveComp(baseSpeed)

// 4. 创建 AI 决策组件
decisionComp, err := caidecision.CreateAIDecisionComp(
    executor,
    scene,
    entityID,
    gssTempID,  // GSS 决策模板 ID
)

// 5. 创建视野组件
visionComp := cvision.NewVisionComp(visionRadius)

// 6. 创建警察组件（可选）
policeComp := cpolice.NewNpcPoliceComp(isPolice)
```

### 8.2 AI Agent 初始化

```go
// 1. 创建值管理器
valueMgr := value.NewValueMgr()

// 2. 创建 AI 代理
aiAgent, _ := agent.New(executor)

// 3. 初始化 AI 代理
initParam := &decision.CreateParam{
    DecisionType: decision.DecisionTypeGSS,
    GSSTempID:    gssTempID,
    EntityID:     uint32(entityID),
}
aiAgent.Init(scene, valueMgr, initParam)
```

### 8.3 GSS Brain 初始化

```go
func newGssBrain(entityID uint32, tempID string, values *value.ValueMgr) (*gssBrain, error) {
    // 1. 获取配置
    config := CfgMgr.GetConfig(tempID)

    // 2. 创建特征系统
    feature := factory.New()
    feature.Init(values, config)

    // 3. 创建状态机
    fsm := NewGssBrainFSM(brain)
    fsm.SetState("Init", context)

    return brain, nil
}
```

---

## 九、日程系统

### 9.1 核心概念

- NPC 根据游戏时间自动执行预定日程
- 日程由 `CfgNode` 组成，每个节点定义一个行动

### 9.2 CfgNode 结构

```go
type CfgNode struct {
    Key      string      // 日程唯一标识
    Time     int64       // 开始时间（游戏时间）
    Duration int64       // 持续时间
    Action   interface{} // 具体动作
}
```

### 9.3 日程查询和执行

```go
// 获取当前日程
nowSchedule := scheduleComp.GetNowSchedule(gameTime)
if nowSchedule != nil {
    // 根据日程类型执行动作
    if moveAction, ok := nowSchedule.Action.(*MoveToBPointFromAPoint); ok {
        pointList := roadNetwork.FindPath(moveAction.APointId, moveAction.BPointId)
        moveComp.SetPointList(nowSchedule.Key, pointList, moveAction.BDirection)
    }
}
```

---

## 十、传感器系统详解

### 10.1 传感器类型

**ViewSensor（视觉传感器）**：
```go
type ViewSensor struct {
    ViewSightHeight         float64  // 射线检测起点高度
    ViewSightDistance       float64  // 检测半径
    ViewSightHorizotalAngle float64  // 水平视角
    ViewSightVerticalAngle  float64  // 垂直视角
    UpdateRate              int      // 每 N 帧更新一次
}
```

**EventSensor（事件传感器）**：
- 检测游戏事件（交互、对话、碰撞等）

**DistanceSensor（距离传感器）**：
- 检测与特定目标的距离

### 10.2 传感器接口

```go
type FeatureSensor interface {
    Sense(entity common.Entity) (map[int32]any, error)
}

type BaseFeatureSensor struct {
    common.ComponentBase
}
```

### 10.3 传感器用途

- 更新特征值系统中的 Feature 数据
- 实时反映游戏状态变化
- 影响条件评估和决策生成

---

## 十一、AI 配置文件格式

### 11.1 完整配置示例

```json
{
    "name": "npc_default_behavior",
    "init_plan": "idle",
    "plan_interval": 1000,

    "plans": [
        {
            "name": "idle",
            "entry_task": "on_idle_enter",
            "main_task": "do_idle",
            "exit_task": "on_idle_exit"
        },
        {
            "name": "move",
            "entry_task": "on_move_enter",
            "main_task": "do_move",
            "exit_task": "on_move_exit"
        },
        {
            "name": "dialog",
            "entry_task": "on_dialog_enter",
            "main_task": "do_dialog",
            "exit_task": "on_dialog_exit"
        }
    ],

    "transitions": [
        {
            "name": "idle_to_move",
            "from": "idle",
            "to": "move",
            "priority": 10,
            "probability": 50,
            "transition_task": "prepare_move",
            "condition": {
                "op": "and",
                "conditions": [
                    {
                        "key": "player_nearby",
                        "op": "eq",
                        "value": true
                    },
                    {
                        "key": "distance_to_player",
                        "op": "lt",
                        "value": 20.0
                    }
                ]
            }
        },
        {
            "name": "idle_to_dialog",
            "from": "idle",
            "to": "dialog",
            "priority": 20,
            "probability": 100,
            "condition": {
                "op": "and",
                "conditions": [
                    {
                        "key": "is_talking",
                        "op": "eq",
                        "value": true
                    }
                ]
            }
        }
    ],

    "features": {
        "player_nearby": false,
        "distance_to_player": 100.0,
        "is_talking": false,
        "health": 100,
        "energy": 100
    },

    "sensors": {
        "view": {
            "view_sight_height": 1.6,
            "view_sight_distance": 30.0,
            "view_sight_horizotal_angle": 120.0,
            "view_sight_vertical_angle": 60.0,
            "update_rate": 10
        }
    }
}
```

### 11.2 嵌套条件示例

```json
"condition": {
    "op": "or",
    "conditions": [
        {
            "key": "state",
            "op": "eq",
            "value": "alert"
        },
        {
            "condition": {
                "op": "and",
                "conditions": [
                    {
                        "key": "health",
                        "op": "lt",
                        "value": 30
                    },
                    {
                        "key": "is_fleeing",
                        "op": "eq",
                        "value": true
                    }
                ]
            }
        }
    ]
}
```

---

## 十二、NPC 移动系统

**文件位置**：`servers/scene_server/internal/ecs/system/npc/move.go`

### 12.1 路点寻路

```go
// 1. 获取路点列表
pointList := roadNetworkMgr.MapInfo.FindPathToVec3List(startPointId, endPointId)

// 2. 设置到移动组件
moveComp.SetPointList(key, pointList, targetDirection)

// 3. 每帧更新
nextPoint := moveComp.GetNextPoint()
if nearPoint {
    moveComp.PassPoint()
}
```

### 12.2 NavMesh 寻路

```go
// 1. 创建 NavMesh Agent
agent := navmesh.NewAgent(position, radius, height, maxSpeed)
moveComp.SetNavAgent(agent, radius, height, maxSpeed)

// 2. 计算路径
path := navmesh.ComputePath(agent, targetPos)
moveComp.SetNavPath(path)

// 3. 每帧更新
moveComp.UpdateNavAgent(deltaTime)
if moveComp.IsNavPathComplete() {
    moveComp.StopNavMove()
}
```

### 12.3 状态控制

```go
moveComp.PauseState()   // 暂停（保存当前状态）
moveComp.ResumeState()  // 恢复到之前的状态
moveComp.StopMove()     // 立即停止
moveComp.StartMove()    // 开始移动
moveComp.StartRun()     // 开始奔跑
```

---

## 十三、视野系统

### 13.1 视野检测机制

```go
func updateVision(npcEntity, targetEntity) {
    // 1. 计算距离
    distance := getDistance(npcEntity, targetEntity)

    // 2. 检查距离范围
    if distance > visionComp.VisionRadius {
        return  // 超出视野距离
    }

    // 3. 检查视野角度
    if visionComp.VisionAngle < 360 {
        angle := getAngleBetween(npcEntity, targetEntity)
        if angle > visionComp.VisionAngle / 2 {
            return  // 超出视野角度
        }
    }

    // 4. 视线检测（射线检测）
    if !raycast(npcEntity, targetEntity) {
        return  // 被遮挡
    }

    // 5. 更新视野
    visionComp.UpdateVisibleEntities(append(visibleEntities, targetEntity.ID()))
}
```

### 13.2 视野应用

```go
// 在警察系统中应用视野
for _, visibleEntity := range visionComp.GetVisibleEntities() {
    if isTarget(visibleEntity) {
        lastSeeTime = now
        suspicion += increment
    }
}

// 判断是否失去目标
if now - lastSeeTime > timeout {
    visionComp.ClearVisibleEntities()
}
```

---

## 十四、警察系统和通缉系统

### 14.1 警察系统

**文件位置**：`servers/scene_server/internal/ecs/system/police/police_system.go`

```go
type NpcPoliceSystem struct {
    *system.SystemBase
    tickInterval int32  // 更新间隔（3 帧）
    tickCounter  int32
}
```

**更新逻辑**：
```go
func (p *NpcPoliceSystem) Update() {
    // 1. 每 3 帧更新一次
    if tickCounter % 3 != 0 {
        return
    }

    // 2. 获取所有警察 NPC
    policeNpcs := townMgr.GetPoliceNpcs()

    // 3. 更新每个警察
    for _, townNpc := range policeNpcs {
        p.updatePoliceLogic(townNpc.Entity)
    }
}
```

**警戒值计算**：
```go
func calculateSuspicion(distance float32, config *PoliceConfig) int32 {
    if distance <= config.NearDistance {
        return config.MaxIncrement      // 140
    } else if distance <= config.MidDistance {
        return config.MidIncrement      // 35
    } else if distance <= config.FarDistance {
        return config.FarIncrement      // 20
    }
    return 0
}
```

### 14.2 通缉系统

**文件位置**：`servers/scene_server/internal/ecs/system/police/being_wanted_system.go`

```go
type BeingWantedSystem struct {
    *system.SystemBase
    tickInterval int32  // 更新间隔（10 帧）
    tickCounter  int32
}
```

**状态转换逻辑**：
```
- 有警察追捕：实时更新 lastWantedTime，状态 = Wanted
- 没有警察追捕 < 5秒：状态保持 Wanted
- 5秒 <= 没有警察 < 35秒：状态 = MissWanted（警察还在寻找）
- 没有警察 >= 35秒：状态 = None（完全逃脱）
```

**常量定义**：
```go
const (
    CMissWantedTimeout = 5000   // 5 秒
    CNoneWantedTimeout = 35000  // 35 秒
)
```

### 14.3 警察-玩家交互流程

```
1. 玩家进入警察视野
    ↓
2. 警察开始计算警戒值（距离 + 视线检测）
    ↓
3. 警戒值达到阈值（例如 700）
    ↓
4. 警察状态切换到 Arresting（逮捕）
    ↓
5. 警察移动到玩家并逮捕
    ↓
6. 玩家被标记为 Wanted（通缉）
    ↓
7. 玩家逃脱（超过视野距离）
    ↓
8. 警察失去目标，警戒值开始衰减
    ↓
9. 状态转换：Wanted → MissWanted → None
```

---

## 十五、决策执行流程

**文件位置**：`servers/scene_server/internal/ecs/system/decision/executor.go`

### 15.1 计划执行

```go
func (e *Executor) OnPlanCreated(req *decision.OnPlanCreatedReq) error {
    entityID := req.EntityID
    plan := req.Plan

    for _, task := range plan.Tasks {
        e.executeTask(entityID, plan.Name, plan.FromPlan, task)
    }
}

func (e *Executor) executeTask(entityID uint32, planName, fromPlan string, task *decision.Task) {
    switch task.Type {
    case TaskTypeTransition:
        e.executeGSSTransTask(entityID, planName, fromPlan, task)
    case TaskTypeGSSEnter:
        e.executeGSSEntryTask(entityID, planName, task)
    case TaskTypeGSSExit:
        e.executeGSSExitTask(entityID, fromPlan, task)
    case TaskTypeGSSMain:
        e.executeGSSMainTask(entityID, planName, task)
    }
}
```

### 15.2 任务类型

| 类型 | 说明 |
|------|------|
| TransitionTask | 状态过渡逻辑 |
| EntryTask | 新状态初始化 |
| MainTask | 状态核心逻辑 |
| ExitTask | 旧状态清理 |

### 15.3 Feature 参数传递

```go
func (b *gssBrain) packDialogArgs() []any {
    args := make([]any, 0, 1)
    if val, ok := b.feature.GetValue("feature_state"); ok {
        if val.Value() == "idle" {
            args = append(args, "idle")
        } else {
            args = append(args, "dialog")
        }
    }
    return args
}

func (b *gssBrain) packFeatureArgs() []any {
    args := make([]any, 0, 1)
    features := make(map[string]any)

    for featureName := range b.config.Features {
        if val, ok := b.feature.GetValue(featureName); ok {
            features[featureName] = val.Value()
        }
    }

    args = append(args, features)
    return args
}
```

---

## 十六、系统集成和性能优化

### 16.1 DecisionSystem

**文件位置**：`servers/scene_server/internal/ecs/system/decision/decision.go`

```go
type DecisionSystem struct {
    *system.SystemBase
    lastUpdateTime int64
    updateIndex    int              // 分帧处理索引
    npcListCache   []common.Entity  // NPC 缓存
    frameCount     int
}

const (
    UpdateInterval          = 1    // 每 1 秒更新一次
    MaxNpcsPerUpdate        = 100  // 每次最多处理 100 个 NPC
    NpcCacheRefreshInterval = 1    // 每 1 秒刷新缓存
)
```

**分帧处理**：
```go
func (ds *DecisionSystem) Update() {
    ds.frameCount++

    // 定期刷新缓存
    if ds.frameCount % NpcCacheRefreshInterval == 0 {
        ds.refreshNpcCache()
    }

    // 检查更新间隔
    if now - ds.lastUpdateTime < UpdateInterval {
        return
    }

    // 分帧处理 NPC
    for i := 0; i < MaxNpcsPerUpdate && processedCount < npcCount; i++ {
        idx := (ds.updateIndex + i) % npcCount
        entity := ds.npcListCache[idx]

        decisionComp := getComponent(entity, ComponentType_AIDecision)
        decisionComp.Update()
    }

    ds.updateIndex += MaxNpcsPerUpdate
}
```

### 16.2 性能优化策略

| 策略 | 说明 |
|------|------|
| **NPC 缓存** | 减少每帧遍历，定期刷新 |
| **分帧处理** | 每帧最多处理 100 个 NPC |
| **更新间隔** | 决策 1 秒，警察 3 帧，通缉 10 帧 |
| **条件缓存** | transitionsMap 预构建，加速查询 |
| **状态机优化** | 名称映射存储，快速查询转移 |

---

## 十七、关键源码文件索引

| 功能 | 文件路径 |
|------|---------|
| AI 决策类型 | `internal/common/ai/decision/types.go` |
| GSS Brain | `internal/common/ai/decision/agent/gss.go` |
| GSS 配置 | `internal/common/ai/decision/gss_brain/config/config.go` |
| 条件系统 | `internal/common/ai/decision/gss_brain/condition/mgr.go` |
| 特征系统 | `internal/common/ai/decision/gss_brain/feature/feature.go` |
| GSS FSM | `internal/common/ai/decision/fsm/gss_brain_fsm.go` |
| 值系统 | `internal/common/ai/value/` |
| GOAP | `internal/common/ai/decision/goap/` |
| 通用 FSM | `internal/common/ai/fsm/state_machine.go` |
| 行为树 | `internal/common/ai/bt/tree/node/` |
| NPC 组件 | `internal/ecs/com/cnpc/` |
| AI 决策组件 | `internal/ecs/com/caidecision/decision.go` |
| 视野组件 | `internal/ecs/com/cvision/vision_comp.go` |
| 警察组件 | `internal/ecs/com/cpolice/police_comp.go` |
| 决策系统 | `internal/ecs/system/decision/` |
| 传感器系统 | `internal/ecs/system/sensor/` |
| 视野系统 | `internal/ecs/system/vision/` |
| NPC 移动系统 | `internal/ecs/system/npc/move.go` |
| 警察系统 | `internal/ecs/system/police/` |

---

## 总结

### AI 决策系统特点

1. **模块化设计** - 清晰的层次结构，易于扩展
2. **配置驱动** - JSON 配置文件定义行为，支持热重载
3. **条件树支持** - 嵌套条件（最深 5 层），灵活的决策逻辑
4. **特征系统** - 动态特征值管理，多种数据类型
5. **多决策模型** - GSS、NDU、GOAP、行为树

### NPC 系统特点

1. **完整组件体系** - 基础信息、日程、移动、AI 决策、视野、警察
2. **两种寻路方式** - 路点寻路、NavMesh 网格寻路
3. **日程系统** - 自动执行预定日程，支持会议预约
4. **警察系统** - 实时警戒值计算，逮捕和通缉机制
5. **状态管理** - 暂停/恢复机制，完整的状态转移
6. **性能优化** - 分帧处理、缓存策略、更新间隔控制
