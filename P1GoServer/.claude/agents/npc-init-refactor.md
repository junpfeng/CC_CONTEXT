# NPC Init Refactor Agent

## 职责

统一场景 NPC AI 系统初始化流程，实现接口化配置。

## 前置条件

- 阅读计划文件：`.claude/plans/npc-ai-refactor-plan.md`
- 阅读 ECS 规范：`.claude/rules/ecs-architecture.md`
- 完成 npc-system-refactor 任务（任务 1.1-1.4）

---

## 任务 1.5：Sakura 场景初始化 AI 系统（临时方案）

### 目标文件
`servers/scene_server/internal/ecs/scene/scene_impl.go`

### 修改内容

在 `case *common.SakuraSceneInfo:` 中添加 AI 系统初始化调用。

### 修改前
```go
case *common.SakuraSceneInfo:
    saveInfo := s.dbEntry.GetSakuraInfo(sceneType.OwnerRole)
    if saveInfo == nil {
        s.Error("get sakura info from db failed")
        return errors.New("get sakura info from mongo failed")
    }

    err := s.sakuraResourceInit(saveInfo)
    if err != nil {
        return err
    }

    // 初始化npc
    npc.InitSakuraNPCs(s)
```

### 修改后
```go
case *common.SakuraSceneInfo:
    saveInfo := s.dbEntry.GetSakuraInfo(sceneType.OwnerRole)
    if saveInfo == nil {
        s.Error("get sakura info from db failed")
        return errors.New("get sakura info from mongo failed")
    }

    err := s.sakuraResourceInit(saveInfo)
    if err != nil {
        return err
    }

    // 加载樱校导航网格
    s.loadNavMesh("sakura")

    // 初始化 NPC AI 相关系统（感知、决策、视野）
    // 注意：樱校暂不启用警察系统
    if err := s.initSakuraNpcAISystems(); err != nil {
        return err
    }

    // 初始化npc
    npc.InitSakuraNPCs(s)
```

### 新增方法

```go
// initSakuraNpcAISystems 初始化樱校 NPC AI 相关系统
// 与小镇不同，樱校暂不启用警察系统和被通缉系统
func (s *scene) initSakuraNpcAISystems() error {
    // 添加感知系统
    sensorFeatureSystem := sensor.NewSensorFeatureSystem(s)
    if err := s.AddSystem(sensorFeatureSystem); err != nil {
        return errors.New("add sensor feature system error: " + err.Error())
    }

    // 添加 AI 决策系统
    decisionSystem := decision.NewDecisionSystem(s)
    if err := s.AddSystem(decisionSystem); err != nil {
        return errors.New("add decision system error: " + err.Error())
    }

    // 添加视野系统
    visionSystem := vision.NewVisionSystem(s)
    if err := s.AddSystem(visionSystem); err != nil {
        return errors.New("add vision system error: " + err.Error())
    }

    // 樱校暂不添加警察系统和被通缉系统
    // 如需启用，取消以下注释：
    // policeSystem := police.NewNpcPoliceSystem(s)
    // if err := s.AddSystem(policeSystem); err != nil {
    //     return errors.New("add police system error: " + err.Error())
    // }
    // beingWantedSystem := police.NewBeingWantedSystem(s)
    // if err := s.AddSystem(beingWantedSystem); err != nil {
    //     return errors.New("add being wanted system error: " + err.Error())
    // }

    return nil
}
```

### 验证
```bash
make build APPS='scene_server'
```

---

## 任务 2.1：定义 NpcAIConfigProvider 接口

### 目标文件
`servers/scene_server/internal/common/scene_info.go`（或合适的位置）

### 新增内容

```go
// SceneNpcAIConfig 场景 NPC AI 配置
type SceneNpcAIConfig struct {
    EnableSensor   bool   // 启用感知系统
    EnableDecision bool   // 启用决策系统
    EnableVision   bool   // 启用视野系统
    EnablePolice   bool   // 启用警察系统
    EnableWanted   bool   // 启用被通缉系统
    NavMeshName    string // 导航网格名称（空表示不加载）
}

// NpcAIConfigProvider 场景 NPC AI 配置提供者接口
// 实现此接口的场景类型可以自动初始化 NPC AI 系统
type NpcAIConfigProvider interface {
    GetNpcAIConfig() *SceneNpcAIConfig
}
```

### TownSceneInfo 实现接口

```go
// GetNpcAIConfig 返回小镇场景的 NPC AI 配置
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
```

### SakuraSceneInfo 实现接口

