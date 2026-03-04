# 小镇物理系统设计文档

> 所有代码路径均相对于 `P1GoServer/` 目录。

## 1. 概述

### 1.1 设计目标

为小镇场景添加完整的物理系统，支持：

| 功能 | 说明 |
|------|------|
| 刚体碰撞 | 物体间的碰撞检测和响应 |
| 视野遮挡 | 基于射线检测的视线阻挡判断 |
| 角色运动 | 玩家/NPC 的物理运动控制 |
| 战斗系统 | 攻击判定、伤害区域检测 |
| 技能系统 | 技能范围检测、弹道轨迹 |

### 1.2 设计原则

1. **与 NavMesh 协作**：NavMesh 负责高层寻路，物理系统负责低层碰撞
2. **渐进式启用**：分阶段启用功能，降低集成风险
3. **ECS 架构**：遵循现有 ECS 模式，Component 存数据，System 处理逻辑
4. **优雅降级**：物理系统初始化失败时不阻塞场景加载

### 1.3 现有基础

项目已集成 **NVIDIA PhysX** 框架，但 Linux 实现已被注释：

| 组件 | 位置 | 状态 |
|------|------|------|
| PhysX 包装器 | `pkg/physics/` | 框架完整，Linux 实现已注释 |
| ECS 物理组件 | `ecs/com/cphysics/` | 已定义基础形状 |
| 物理资源 | `ecs/res/physx.go` | 已定义 |
| 触发器组件 | `ecs/com/trigger/` | 已定义 |

### 1.4 坐标系约定

**统一使用右手坐标系**（与 NavMesh 一致）：

| 轴 | 方向 |
|---|------|
| X | 右 |
| Y | 上 |
| Z | 前 |

**注意**：Unity 客户端使用左手坐标系，需要在同步时进行 Z 轴取反。

---

## 2. 系统架构

### 2.1 分层架构

```
┌─────────────────────────────────────────────────────────────┐
│                      业务层 (Business)                       │
│  战斗系统 │ 技能系统 │ 视野系统 │ AI 决策                      │
├─────────────────────────────────────────────────────────────┤
│                      物理服务层 (Service)                    │
│  PhysicsService: 碰撞查询、射线检测、触发器管理、ID映射       │
├─────────────────────────────────────────────────────────────┤
│                      ECS 层 (ECS)                            │
│  PhysicsUpdateSystem │ PhysicsComp │ Physx Resource          │
├─────────────────────────────────────────────────────────────┤
│                      引擎层 (Engine)                         │
│  pkg/physics (PhysX 封装) │ common/physics (通用接口)        │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 与现有系统的关系

```
                NavMesh (寻路)
                    │
                    │ 路径点
                    ▼
    ┌───────────────────────────────┐
    │      NpcMoveSystem            │
    │  (移动目标、速度计算)          │
    └───────────────┬───────────────┘
                    │ 位移请求
                    ▼
    ┌───────────────────────────────┐
    │    PhysicsUpdateSystem        │
    │  (碰撞检测、位置修正)          │
    └───────────────┬───────────────┘
                    │ 最终位置
                    ▼
    ┌───────────────────────────────┐
    │      Transform 组件           │
    │  (同步到客户端)               │
    └───────────────────────────────┘
```

---

## 3. 核心类型扩展

### 3.1 RaycastResult 扩展

**文件**: `pkg/physics/type.go` (修改)

```go
type RaycastResult struct {
    Hit         bool
    HitActorID  int      // 新增：命中的 PhysX Actor ID
    HitX        float32
    HitY        float32
    HitZ        float32
    NormalX     float32
    NormalY     float32
    NormalZ     float32
    Distance    float32
}

// OverlapResult 范围检测结果
type OverlapResult struct {
    ActorIDs []int  // 范围内的所有 Actor ID
}
```

### 3.2 新增 Overlap 接口

**文件**: `pkg/physics/physx_linux.go` (新增方法)

```go
// OverlapSphere 球形范围检测
func (s *SourcePhysx) OverlapSphere(center Vec3f, radius float32, layerMask uint32) OverlapResult {
    // C.overlapSphere(...)
    return OverlapResult{}
}

