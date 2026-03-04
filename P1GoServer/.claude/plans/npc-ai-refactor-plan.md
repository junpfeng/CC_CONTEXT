# NPC AI 决策系统重构计划

## 概述

当前 NPC AI 决策系统存在明显的小镇场景耦合。虽然核心 AI 决策引擎（感知、决策、执行）已具备通用性，但场景资源管理层、系统初始化、NPC 组件层都存在小镇特定实现。通过重构这些层级的代码，可以支持新场景（如樱校、未来新增场景）的 NPC AI 功能。

**重构目标**：新增场景时，只需 ~50 行代码即可复用完整的 NPC AI 决策功能。

---

## 现状分析

### 已经通用的系统（无需修改）

| 系统 | 文件 | 说明 |
|------|------|------|
| DecisionSystem | `decision/decision.go` | 使用 `EntityList()` + `EntityType_Npc` 过滤，已通用 |
| BeingWantedSystem | `police/being_wanted_system.go` | 使用 `PlayerManager`，已通用 |

### 需要重构的系统（硬编码 TownNpcMgr）

| 系统 | 文件 | 问题行 |
|------|------|--------|
| SensorFeatureSystem | `sensor/sensor_feature.go` | 68-75 |
| NpcPoliceSystem | `police/police_system.go` | 81, 88 |
| VisionSystem | `vision/vision_system.go` | 48, 54, 66, 80 |

### 当前 Sakura 场景的问题

1. **未初始化 AI 系统**：`scene_impl.go:125-139` 中 Sakura 场景没有调用 `initNpcAISystems()`
2. **未加载导航网格**：Sakura 场景没有调用 `loadNavMesh()`
3. **代码重复**：`sakura_npc.go:70-84` 手动创建 AI 组件，未使用 `InitNpcAIComponents()`
4. **缺少警察组件**：`CreateSakuraNpc` 没有添加警察组件

---

## 重构点 #1：NPC 遍历通用化（核心）

### 优先级：高（必须首先完成）

### 当前实现位置
- `servers/scene_server/internal/ecs/system/sensor/sensor_feature.go:68-75`
- `servers/scene_server/internal/ecs/system/police/police_system.go:81,88`
- `servers/scene_server/internal/ecs/system/vision/vision_system.go:48,54,66,80`

### 问题描述

```go
// 当前代码：只能处理小镇 NPC
townMgr, ok := common.GetResourceAs[*town.TownNpcMgr](ds.Scene(), common.ResourceType_TownNpcMgr)
if !ok {
    return
}
for _, townNpc := range townMgr.NpcMap {
    // 处理 NPC...
}
```

### 重构方案

**方案 A：基于实体类型过滤（推荐）**

```go
// 重构后：处理所有场景的 NPC
npcEntities := ds.Scene().EntityListByType(common.EntityType_Npc)
for _, entity := range npcEntities {
    // 处理 NPC...
}
```

**方案 B：通用 NPC 遍历接口（如需优化性能）**

```go
// 位置：common/npc_iterator.go（新建）

// NpcIterator 通用 NPC 遍历器
type NpcIterator struct {
    scene Scene
}

func NewNpcIterator(scene Scene) *NpcIterator {
    return &NpcIterator{scene: scene}
}

// ForEach 遍历所有 NPC 实体
func (it *NpcIterator) ForEach(fn func(entity Entity)) {
    // 优先使用场景特定的 NPC 管理器（性能优化）
    switch it.scene.SceneType().(type) {
    case *TownSceneInfo:
        if townMgr, ok := GetResourceAs[*town.TownNpcMgr](it.scene, ResourceType_TownNpcMgr); ok {
            for _, npc := range townMgr.NpcMap {
                fn(npc.Entity)
            }
            return
        }
    case *SakuraSceneInfo:
        if sakuraMgr, ok := GetResourceAs[*sakura.SakuraNpcMgr](it.scene, ResourceType_SakuraNpcMgr); ok {
            for _, npc := range sakuraMgr.NpcMap {
                fn(npc.Entity)
            }
            return
        }
    }

    // 降级：通用实体遍历
    for _, entity := range it.scene.EntityListByType(EntityType_Npc) {
        fn(entity)
    }
}
```