```go
// GetNpcAIConfig 返回樱校场景的 NPC AI 配置
func (s *SakuraSceneInfo) GetNpcAIConfig() *SceneNpcAIConfig {
    return &SceneNpcAIConfig{
        EnableSensor:   true,
        EnableDecision: true,
        EnableVision:   true,
        EnablePolice:   false,  // 樱校暂无警察
        EnableWanted:   false,  // 樱校暂无通缉系统
        NavMeshName:    "sakura",
    }
}
```

### 验证
```bash
make build APPS='scene_server'
```

---

## 任务 2.2：实现 initNpcAISystemsFromConfig()

### 目标文件
`servers/scene_server/internal/ecs/scene/scene_impl.go`

### 新增方法

```go
// initNpcAISystemsFromConfig 根据场景配置初始化 NPC AI 系统
// 如果场景类型实现了 NpcAIConfigProvider 接口，则根据配置初始化相应系统
func (s *scene) initNpcAISystemsFromConfig() error {
    // 检查场景类型是否实现了配置接口
    provider, ok := s.sceneType.(common.NpcAIConfigProvider)
    if !ok {
        // 该场景不支持 NPC AI 系统
        return nil
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
        sensorFeatureSystem := sensor.NewSensorFeatureSystem(s)
        if err := s.AddSystem(sensorFeatureSystem); err != nil {
            return errors.New("add sensor feature system error: " + err.Error())
        }
    }

    if cfg.EnableDecision {
        decisionSystem := decision.NewDecisionSystem(s)
        if err := s.AddSystem(decisionSystem); err != nil {
            return errors.New("add decision system error: " + err.Error())
        }
    }

    if cfg.EnableVision {
        visionSystem := vision.NewVisionSystem(s)
        if err := s.AddSystem(visionSystem); err != nil {
            return errors.New("add vision system error: " + err.Error())
        }
    }

    if cfg.EnablePolice {
        policeSystem := police.NewNpcPoliceSystem(s)
        if err := s.AddSystem(policeSystem); err != nil {
            return errors.New("add police system error: " + err.Error())
        }
    }

    if cfg.EnableWanted {
        beingWantedSystem := police.NewBeingWantedSystem(s)
        if err := s.AddSystem(beingWantedSystem); err != nil {
            return errors.New("add being wanted system error: " + err.Error())
        }
    }

    return nil
}
```

### 验证
```bash
make build APPS='scene_server'
```

---

## 任务 2.3：scene_impl.go 统一调用

### 目标文件
`servers/scene_server/internal/ecs/scene/scene_impl.go`

### 修改内容

1. 删除各场景 case 中的 `loadNavMesh()` 和 `initNpcAISystems()` 调用
2. 在 switch 语句后统一调用 `initNpcAISystemsFromConfig()`

### 修改后的 init() 方法结构

```go
func (s *scene) init() error {
    // ... 公共资源初始化 ...

    switch sceneType := s.sceneType.(type) {
    case *common.TownSceneInfo:
        // 数据加载和资源初始化
        saveInfo := s.dbEntry.GetTownIfno(sceneType.OwnerRole)
        // ...
        err := s.townRosurceInit(saveInfo)
        if err != nil {
            return err
        }
        // 初始化 NPC（在系统初始化之前，因为系统需要遍历 NPC）
        npc.InitTownNpcs(s)
        timeMgr.LoadData(saveInfo.TimeData)

    case *common.SakuraSceneInfo:
        // 数据加载和资源初始化
        saveInfo := s.dbEntry.GetSakuraInfo(sceneType.OwnerRole)
        // ...
        err := s.sakuraResourceInit(saveInfo)
        if err != nil {
            return err
        }
        // 初始化 NPC
        npc.InitSakuraNPCs(s)
    }

    // 统一初始化 NPC AI 系统（根据配置）
    if err := s.initNpcAISystemsFromConfig(); err != nil {
        return err
    }

    // ... 其他初始化 ...
}
```

### 删除的代码

1. 删除 `initNpcAISystems()` 方法（被 `initNpcAISystemsFromConfig()` 替代）
2. 删除 `initSakuraNpcAISystems()` 方法（如果在任务 1.5 中创建了）
3. 删除各 case 中的 `s.loadNavMesh()` 调用
4. 删除各 case 中的 `s.initNpcAISystems()` 调用

### 验证
```bash
make build APPS='scene_server'
```

---

## 完成检查

- [ ] NpcAIConfigProvider 接口已定义
- [ ] SceneNpcAIConfig 结构体已定义
- [ ] TownSceneInfo 实现了 GetNpcAIConfig()
- [ ] SakuraSceneInfo 实现了 GetNpcAIConfig()
- [ ] initNpcAISystemsFromConfig() 方法已实现
- [ ] scene_impl.go 统一调用 initNpcAISystemsFromConfig()
- [ ] 删除了冗余代码（旧的 initNpcAISystems 等）
- [ ] 所有文件编译通过