// OverlapBox 盒形范围检测
func (s *SourcePhysx) OverlapBox(center Vec3f, halfExtents Vec3f, layerMask uint32) OverlapResult {
    // C.overlapBox(...)
    return OverlapResult{}
}

// RaycastWithMask 带碰撞层过滤的射线检测
func (s *SourcePhysx) RaycastWithMask(origin, dir Vec3f, maxDist float32, layerMask uint32) RaycastResult {
    // C.raycastWithMask(...)
    return RaycastResult{}
}
```

---

## 4. 核心组件设计

### 4.1 PhysicsComp 扩展

**文件**: `ecs/com/cphysics/physics.go`

```go
type PhysicsComp struct {
    common.ComponentBase

    // === 形状参数 ===
    Shape     ShapeType  // Sphere=0, Box=1, Capsule=2
    Radius    float32    // 球体/胶囊体半径
    Height    float32    // 胶囊体高度
    HalfX     float32    // 盒子半尺寸
    HalfY     float32
    HalfZ     float32

    // === 物理属性 ===
    PhysicsID int        // PhysX 中的物体 ID（运行时分配）
    BodyType  BodyType   // Static=0, Dynamic=1, Kinematic=2
    Mass      float32    // 质量（Dynamic 有效）
    Layer     uint32     // 碰撞层（用于过滤）

    // === 状态标记 ===
    IsCreated bool       // 是否已在物理世界创建
    IsDirty   bool       // 位置是否需要同步
}

type BodyType int
const (
    BodyType_Static    BodyType = 0  // 静态物体（墙、地面）
    BodyType_Dynamic   BodyType = 1  // 动态刚体
    BodyType_Kinematic BodyType = 2  // 运动学物体（由代码控制位置）
)

type ShapeType int
const (
    ShapeType_Sphere  ShapeType = 0
    ShapeType_Box     ShapeType = 1
    ShapeType_Capsule ShapeType = 2
)
```

### 4.2 碰撞层定义（完整版）

**文件**: `ecs/com/cphysics/layer.go` (新增)

```go
// 碰撞层定义
const (
    Layer_Default    uint32 = 1 << 0  // 默认层
    Layer_Player     uint32 = 1 << 1  // 玩家
    Layer_NPC        uint32 = 1 << 2  // NPC
    Layer_Static     uint32 = 1 << 3  // 静态物体（墙、建筑）
    Layer_Dynamic    uint32 = 1 << 4  // 动态物体（可推动）
    Layer_Trigger    uint32 = 1 << 5  // 触发器（不产生物理响应）
    Layer_Projectile uint32 = 1 << 6  // 投射物（子弹、技能）
    Layer_Vision     uint32 = 1 << 7  // 视野遮挡物
)

// 碰撞矩阵（完整版）
var CollisionMatrix = map[uint32]uint32{
    Layer_Default:    Layer_Default | Layer_Static | Layer_Dynamic,
    Layer_Player:     Layer_Static | Layer_NPC | Layer_Dynamic | Layer_Trigger,
    Layer_NPC:        Layer_Static | Layer_Player | Layer_NPC | Layer_Dynamic | Layer_Trigger,
    Layer_Static:     Layer_Player | Layer_NPC | Layer_Dynamic | Layer_Projectile,  // 静态物体不互相碰撞
    Layer_Dynamic:    Layer_Static | Layer_Player | Layer_NPC | Layer_Dynamic,
    Layer_Trigger:    Layer_Player | Layer_NPC,  // 触发器只检测玩家和NPC
    Layer_Projectile: Layer_Static | Layer_Player | Layer_NPC,
    Layer_Vision:     Layer_Static,  // 视野射线只检测静态遮挡物
}