### 需要修改的文件

1. **sensor_feature.go**
```go
// 修改 Update() 方法
func (ds *SensorFeatureSystem) Update() {
    // ... 时间检查逻辑 ...

    // 遍历所有 NPC（通用）
    npcEntities := ds.Scene().EntityListByType(common.EntityType_Npc)
    for _, entity := range npcEntities {
        ds.eventSensorFeature.GetAndUpdateFeature(entity.ID())

        // 如果有日程组件，更新日程
        if _, ok := common.GetComponentAs[*cnpc.NpcScheduleComp](
            ds.Scene(), entity.ID(), common.ComponentType_NpcSchedule); ok {
            ds.scheduleSensorFeature.TimeTick(entity.ID())
        }
    }
}
```

2. **vision_system.go**
```go
// 修改 Update() 和 UpdateVisionByProto() 方法
func (v *VisionSystem) Update() {
    npcEntities := v.Scene().EntityListByType(common.EntityType_Npc)
    for _, entity := range npcEntities {
        // 处理 NPC 视野...
    }
}
```

3. **police_system.go**
```go
// 修改 Update() 方法，使用通用警察判断
func (p *NpcPoliceSystem) Update() {
    npcEntities := p.Scene().EntityListByType(common.EntityType_Npc)
    for _, entity := range npcEntities {
        if IsNpcPolice(p.Scene(), entity) {
            p.updatePoliceLogic(entity)
        }
    }
}
```

### 工作量估计
~100 行代码改动

---

## 重构点 #2：警察角色通用判断

### 优先级：高

### 当前实现位置
- `servers/scene_server/internal/ecs/system/police/police_system.go:88`

### 问题描述

```go
// 当前代码：只能获取小镇警察
policeNpcs := townMgr.GetPoliceNpcs()  // 只在 TownNpcMgr 中存在
```

### 重构方案

```go
// 位置：common/npc_utils.go（新建）

// IsNpcPolice 判断 NPC 是否为警察
// 优先检查警察组件的 IsPolice 字段，其次检查配置
func IsNpcPolice(scene Scene, entity Entity) bool {
    // 方式1：检查警察组件标志
    policeComp, ok := GetComponentAs[*cpolice.NpcPoliceComp](
        scene, entity.ID(), ComponentType_NpcPolice)
    if ok && policeComp.IsPolice {
        return true
    }

    // 方式2：检查小镇 NPC 配置
    townNpcComp, ok := GetComponentAs[*cnpc.TownNpcComp](
        scene, entity.ID(), ComponentType_TownNpc)
    if ok {
        return townNpcComp.Cfg.GetOccupation() == config.PoliceTownNpcOccupationType
    }

    // 方式3：检查樱校 NPC 配置（如果樱校有警察）
    // sakuraNpcComp, ok := GetComponentAs[*cnpc.SakuraNpcComp](...)
    // if ok { ... }

    return false
}
```

### 工作量估计
~50 行代码改动

---

## 重构点 #3：场景 AI 系统初始化统一

### 优先级：高（当前 Sakura 场景无法使用 AI 系统）

### 当前实现位置
- `servers/scene_server/internal/ecs/scene/scene_impl.go:117-120,125-139`

### 问题描述

```go
// 当前代码：只有小镇初始化 AI 系统
case *common.TownSceneInfo:
    // ... 资源初始化 ...
    s.loadNavMesh("town")
    if err := s.initNpcAISystems(); err != nil {  // ✓ 初始化 AI 系统
        return err
    }
    npc.InitTownNpcs(s)

case *common.SakuraSceneInfo:
    // ... 资源初始化 ...
    // ✗ 没有 loadNavMesh
    // ✗ 没有 initNpcAISystems
    npc.InitSakuraNPCs(s)  // NPC 有决策组件，但系统未初始化！
```

### 重构方案

**方案 A：接口化配置（推荐）**

