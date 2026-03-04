# NPC Creation Refactor Agent

## 职责

统一 NPC 创建流程，消除代码重复，支持新场景快速适配。

## 前置条件

- 阅读计划文件：`.claude/plans/npc-ai-refactor-plan.md`
- 完成 npc-system-refactor 任务
- 完成 npc-init-refactor 任务

---

## 任务 3.1：实现 CreateSceneNpc()

### 目标文件
`servers/scene_server/internal/net_func/npc/common.go`

### 新增内容

```go
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
}

// CreateSceneNpc 通用场景 NPC 创建函数
// 统一了小镇、樱校等场景的 NPC 创建流程
func CreateSceneNpc(param *CreateSceneNpcParam) common.Entity {
    s := param.Scene

    // 1. 基础 NPC 创建
    entity := CreateNpcFromConfig(s, param.NpcCfgId, param.Position, param.Rotation)
    if entity == nil {
        s.Errorf("[CreateSceneNpc] create base npc failed, npc_cfg_id=%v", param.NpcCfgId)
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

    // 5. 初始化 AI 组件
    if param.GSSTempID != "" {
        if !InitNpcAIComponentsWithParam(&InitNpcAIComponentsParam{
            Scene:             s,
            Entity:            entity,
            GSSTempID:         param.GSSTempID,
            IncludePoliceComp: param.IncludePoliceComp,
        }) {
            s.Errorf("[CreateSceneNpc] init AI components failed, entity_id=%v, npc_cfg_id=%v",
                entity.ID(), param.NpcCfgId)
            // 返回不带 AI 的实体，让调用方决定如何处理
            return entity
        }
    }

    // 6. 设置移动速度
    if param.RunSpeed > 0 {
        npcMoveComp, ok := common.GetEntityComponentAs[*cnpc.NpcMoveComp](
            entity, common.ComponentType_NpcMove)
        if ok {
            npcMoveComp.RunSpeed = param.RunSpeed
        }
    }

    s.Debugf("[CreateSceneNpc] success, entity_id=%v, npc_cfg_id=%v, template=%v",
        entity.ID(), param.NpcCfgId, param.GSSTempID)

    return entity
}
```

### 需要添加的 import

```go
import (
    confignpcschedule "common/config/config_npc_schedule"
    "mp/servers/scene_server/internal/ecs/com/cdialog"
    // ... 其他已有的 import
)
```

### 验证
```bash
make build APPS='scene_server'
```

---

## 任务 3.2：重构 CreateTownNpc()

### 目标文件
`servers/scene_server/internal/net_func/npc/town_npc.go`

### 修改内容

使用 CreateSceneNpc() 替代现有的手动创建逻辑。

### 修改后

```go
func CreateTownNpc(s common.Scene, cfg *config.CfgTownNpc) common.Entity {
    townNpcMgr, ok := common.GetResourceAs[*town.TownNpcMgr](s, common.ResourceType_TownNpcMgr)
    if !ok {
        s.Error("[CreateTownNpc] 获取小镇NPC管理器失败")
        return nil
    }

    scheduleCfg := config.GetNpcSchedule(cfg.GetSchedule())
    if scheduleCfg == nil {
        s.Errorf("[CreateTownNpc] 获取NPC日程配置失败, npc_cfg_id=%v", cfg.GetId())
        return nil
    }

    // 读取状态转换配置
    stateTransCfgFileName := cfg.GetStateTrans()
    stateTrans, ok := configNpcGssBrain.CfgMgr.GetConfig(stateTransCfgFileName)
    if !ok || stateTrans == nil {
        s.Errorf("[CreateTownNpc] 获取状态转换配置失败, npc_cfg_id=%v, state_trans=%v",
            cfg.GetId(), stateTransCfgFileName)
        return nil
    }

    // 使用通用创建函数
    entity := CreateSceneNpc(&CreateSceneNpcParam{
        Scene:             s,
        NpcCfgId:          cfg.GetBaseNpcId(),
        Position:          trans.Vec3{X: 0, Y: 0, Z: 0},
        Rotation:          trans.Vec3{X: 0, Y: 0, Z: 0},
        SceneSpecificComp: cnpc.NewTownNpcComp(cfg),
        ScheduleCfg:       scheduleCfg,
        GssStateTransCfg:  stateTrans,
        GSSTempID:         stateTransCfgFileName,
        RunSpeed:          1,  // 小镇 NPC 移动速度
        IncludePoliceComp: true,
    })

    if entity == nil {
        s.Errorf("[CreateTownNpc] 创建NPC失败, npc_cfg_id=%v", cfg.GetId())
        return nil
    }

    // 添加到小镇 NPC 管理器
    townNpcMgr.AddNpc(cfg, scheduleCfg, entity)

    s.Infof("[CreateTownNpc] success, entity_id=%v, npc_cfg_id=%v", entity.ID(), cfg.GetId())

    return entity
}
```