// CanCollide 检查两个层是否可以碰撞
func CanCollide(layerA, layerB uint32) bool {
    maskA, okA := CollisionMatrix[layerA]
    maskB, okB := CollisionMatrix[layerB]
    if !okA || !okB {
        return true  // 默认可碰撞
    }
    return (maskA&layerB) != 0 && (maskB&layerA) != 0
}
```

### 4.3 CharacterControllerComp

**文件**: `ecs/com/cphysics/character_controller.go` (新增)

```go
// CharacterControllerComp 角色控制器组件
// 用于玩家和 NPC 的运动控制（替代 PhysicsComp 用于角色）
type CharacterControllerComp struct {
    common.ComponentBase

    ControllerID int     // PhysX CharacterController ID
    Radius       float32 // 胶囊体半径
    Height       float32 // 胶囊体高度
    StepOffset   float32 // 可跨越的台阶高度
    SlopeLimit   float32 // 可行走的坡度限制（角度）

    // 运动状态
    Velocity     Vec3f   // 当前速度
    IsGrounded   bool    // 是否着地
    IsCreated    bool    // 是否已创建
}

func NewCharacterControllerComp(radius, height float32) *CharacterControllerComp {
    return &CharacterControllerComp{
        Radius:     radius,
        Height:     height,
        StepOffset: 0.3,  // 30cm 台阶
        SlopeLimit: 45.0, // 45 度坡
    }
}
```

### 4.4 组件使用场景说明

| 实体类型 | 推荐组件 | 说明 |
|---------|---------|------|
| 墙/建筑 | `PhysicsComp` (Static) | 静态碰撞体，不移动 |
| 可推动物体 | `PhysicsComp` (Dynamic) | 受力移动的刚体 |
| 玩家 | `CharacterControllerComp` | 角色控制器，带台阶和坡度处理 |
| NPC | `CharacterControllerComp` | 角色控制器 |
| 触发区域 | `TriggerComp` | 只检测进入/离开，不产生碰撞响应 |

**注意**：角色（玩家/NPC）使用 `CharacterControllerComp`，不需要同时使用 `PhysicsComp`。

---

## 5. 系统设计

### 5.1 PhysicsUpdateSystem

**文件**: `ecs/system/physics/physics_system.go` (新增)

```go
type PhysicsUpdateSystem struct {
    *system.SystemBase

    physx           *physics.Physx  // 物理引擎实例
    fixedDeltaT     float32         // 固定时间步长 (1/60 = 0.0167s)
    accumulator     float32         // 时间累积器
    lastUpdateTime  int64           // 上次更新时间戳（毫秒）

    // ID 映射管理
    physicsToEntity map[int]uint64   // PhysicsID -> EntityID
    entityToPhysics map[uint64]int   // EntityID -> PhysicsID

    // 待创建/销毁的物体队列
    pendingCreate  []uint64
    pendingDestroy []int

    // 性能统计
    stats PhysicsStats
}

// PhysicsStats 性能统计
type PhysicsStats struct {
    LastStepTimeMs  float32  // 上次 Step 耗时（毫秒）
    CollisionCount  int      // 碰撞次数
    RaycastCount    int      // 射线检测次数
    TriggerEvents   int      // 触发器事件数
    ActiveBodies    int      // 活跃刚体数量
}

func NewPhysicsUpdateSystem(scene common.Scene) *PhysicsUpdateSystem {
    return &PhysicsUpdateSystem{
        SystemBase:      system.New(scene),
        fixedDeltaT:     1.0 / 60.0,  // 60Hz 物理更新
        physicsToEntity: make(map[int]uint64),
        entityToPhysics: make(map[uint64]int),
    }
}