```go
// 位置：common/scene_info.go

// NpcAIConfigProvider 场景 NPC AI 配置接口
type NpcAIConfigProvider interface {
    GetNpcAIConfig() *SceneNpcAIConfig
}

// SceneNpcAIConfig 场景 NPC AI 配置
type SceneNpcAIConfig struct {
    EnableSensor   bool   // 启用感知系统
    EnableDecision bool   // 启用决策系统
    EnableVision   bool   // 启用视野系统
    EnablePolice   bool   // 启用警察系统
    EnableWanted   bool   // 启用被通缉系统
    NavMeshName    string // 导航网格名称（空表示不加载）
}

// TownSceneInfo 实现接口
func (t *TownSceneInfo) GetNpcAIConfig() *SceneNpcAIConfig {
    return &SceneNpcAIConfig{
        EnableSensor:   true,
        EnableDecision: true,
        EnableVision:   true,
        EnablePolice:   true,
        EnableWanted:   true,
        NavMeshName:    "town",
    }
}

// SakuraSceneInfo 实现接口
func (s *SakuraSceneInfo) GetNpcAIConfig() *SceneNpcAIConfig {
    return &SceneNpcAIConfig{
        EnableSensor:   true,
        EnableDecision: true,
        EnableVision:   true,
        EnablePolice:   false,  // 樱校暂无警察
        EnableWanted:   false,
        NavMeshName:    "sakura",
    }
}
```

```go
// 位置：scene_impl.go

func (s *scene) init() error {
    // ... 公共资源初始化 ...

    switch sceneType := s.sceneType.(type) {
    case *common.TownSceneInfo:
        if err := s.townRosurceInit(saveInfo); err != nil {
            return err
        }
        npc.InitTownNpcs(s)

    case *common.SakuraSceneInfo:
        if err := s.sakuraResourceInit(saveInfo); err != nil {
            return err
        }
        npc.InitSakuraNPCs(s)
    }

    // 统一初始化 NPC AI 系统（根据配置）
    if err := s.initNpcAISystemsFromConfig(); err != nil {
        return err
    }

    // ... 其他初始化 ...
}

func (s *scene) initNpcAISystemsFromConfig() error {
    // 获取配置（通过接口）
    provider, ok := s.sceneType.(common.NpcAIConfigProvider)
    if !ok {
        return nil  // 该场景不支持 NPC AI
    }

    cfg := provider.GetNpcAIConfig()
    if cfg == nil {
        return nil
    }

    // 加载导航网格
    if cfg.NavMeshName != "" {
        s.loadNavMesh(cfg.NavMeshName)
    }

    // 按需初始化系统
    if cfg.EnableSensor {
        if err := s.AddSystem(sensor.NewSensorFeatureSystem(s)); err != nil {
            return errors.New("add sensor system error: " + err.Error())
        }
    }

    if cfg.EnableDecision {
        if err := s.AddSystem(decision.NewDecisionSystem(s)); err != nil {
            return errors.New("add decision system error: " + err.Error())
        }
    }

    if cfg.EnableVision {
        if err := s.AddSystem(vision.NewVisionSystem(s)); err != nil {
            return errors.New("add vision system error: " + err.Error())
        }
    }

    if cfg.EnablePolice {
        if err := s.AddSystem(police.NewNpcPoliceSystem(s)); err != nil {
            return errors.New("add police system error: " + err.Error())
        }
    }

    if cfg.EnableWanted {
        if err := s.AddSystem(police.NewBeingWantedSystem(s)); err != nil {
            return errors.New("add being wanted system error: " + err.Error())
        }
    }

    return nil
}
```

### 工作量估计
~80 行代码改动

---

## 重构点 #4：NPC 创建流程统一

### 优先级：中

### 当前实现位置
- `servers/scene_server/internal/net_func/npc/town_npc.go:46-134`
- `servers/scene_server/internal/net_func/npc/sakura_npc.go:24-101`
- `servers/scene_server/internal/net_func/npc/common.go:261-306`

### 问题描述

| 功能 | town_npc.go | sakura_npc.go |
|------|-------------|---------------|
| 基础 NPC 创建 | CreateNpcFromConfig | CreateNpcFromConfig |
| 场景特定组件 | TownNpcComp | SakuraNpcComp |
| 日程组件 | ✓ | ✓ |
| 对话组件 | ✓ | ✓ |
| AI 决策组件 | InitNpcAIComponents() | 手动创建（重复代码） |
| 视野组件 | InitNpcAIComponents() | 手动创建 |
| 警察组件 | InitNpcAIComponents() | ✗ 缺失 |
| 移动速度 | 硬编码 1 | cfg.GetRunSpeed() |