### 可以删除的代码

删除原有的手动创建逻辑（约 50-60 行）：
- 手动创建日程组件
- 手动创建对话组件
- 调用 InitNpcAIComponents()
- 手动设置移动速度

### 验证
```bash
make build APPS='scene_server'
```

---

## 任务 3.3：重构 CreateSakuraNpc()

### 目标文件
`servers/scene_server/internal/net_func/npc/sakura_npc.go`

### 修改内容

使用 CreateSceneNpc() 替代现有的手动创建逻辑。

### 修改后

```go
func CreateSakuraNpc(s common.Scene, cfg *config.CfgSakuraNpc) common.Entity {
    sakuraNpcMgr, ok := common.GetResourceAs[*sakura.SakuraNpcMgr](s, common.ResourceType_SakuraNpcMgr)
    if !ok {
        s.Error("[CreateSakuraNpc] 获取樱校NPC管理器失败")
        return nil
    }

    scheduleCfg := config.GetNpcSchedule(cfg.GetSchedule())
    if scheduleCfg == nil {
        s.Errorf("[CreateSakuraNpc] 获取NPC日程配置失败, npc_cfg_id=%v", cfg.GetId())
        return nil
    }

    // 读取状态转换配置
    stateTransCfgFileName := cfg.GetStateTrans()
    stateTrans, ok := configNpcGssBrain.CfgMgr.GetConfig(stateTransCfgFileName)
    if !ok || stateTrans == nil {
        s.Errorf("[CreateSakuraNpc] 获取状态转换配置失败, npc_cfg_id=%v, state_trans=%v",
            cfg.GetId(), stateTransCfgFileName)
        return nil
    }

    // 使用通用创建函数
    entity := CreateSceneNpc(&CreateSceneNpcParam{
        Scene:             s,
        NpcCfgId:          cfg.GetBaseNpcId(),
        Position:          trans.Vec3{X: 0, Y: 0, Z: 0},
        Rotation:          trans.Vec3{X: 0, Y: 0, Z: 0},
        SceneSpecificComp: cnpc.NewSakuraNpcComp(cfg),
        ScheduleCfg:       scheduleCfg,
        GssStateTransCfg:  stateTrans,
        GSSTempID:         stateTransCfgFileName,
        RunSpeed:          cfg.GetRunSpeed(),
        IncludePoliceComp: false,  // 樱校暂无警察
    })

    if entity == nil {
        s.Errorf("[CreateSakuraNpc] 创建NPC失败, npc_cfg_id=%v", cfg.GetId())
        return nil
    }

    // 添加到樱校 NPC 管理器
    sakuraNpcMgr.AddNpc(cfg, scheduleCfg, entity)

    s.Infof("[CreateSakuraNpc] success, entity_id=%v, npc_cfg_id=%v", entity.ID(), cfg.GetId())

    return entity
}
```

### 可以删除的 import

```go
// 删除以下 import（如果不再使用）
"mp/servers/scene_server/internal/ecs/com/caidecision"
"mp/servers/scene_server/internal/ecs/com/cvision"
decisionexec "mp/servers/scene_server/internal/ecs/system/decision"
```