func (s *PhysicsUpdateSystem) Type() common.SystemType {
    return common.SystemType_Physics
}
```

### 5.2 系统更新流程

```go
func (s *PhysicsUpdateSystem) Update() {
    if s.physx == nil {
        return  // 物理系统未初始化，跳过
    }

    // 计算时间差（使用与 NpcMoveSystem 一致的时间源）
    nowMs := mtime.NowMilliTickWithOffset()
    if s.lastUpdateTime == 0 {
        s.lastUpdateTime = nowMs
        return
    }
    dtMs := nowMs - s.lastUpdateTime
    s.lastUpdateTime = nowMs
    dt := float32(dtMs) / 1000.0  // 转换为秒

    s.accumulator += dt

    // 1. 处理待创建的物理对象
    s.processPendingCreates()

    // 2. 扫描新增/删除的物理组件
    s.syncEntityLifecycle()

    // 3. 同步 Transform → Physics (Kinematic 物体)
    s.syncTransformToPhysics()

    // 4. 固定步长物理模拟
    stepStart := mtime.NowMilliTickWithOffset()
    for s.accumulator >= s.fixedDeltaT {
        s.physx.Step(s.fixedDeltaT)
        s.accumulator -= s.fixedDeltaT
    }
    s.stats.LastStepTimeMs = float32(mtime.NowMilliTickWithOffset()-stepStart)

    // 5. 同步 Physics → Transform (Dynamic 物体)
    s.syncPhysicsToTransform()

    // 6. 处理触发器事件
    s.processTriggerEvents()

    // 7. 处理待销毁的物理对象
    s.processPendingDestroys()
}
```

### 5.3 ID 映射管理

```go
// RegisterPhysicsEntity 注册物理对象与实体的映射
func (s *PhysicsUpdateSystem) RegisterPhysicsEntity(physicsID int, entityID uint64) {
    s.physicsToEntity[physicsID] = entityID
    s.entityToPhysics[entityID] = physicsID
}

// UnregisterPhysicsEntity 取消映射
func (s *PhysicsUpdateSystem) UnregisterPhysicsEntity(physicsID int, entityID uint64) {
    delete(s.physicsToEntity, physicsID)
    delete(s.entityToPhysics, entityID)
}

// GetEntityByPhysicsID 通过物理 ID 获取实体 ID
func (s *PhysicsUpdateSystem) GetEntityByPhysicsID(physicsID int) (uint64, bool) {
    entityID, ok := s.physicsToEntity[physicsID]
    return entityID, ok
}

// GetPhysicsIDByEntity 通过实体 ID 获取物理 ID
func (s *PhysicsUpdateSystem) GetPhysicsIDByEntity(entityID uint64) (int, bool) {
    physicsID, ok := s.entityToPhysics[entityID]
    return physicsID, ok
}
```

### 5.4 生命周期同步

```go
// syncEntityLifecycle 同步实体生命周期
// 扫描所有带物理组件的实体，确保物理对象与实体同步
func (s *PhysicsUpdateSystem) syncEntityLifecycle() {
    // 收集当前所有带物理组件的实体
    currentEntities := make(map[uint64]bool)

    for _, entity := range s.Scene().EntityList() {
        entityID := entity.ID()

        // 检查 PhysicsComp
        if comp, ok := common.GetComponentAs[*cphysics.PhysicsComp](
            s.Scene(), entityID, common.ComponentType_Physics); ok {
            currentEntities[entityID] = true

            if !comp.IsCreated {
                s.pendingCreate = append(s.pendingCreate, entityID)
            }
        }

        // 检查 CharacterControllerComp
        if comp, ok := common.GetComponentAs[*cphysics.CharacterControllerComp](
            s.Scene(), entityID, common.ComponentType_CharacterController); ok {
            currentEntities[entityID] = true

            if !comp.IsCreated {
                s.pendingCreate = append(s.pendingCreate, entityID)
            }
        }
    }

    // 检查已删除的实体，清理物理对象
    for entityID, physicsID := range s.entityToPhysics {
        if !currentEntities[entityID] {
            s.pendingDestroy = append(s.pendingDestroy, physicsID)
            s.UnregisterPhysicsEntity(physicsID, entityID)
        }
    }
}
```

### 5.5 触发器事件处理

```go
// TriggerEventType 触发器事件类型
type TriggerEventType int
const (
    TriggerEvent_Enter TriggerEventType = 1  // 进入触发器
    TriggerEvent_Exit  TriggerEventType = 2  // 离开触发器
    TriggerEvent_Stay  TriggerEventType = 3  // 停留在触发器内
)

// TriggerEventData 触发器事件数据
type TriggerEventData struct {
    EventType    TriggerEventType
    TriggerID    uint64  // 触发器实体 ID
    OtherID      uint64  // 进入/离开的实体 ID
    Timestamp    int64
}