### 重构方案

```go
// 位置：net_func/npc/common.go（扩展）

// CreateSceneNpcParam 场景 NPC 创建参数
type CreateSceneNpcParam struct {
    Scene              common.Scene
    NpcCfgId           int32
    Position           trans.Vec3
    Rotation           trans.Vec3

    // 场景特定配置
    SceneSpecificComp  common.Component   // TownNpcComp 或 SakuraNpcComp
    ScheduleCfg        *confignpcschedule.NpcSchedule
    GssStateTransCfg   interface{}
    GSSTempID          string

    // 可选配置
    RunSpeed           float32  // 0 表示使用基础速度
    IncludePoliceComp  bool     // 是否添加警察组件
    PoliceConfig       *cpolice.PoliceConfig // 警察配置（nil 使用默认）
}

// CreateSceneNpc 通用场景 NPC 创建函数
func CreateSceneNpc(param *CreateSceneNpcParam) common.Entity {
    s := param.Scene

    // 1. 基础 NPC 创建
    entity := CreateNpcFromConfig(s, param.NpcCfgId, param.Position, param.Rotation)
    if entity == nil {
        return nil
    }

    // 2. 添加场景特定组件
    if param.SceneSpecificComp != nil {
        entity.AddComponent(param.SceneSpecificComp)
    }

    // 3. 添加日程组件
    if param.ScheduleCfg != nil {
        scheduleComp := cnpc.NewNpcScheduleComp(param.ScheduleCfg)
        if param.GssStateTransCfg != nil {
            scheduleComp.SetGssStateTransCfg(param.GssStateTransCfg)
        }
        entity.AddComponent(scheduleComp)
    }

    // 4. 添加对话组件
    dialogComp := cdialog.NewDialogComp()
    entity.AddComponent(dialogComp)

    // 5. 初始化 AI 组件（决策 + 视野 + 警察）
    if !InitNpcAIComponents(s, entity, param.GSSTempID) {
        s.Errorf("[CreateSceneNpc] init AI components failed, entity_id=%v", entity.ID())
        return entity  // 返回不带 AI 的实体
    }

    // 6. 设置移动速度
    if param.RunSpeed > 0 {
        if npcMoveComp, ok := common.GetEntityComponentAs[*cnpc.NpcMoveComp](
            entity, common.ComponentType_NpcMove); ok {
            npcMoveComp.RunSpeed = param.RunSpeed
        }
    }

    return entity
}

// 修改后的 CreateTownNpc
func CreateTownNpc(s common.Scene, cfg *config.CfgTownNpc) common.Entity {
    // ... 获取配置 ...

    return CreateSceneNpc(&CreateSceneNpcParam{
        Scene:             s,
        NpcCfgId:          cfg.GetBaseNpcId(),
        SceneSpecificComp: cnpc.NewTownNpcComp(cfg),
        ScheduleCfg:       scheduleCfg,
        GssStateTransCfg:  stateTrans,
        GSSTempID:         cfg.GetStateTrans(),
        RunSpeed:          1,
        IncludePoliceComp: true,
    })
}

// 修改后的 CreateSakuraNpc
func CreateSakuraNpc(s common.Scene, cfg *config.CfgSakuraNpc) common.Entity {
    // ... 获取配置 ...

    return CreateSceneNpc(&CreateSceneNpcParam{
        Scene:             s,
        NpcCfgId:          cfg.GetBaseNpcId(),
        SceneSpecificComp: cnpc.NewSakuraNpcComp(cfg),
        ScheduleCfg:       scheduleCfg,
        GssStateTransCfg:  stateTrans,
        GSSTempID:         cfg.GetStateTrans(),
        RunSpeed:          cfg.GetRunSpeed(),
        IncludePoliceComp: false,  // 樱校暂无警察
    })
}
```

### 工作量估计
~150 行代码改动

---

## 重构点 #5：InitNpcAIComponents 增强