### 验证
```bash
make build APPS='scene_server'
```

---

## 任务 3.4：增强 InitNpcAIComponents()

### 目标文件
`servers/scene_server/internal/net_func/npc/common.go`

### 新增内容

```go
// InitNpcAIComponentsParam AI 组件初始化参数
type InitNpcAIComponentsParam struct {
    Scene             common.Scene
    Entity            common.Entity
    GSSTempID         string
    IncludePoliceComp bool  // 是否添加警察组件
}

// InitNpcAIComponentsWithParam 带参数的 AI 组件初始化
// 支持可选添加警察组件
func InitNpcAIComponentsWithParam(param *InitNpcAIComponentsParam) bool {
    s := param.Scene
    entity := param.Entity
    entityID := entity.ID()

    // 1. 创建 AI 决策组件
    decisionComp, err := caidecision.CreateAIDecisionComp(
        &decisionexec.Executor{Scene: s}, s, entityID, param.GSSTempID)
    if err != nil {
        s.Errorf("[InitNpcAIComponents] create decision comp failed, entity_id=%v, err=%v",
            entityID, err)
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
        policeCfg := getDefaultPoliceConfig()
        policeComp := cpolice.NewNpcPoliceComp(policeCfg)
        entity.AddComponent(policeComp)
    }

    s.Debugf("[InitNpcAIComponents] success, entity_id=%v, template=%v, include_police=%v",
        entityID, param.GSSTempID, param.IncludePoliceComp)

    return true
}

// getDefaultPoliceConfig 获取默认警察配置（从全局配置读取）
func getDefaultPoliceConfig() *cpolice.PoliceConfig {
    policeCfg := cpolice.DefaultPoliceConfig()

    policeCfg.NearDistance = float32(config.CfgServerSetting.TheAccumulationRateOfSuspiciousValuesNear.X)
    policeCfg.ZeroDistace = float32(config.CfgServerSetting.TheAccumulationRateOfSuspiciousValuesNear.Y)
    policeCfg.MaxIncrement = config.CfgServerSetting.TheAccumulationRateOfSuspiciousValuesNear.Z

    policeCfg.MidDistance = float32(config.CfgServerSetting.TheAccumulationRateOfSuspiciousValuesMiddle.X)
    policeCfg.MidIncrement = config.CfgServerSetting.TheAccumulationRateOfSuspiciousValuesMiddle.Z

    policeCfg.FarDistance = float32(config.CfgServerSetting.TheAccumulationRateOfSuspiciousValuesFar.X)
    policeCfg.FarIncrement = config.CfgServerSetting.TheAccumulationRateOfSuspiciousValuesFar.Z

    return policeCfg
}

// InitNpcAIComponents 初始化 NPC AI 相关组件（向后兼容）
// 包括：AI 决策组件、视野组件、警察组件
// 保持原有签名，默认包含警察组件
func InitNpcAIComponents(s common.Scene, entity common.Entity, gssTempID string) bool {
    return InitNpcAIComponentsWithParam(&InitNpcAIComponentsParam{
        Scene:             s,
        Entity:            entity,
        GSSTempID:         gssTempID,
        IncludePoliceComp: true,  // 保持向后兼容
    })
}
```

### 验证
```bash
make build APPS='scene_server'
```

---

## 完成检查

- [ ] CreateSceneNpcParam 结构体已定义
- [ ] CreateSceneNpc() 函数已实现
- [ ] CreateTownNpc() 使用 CreateSceneNpc()
- [ ] CreateSakuraNpc() 使用 CreateSceneNpc()
- [ ] InitNpcAIComponentsParam 结构体已定义
- [ ] InitNpcAIComponentsWithParam() 函数已实现
- [ ] InitNpcAIComponents() 保持向后兼容
- [ ] getDefaultPoliceConfig() 函数已实现
- [ ] 删除了重复代码
- [ ] 所有文件编译通过
- [ ] 日志符合规范