// processTriggerEvents 处理触发器事件
func (s *PhysicsUpdateSystem) processTriggerEvents() {
    // 从 PhysX 获取触发器事件
    events := s.physx.GetTriggerEvents()

    for _, event := range events {
        // 转换 PhysicsID -> EntityID
        triggerEntityID, ok1 := s.GetEntityByPhysicsID(event.TriggerPtr)
        otherEntityID, ok2 := s.GetEntityByPhysicsID(event.OtherPtr)

        if !ok1 || !ok2 {
            continue
        }

        eventData := TriggerEventData{
            EventType: TriggerEventType(event.EventType),
            TriggerID: triggerEntityID,
            OtherID:   otherEntityID,
            Timestamp: mtime.NowMilliTickWithOffset(),
        }

        // 分发事件到触发器组件
        s.dispatchTriggerEvent(eventData)

        s.stats.TriggerEvents++
    }
}

// dispatchTriggerEvent 分发触发器事件
func (s *PhysicsUpdateSystem) dispatchTriggerEvent(event TriggerEventData) {
    // 获取触发器组件
    triggerComp, ok := common.GetComponentAs[*trigger.TriggerComp](
        s.Scene(), event.TriggerID, common.ComponentType_Trigger)
    if !ok {
        return
    }

    // 调用触发器的回调
    switch event.EventType {
    case TriggerEvent_Enter:
        if triggerComp.OnEnter != nil {
            triggerComp.OnEnter(event.OtherID)
        }
    case TriggerEvent_Exit:
        if triggerComp.OnExit != nil {
            triggerComp.OnExit(event.OtherID)
        }
    }
}
```

### 5.6 SystemType 注册顺序

**文件**: `common/ecs.go` 修改

```go
const (
    SystemType_Base SystemType = iota
    // ...
    SystemType_NpcUpdate    // NPC更新系统
    SystemType_NpcMove      // NPC移动系统（计算期望位移）
    SystemType_Physics      // 物理更新系统（碰撞检测、位置修正）← 新增，在 NpcMove 之后
    SystemType_AIDecision   // AI决策系统
    // ...
    SystemType_NetUpdate    // 网络更新系统（最后执行）
    SystemType_MAX
)
```

**执行顺序说明**：
1. `NpcMoveSystem` 计算 NPC 的期望位移
2. `PhysicsUpdateSystem` 执行碰撞检测，修正最终位置
3. `NetUpdateSystem` 将最终位置同步到客户端

---

## 6. 物理服务层

### 6.1 PhysicsService

**文件**: `ecs/system/physics/physics_service.go` (新增)

```go
// PhysicsService 物理查询服务
// 提供给业务层的统一接口
type PhysicsService struct {
    system *PhysicsUpdateSystem
}

func NewPhysicsService(system *PhysicsUpdateSystem) *PhysicsService {
    return &PhysicsService{system: system}
}

// CheckLineOfSight 检查两点之间是否有视线
func (s *PhysicsService) CheckLineOfSight(from, to Vec3f) bool {
    if s.system.physx == nil {
        return true  // 物理系统未启用，默认无遮挡
    }

    dir := normalize(sub(to, from))
    distance := length(sub(to, from))

    result := s.system.physx.RaycastWithMask(from, dir, distance, Layer_Vision)
    s.system.stats.RaycastCount++

    return !result.Hit
}

// RaycastEntity 射线检测，返回命中的实体 ID
func (s *PhysicsService) RaycastEntity(from, dir Vec3f, maxDist float32, layerMask uint32) (uint64, bool) {
    if s.system.physx == nil {
        return 0, false
    }

    result := s.system.physx.RaycastWithMask(from, dir, maxDist, layerMask)
    s.system.stats.RaycastCount++

    if !result.Hit {
        return 0, false
    }

    entityID, ok := s.system.GetEntityByPhysicsID(result.HitActorID)
    return entityID, ok
}

// OverlapSphereEntities 球形范围检测，返回实体 ID 列表
func (s *PhysicsService) OverlapSphereEntities(center Vec3f, radius float32, layerMask uint32) []uint64 {
    if s.system.physx == nil {
        return nil
    }

    result := s.system.physx.OverlapSphere(center, radius, layerMask)

    entities := make([]uint64, 0, len(result.ActorIDs))
    for _, actorID := range result.ActorIDs {
        if entityID, ok := s.system.GetEntityByPhysicsID(actorID); ok {
            entities = append(entities, entityID)
        }
    }

    return entities
}