### 优先级：中

### 当前实现位置
- `servers/scene_server/internal/net_func/npc/common.go:261-306`

### 问题描述

当前 `InitNpcAIComponents` 始终添加警察组件，但某些场景（如樱校）可能不需要。

### 重构方案

```go
// 位置：net_func/npc/common.go

// InitNpcAIComponentsParam AI 组件初始化参数
type InitNpcAIComponentsParam struct {
    Scene             common.Scene
    Entity            common.Entity
    GSSTempID         string
    IncludePoliceComp bool                    // 是否添加警察组件
    PoliceConfig      *cpolice.PoliceConfig   // 警察配置（nil 使用全局配置）
}

// InitNpcAIComponentsWithParam 带参数的 AI 组件初始化
func InitNpcAIComponentsWithParam(param *InitNpcAIComponentsParam) bool {
    s := param.Scene
    entity := param.Entity
    entityID := entity.ID()

    // 1. 创建 AI 决策组件
    decisionComp, err := caidecision.CreateAIDecisionComp(
        &decisionexec.Executor{Scene: s}, s, entityID, param.GSSTempID)
    if err != nil {
        s.Errorf("[InitNpcAIComponents] create decision comp failed, entity_id=%v, err=%v", entityID, err)
        return false
    }
    if !entity.AddComponent(decisionComp) {
        s.Errorf("[InitNpcAIComponents] add decision comp failed, entity_id=%v", entityID)
        return false
    }

    // 2. 创建视野组件
    visionComp := cvision.NewVisionComp(1)
    entity.AddComponent(visionComp)

    // 3. 可选：创建警察组件
    if param.IncludePoliceComp {
        policeCfg := param.PoliceConfig
        if policeCfg == nil {
            policeCfg = getDefaultPoliceConfig()
        }
        policeComp := cpolice.NewNpcPoliceComp(policeCfg)
        entity.AddComponent(policeComp)
    }

    s.Debugf("[InitNpcAIComponents] success, entity_id=%v, template=%v, police=%v",
        entityID, param.GSSTempID, param.IncludePoliceComp)
    return true
}

// 保持向后兼容
func InitNpcAIComponents(s common.Scene, entity common.Entity, gssTempID string) bool {
    return InitNpcAIComponentsWithParam(&InitNpcAIComponentsParam{
        Scene:             s,
        Entity:            entity,
        GSSTempID:         gssTempID,
        IncludePoliceComp: true,
    })
}
```

### 工作量估计
~50 行代码改动

---

## 实施路线图

### 第一阶段：解决 Sakura 场景无法使用 AI 系统的问题

| 序号 | 任务 | 优先级 | 工作量 |
|------|------|--------|--------|
| 1.1 | 重构点 #1：sensor_feature.go 通用化 | 高 | ~30 行 |
| 1.2 | 重构点 #1：vision_system.go 通用化 | 高 | ~30 行 |
| 1.3 | 重构点 #1：police_system.go 通用化 | 高 | ~20 行 |
| 1.4 | 重构点 #2：新增 IsNpcPolice() 函数 | 高 | ~30 行 |
| 1.5 | 重构点 #3：Sakura 场景初始化 AI 系统 | 高 | ~20 行 |

**阶段产出**：Sakura 场景的 NPC 能使用 AI 决策功能

### 第二阶段：统一初始化流程

| 序号 | 任务 | 优先级 | 工作量 |
|------|------|--------|--------|
| 2.1 | 重构点 #3：定义 NpcAIConfigProvider 接口 | 中 | ~40 行 |
| 2.2 | 重构点 #3：实现 initNpcAISystemsFromConfig() | 中 | ~50 行 |
| 2.3 | 重构点 #3：scene_impl.go 统一调用 | 中 | ~20 行 |

**阶段产出**：新场景只需实现接口即可启用 AI 系统

### 第三阶段：统一 NPC 创建流程

| 序号 | 任务 | 优先级 | 工作量 |
|------|------|--------|--------|
| 3.1 | 重构点 #4：实现 CreateSceneNpc() | 中 | ~80 行 |
| 3.2 | 重构点 #4：重构 CreateTownNpc() | 中 | ~20 行 |
| 3.3 | 重构点 #4：重构 CreateSakuraNpc() | 中 | ~20 行 |
| 3.4 | 重构点 #5：增强 InitNpcAIComponents() | 低 | ~50 行 |