// MoveCharacter 移动角色（带碰撞检测）
func (s *PhysicsService) MoveCharacter(entityID uint64, displacement Vec3f, dt float32) bool {
    if s.system.physx == nil {
        return false
    }

    comp, ok := common.GetComponentAs[*cphysics.CharacterControllerComp](
        s.system.Scene(), entityID, common.ComponentType_CharacterController)
    if !ok || !comp.IsCreated {
        return false
    }

    s.system.physx.MoveCharacterController(comp.ControllerID, displacement, dt)
    actualPos := s.system.physx.GetCharacterControllerPosition(comp.ControllerID)
    updateTransformPosition(s.system.Scene(), entityID, actualPos)

    return true
}

// GetStats 获取性能统计
func (s *PhysicsService) GetStats() PhysicsStats {
    return s.system.stats
}
```

---

## 7. 场景初始化

### 7.1 资源初始化

**文件**: `scene_impl.go` 修改

```go
func (s *scene) townRosurceInit(saveInfo *proto.DBSaveTownInfo) error {
    // ... 现有资源初始化 ...

    // 新增：初始化物理资源
    if err := s.initPhysicsResource(); err != nil {
        s.Warningf("init physics resource failed: %v, physics disabled", err)
        // 物理系统可选，失败不阻塞场景加载
    }

    // ... 其他资源 ...
    return nil
}

// initPhysicsResource 初始化物理资源
func (s *scene) initPhysicsResource() error {
    physxRes, err := resource.NewPhysx()
    if err != nil {
        return fmt.Errorf("create physx resource: %w", err)
    }

    s.AddResource(physxRes)

    // 加载场景静态碰撞体
    if err := s.loadPhysicsColliders(); err != nil {
        s.Warningf("load physics colliders failed: %v", err)
        // 碰撞体加载失败不影响物理系统运行
    }

    return nil
}

// loadPhysicsColliders 加载场景静态碰撞体
func (s *scene) loadPhysicsColliders() error {
    physxRes, ok := common.GetResourceAs[*resource.Physx](s, common.ResourceType_Physx)
    if !ok {
        return errors.New("physx resource not found")
    }

    colliderFile := s.Config().GetColliderFile()
    if colliderFile == "" {
        return nil  // 没有配置碰撞体文件
    }

    colliders, err := loadColliderData(colliderFile)
    if err != nil {
        return fmt.Errorf("load collider file %s: %w", colliderFile, err)
    }

    physx := physxRes.GetPhysx()
    for _, c := range colliders {
        _, err := physx.CreateBox(c.Position, c.HalfX, c.HalfY, c.HalfZ)
        if err != nil {
            s.Warningf("create collider failed: %v", err)
        }
    }

    s.Infof("loaded %d physics colliders", len(colliders))
    return nil
}
```

### 7.2 碰撞体数据格式

**文件格式**: JSON

```json
{
  "colliders": [
    {
      "id": 1,
      "type": "box",
      "position": {"x": 0, "y": 0, "z": 0},
      "halfExtents": {"x": 5, "y": 2, "z": 5},
      "layer": "static"
    },
    {
      "id": 2,
      "type": "capsule",
      "position": {"x": 10, "y": 0, "z": 10},
      "radius": 0.5,
      "height": 2.0,
      "layer": "dynamic"
    }
  ]
}
```

**数据来源**：
- 由场景编辑器导出
- 存放在 `resources/colliders/` 目录
- 命名规则：`{scene_name}_colliders.json`

---

## 8. 错误处理与降级策略

### 8.1 初始化失败处理

| 失败场景 | 处理方式 |
|---------|---------|
| PhysX 库加载失败 | 记录错误，禁用物理系统，场景继续加载 |
| 碰撞体文件不存在 | 记录警告，物理系统正常运行（无静态碰撞） |
| 碰撞体解析失败 | 记录错误，跳过该碰撞体，继续加载其他 |

### 8.2 运行时错误处理

```go
// 所有物理操作都应检查 physx 是否为 nil
func (s *PhysicsService) CheckLineOfSight(from, to Vec3f) bool {
    if s.system == nil || s.system.physx == nil {
        return true  // 物理系统未启用，默认无遮挡
    }
    // ...
}
```

### 8.3 超时处理

```go
const MaxPhysicsStepTimeMs = 50  // 单次 Step 最大耗时 50ms

func (s *PhysicsUpdateSystem) Update() {
    // ...
    stepStart := mtime.NowMilliTickWithOffset()
    stepCount := 0

    for s.accumulator >= s.fixedDeltaT {
        s.physx.Step(s.fixedDeltaT)
        s.accumulator -= s.fixedDeltaT
        stepCount++

        // 超时保护
        if mtime.NowMilliTickWithOffset()-stepStart > MaxPhysicsStepTimeMs {
            log.Warningf("[Physics] step timeout, accumulated: %f, stepped: %d",
                s.accumulator, stepCount)
            s.accumulator = 0  // 丢弃剩余累积时间
            break
        }
    }
    // ...
}
```

---

## 9. 调试支持

### 9.1 GM 命令

| 命令 | 功能 |
|------|------|
| `/physics enable` | 启用物理系统 |
| `/physics disable` | 禁用物理系统 |
| `/physics stats` | 显示性能统计 |
| `/physics debug on` | 开启调试日志 |
| `/physics raycast x y z dx dy dz` | 手动执行射线检测 |

### 9.2 PVD 调试

```go
// 连接 PhysX Visual Debugger
func (s *PhysicsUpdateSystem) ConnectPVD(host string) error {
    if s.physx == nil {
        return errors.New("physics not initialized")
    }
    return s.physx.PvdConnect(host)
}
```

### 9.3 调试日志

```go
const (
    PhysicsLogTag = "[Physics]"
)

// 在调试模式下记录详细日志
func (s *PhysicsUpdateSystem) debugLog(format string, args ...interface{}) {
    if s.debugMode {
        log.Debugf(PhysicsLogTag+" "+format, args...)
    }
}
```

---

## 10. 配置化

### 10.1 物理系统配置

**文件**: `config/physics_config.toml`

```toml
[physics]
enabled = true
fixed_timestep = 0.01667  # 60Hz
max_step_time_ms = 50     # 单帧最大物理计算时间
gravity_y = -9.81

[physics.debug]
enabled = false
pvd_host = "localhost"
log_level = "warning"

[physics.layers]
# 可配置的碰撞矩阵（可选覆盖默认值）
# player = ["static", "npc", "dynamic", "trigger"]
```

### 10.2 运行时配置修改

```go
// SetPhysicsEnabled 运行时启用/禁用物理系统
func (s *PhysicsUpdateSystem) SetPhysicsEnabled(enabled bool) {
    s.enabled = enabled
    log.Infof("[Physics] enabled=%v", enabled)
}

// SetFixedTimestep 修改固定时间步长
func (s *PhysicsUpdateSystem) SetFixedTimestep(dt float32) {
    if dt > 0 && dt < 0.1 {
        s.fixedDeltaT = dt
        log.Infof("[Physics] fixedTimestep=%f", dt)
    }
}
```

---

## 11. 多线程安全

### 11.1 当前设计

- **物理模拟**：在主线程（Worker goroutine）中执行
- **物理查询**：在主线程中执行（与模拟同一线程）
- **无并发问题**：所有物理操作在同一 goroutine 中顺序执行

### 11.2 未来扩展（可选）

如果需要将物理模拟放到独立线程：

```go
// 使用双缓冲隔离读写
type PhysicsState struct {
    positions map[uint64]Vec3f
    triggers  []TriggerEventData
}