**阶段产出**：NPC 创建代码去重，新场景快速适配

---

## 新场景适配清单

完成重构后，新增场景的步骤：

### 步骤 1：定义场景信息（实现接口）

```go
// common/scene_info.go
type NewSceneInfo struct {
    // ... 场景字段 ...
}

func (n *NewSceneInfo) GetNpcAIConfig() *SceneNpcAIConfig {
    return &SceneNpcAIConfig{
        EnableSensor:   true,
        EnableDecision: true,
        EnableVision:   true,
        EnablePolice:   false,  // 根据需求配置
        EnableWanted:   false,
        NavMeshName:    "new_scene",
    }
}
```

### 步骤 2：定义场景特定 NPC 组件

```go
// ecs/com/cnpc/new_scene_npc.go
type NewSceneNpcComp struct {
    common.ComponentBase
    Cfg *config.CfgNewSceneNpc
}

func (c *NewSceneNpcComp) Type() common.ComponentType {
    return common.ComponentType_NewSceneNpc
}
```

### 步骤 3：定义场景特定 NPC 管理器

```go
// ecs/res/new_scene/new_scene_npc.go
type NewSceneNpcMgr struct {
    common.ResourceBase
    NpcMap map[int32]*NewSceneNpcInfo
}
```

### 步骤 4：实现 NPC 创建函数

```go
// net_func/npc/new_scene_npc.go
func CreateNewSceneNpc(s common.Scene, cfg *config.CfgNewSceneNpc) common.Entity {
    scheduleCfg := config.GetNpcSchedule(cfg.GetSchedule())
    stateTrans, _ := configNpcGssBrain.CfgMgr.GetConfig(cfg.GetStateTrans())

    return CreateSceneNpc(&CreateSceneNpcParam{
        Scene:             s,
        NpcCfgId:          cfg.GetBaseNpcId(),
        SceneSpecificComp: cnpc.NewNewSceneNpcComp(cfg),
        ScheduleCfg:       scheduleCfg,
        GssStateTransCfg:  stateTrans,
        GSSTempID:         cfg.GetStateTrans(),
        RunSpeed:          cfg.GetRunSpeed(),
        IncludePoliceComp: false,
    })
}

func InitNewSceneNpcs(s common.Scene) {
    cfgMap := config.GetCfgMapNewSceneNpc()
    for _, cfg := range cfgMap {
        CreateNewSceneNpc(s, cfg)
    }
}
```

### 步骤 5：在场景初始化中注册

```go
// scene_impl.go init()
case *common.NewSceneInfo:
    if err := s.newSceneResourceInit(saveInfo); err != nil {
        return err
    }
    npc.InitNewSceneNpcs(s)
```

**总代码量**：~50-80 行（不含配置和组件定义）

---

## 工作量总结

| 阶段 | 重构点 | 代码改动 |
|------|--------|----------|
| 第一阶段 | #1, #2, #3（部分） | ~130 行 |
| 第二阶段 | #3（完整） | ~110 行 |
| 第三阶段 | #4, #5 | ~170 行 |
| **总计** | - | **~410 行** |

---

## 测试策略

| 测试项目 | 测试方法 | 验收标准 |
|----------|----------|----------|
| 小镇 NPC AI | 回归测试 | 与重构前行为一致 |
| 樱校 NPC AI | 新功能测试 | 感知、决策、视野系统正常工作 |
| 新场景适配 | 集成测试 | 按清单完成，NPC AI 功能正常 |
| 性能 | 性能测试 | NPC 遍历时间 <5ms/帧 |

---

## 风险评估

| 风险 | 等级 | 缓解措施 |
|------|------|----------|
| 回归问题 | 中 | 分阶段实施，每阶段完成后充分测试 |
| 性能下降 | 低 | 保留 NPC 管理器优化路径（方案 B） |
| 接口变更 | 低 | 保持向后兼容（如 InitNpcAIComponents） |