// 物理线程写入 backBuffer，主线程读取 frontBuffer
// 每帧交换
```

**注意**：当前阶段不建议多线程化，除非性能测试表明有必要。

---

## 12. 实现计划

### Phase 1: 基础物理 (P0)

| 任务 | 说明 | 文件 |
|------|------|------|
| 扩展 RaycastResult | 添加 HitActorID | `pkg/physics/type.go` |
| 添加 Overlap 接口 | OverlapSphere/Box | `pkg/physics/physx_linux.go` |
| 启用 PhysX Linux 实现 | 取消注释、编译库 | `pkg/physics/physx_linux.go` |
| 实现 ID 映射管理 | physicsToEntity 双向映射 | `physics_system.go` |
| 实现 PhysicsUpdateSystem | 物理模拟主循环 | `physics_system.go` |
| 添加 Physx 资源到小镇初始化 | 资源初始化 | `scene_impl.go` |
| 静态碰撞体加载 | 从 JSON 加载 | `scene_impl.go` |

### Phase 2: 角色运动 (P1)

| 任务 | 说明 |
|------|------|
| CharacterControllerComp 完善 | 角色控制器组件 |
| 生命周期同步 | Entity 创建/销毁时同步物理对象 |
| 集成到 NpcMoveSystem | 替换直接位置设置 |
| 玩家运动集成 | 玩家移动走物理系统 |

### Phase 3: 视野遮挡 (P1)

| 任务 | 说明 |
|------|------|
| PhysicsService 实现 | 业务层查询接口 |
| CheckLineOfSight 实现 | 视线检测 |
| VisionSystem 集成 | 视野检测加遮挡判断 |

### Phase 4: 战斗/技能 (P2)

| 任务 | 说明 |
|------|------|
| 触发器事件处理 | Enter/Exit/Stay 回调 |
| CombatService | 攻击范围检测 |
| ProjectileSystem | 投射物系统 |
| SkillService | 技能范围检测 |

### Phase 5: 完善 (P2)

| 任务 | 说明 |
|------|------|
| GM 命令 | 调试命令支持 |
| 性能监控 | 统计和日志 |
| 配置化 | 运行时配置修改 |
| 错误处理完善 | 降级策略 |

---

## 13. 关键文件清单

| 文件 | 状态 | 说明 |
|------|------|------|
| `pkg/physics/type.go` | 修改 | 扩展 RaycastResult，添加 OverlapResult |
| `pkg/physics/physx_linux.go` | 修改 | 取消注释，添加 Overlap/RaycastWithMask |
| `ecs/com/cphysics/physics.go` | 扩展 | 添加新字段 |
| `ecs/com/cphysics/layer.go` | 新增 | 碰撞层定义（完整版） |
| `ecs/com/cphysics/character_controller.go` | 新增 | 角色控制器组件 |
| `ecs/res/physx.go` | 保持 | 物理资源 |
| `ecs/system/physics/physics_system.go` | 新增 | 物理更新系统（含 ID 映射） |
| `ecs/system/physics/physics_service.go` | 新增 | 物理查询服务 |
| `ecs/scene/scene_impl.go` | 修改 | 添加初始化 |
| `common/ecs.go` | 修改 | 注册 SystemType_Physics |
| `common/com_type.go` | 确认 | ComponentType_CharacterController 已存在 |
| `config/physics_config.toml` | 新增 | 物理系统配置 |

---

## 14. 审查修复记录

| 问题 | 修复内容 |
|------|---------|
| RaycastResult 缺少命中实体 ID | 添加 HitActorID 字段和 OverlapResult 类型 |
| 缺少 PhysicsID ↔ EntityID 映射 | 添加 physicsToEntity/entityToPhysics 双向映射 |
| 时间源不一致 | 改用 mtime.NowMilliTickWithOffset() |
| 生命周期未同步 | 添加 syncEntityLifecycle() 方法 |
| 碰撞层矩阵不完整 | 补全所有层的碰撞定义 |
| 组件使用场景不明确 | 添加组件使用场景说明表 |
| System 注册顺序不明确 | 在 ecs.go 枚举中明确位置 |
| 触发器事件缺少设计 | 添加 TriggerEventData 和分发逻辑 |
| Overlap 接口缺失 | 添加 OverlapSphere/OverlapBox 设计 |
| 坐标系未约定 | 添加坐标系约定章节 |
| 性能监控缺失 | 添加 PhysicsStats 统计 |
| 错误处理缺失 | 添加降级策略和超时处理 |
| 调试支持缺失 | 添加 GM 命令和 PVD 支持 |
| 配置化缺失 | 添加配置文件和运行时修改接口 |
| 多线程安全未说明 | 添加多线程安全章节 |
| 碰撞体数据来源未说明 | 添加数据格式和来源说明 |
