# 大世界动物系统遗留任务 — 设计方案

> 2026-03-24，基于验收遗留任务清单

## 1. 需求回顾

| 优先级 | 任务 | 核心问题 |
|--------|------|----------|
| P0 | BtTickSystem 集成 | 大世界无 BtTickSystem，动物 AI 不 tick |
| P1 | 客户端 Follow 表现 | Dog Follow 不移动（依赖 P0） |
| P1 | 背包与喂食物品 | 无背包 UI，无法获取/使用食物 |
| P2 | 交互闭环 | HoldComp 依赖，大世界无手持 UI |
| P2 | Bird 飞行高度 | Y 坐标未升空（依赖 P0） |

## 2. 架构设计

### 2.1 P0: CitySceneInfo 实现 NpcAIConfigProvider

**文件**: `P1GoServer/servers/scene_server/internal/common/scene_type.go`

```go
func (csi *CitySceneInfo) GetNpcAIConfig() *SceneNpcAIConfig {
    return &SceneNpcAIConfig{
        EnableDecision: true,  // 仅启用决策系统（BtTickSystem）
        // 其他全部 false：大世界不需要 Sensor/Vision/Police/Wanted/Scenario
        // NavMeshName 为空：动物移动使用直线 fallback
    }
}
```

**文件**: `P1GoServer/servers/scene_server/internal/ecs/scene/scene_impl.go`

在通用路径的 `initAnimals()` 调用前，增加 `initNpcAISystemsFromConfig()` 调用。
`initNpcAISystemsFromConfig` 内部增加防重复注册保护（检查 BtTickSystem 是否已存在）。

**影响分析**:
- Town 场景：已在 case 块内调用过，通用路径的二次调用被防重复保护跳过，无影响
- City 场景：首次调用，创建 BtTickSystem，动物 AI 开始 tick
- 性能：BtTickSystem.Update 仅遍历 EntityList 中有 SceneNpcComp 的实体，大世界只有动物，开销极小

### 2.2 P1: Follow 表现（自动解决）

P0 完成后，服务器 `AnimalFollowHandler.OnTick` 开始执行：
1. 计算与玩家的 XZ 距离
2. 距离 > 4m² 时 `SetMoveTarget()` 追踪
3. `syncNpcMovement` 桥接到 `NpcMoveComp`
4. 帧同步下发位置 → 客户端 `TransformComp.Lerp` 插值

客户端 `AnimalFollowState` 已有 run 动画 + 速度同步，无需额外修改。

### 2.3 P1+P2: 背包喂食 + 交互闭环（合并实现）

**问题**: 大世界无 HoldComp UI，AnimalInteractComp 检测依赖 `HoldComp.CurrentHold`

**方案**: 修改交互检测逻辑，改为直接检查 BackpackComp 中的食物道具

**服务器** (`P1GoServer`):
- `animal_feed.go` 的 `HandleAnimalFeed`: 增加 BackpackComp 食物消耗逻辑
- 当前服务器不校验物品类型，只校验距离和冷却 → 无需额外修改

**客户端** (`freelifeclient`):
- `AnimalInteractComp.cs`: 移除 HoldComp 依赖，改为检查 BackpackComp 是否有食物道具
- 靠近动物（3m内）+ 背包有食物 → 显示交互 UI
- 点击交互 → 发送 `AnimalFeedReq` + 从背包扣除食物

### 2.4 P2: Bird 飞行高度（自动解决）

P0 完成后，`BirdFlightHandler.OnTick` 开始执行：
1. 设飞行目标 Y = random(5m~20m)
2. `SetMoveTarget()` → `syncNpcMovement` → 帧同步
3. 客户端 `TransformComp.Lerp` 插值到新高度

客户端 `AnimalFlightState` 已有 fly 动画 + foot IK 禁用，无需额外修改。

## 3. 验收测试方案

### TC-010: 大世界动物 AI tick
前置条件：已登录大世界
操作步骤：
1. [GM] `/kei gm add_animal dog 1` 生成 dog
2. [等待] 30 秒观察 dog 行为
3. [验证] Dog 应有 Idle→Walk→Idle 循环（游荡行为）
验证方式：screenshot-game-view + script-execute 读 BehaviorState

### TC-011: Dog Follow 移动
前置条件：已登录大世界，附近有 dog
操作步骤：
1. [GM] `/kei gm feed_animal` 喂食
2. [验证] Dog State=5(Follow) + Dog 移动跟随玩家
3. [等待] 30 秒
4. [验证] Dog 回归 Idle（Follow 超时）
验证方式：screenshot-game-view + script-execute 读位置变化

### TC-012: Bird 飞行升空
前置条件：已登录大世界，有 bird
操作步骤：
1. [等待] bird 进入 Flight 状态
2. [验证] Bird Y 坐标 > 地面 + 5m
验证方式：script-execute 读 transform.position.y

### TC-013: 背包喂食交互
前置条件：已登录大世界
操作步骤：
1. [GM] `/kei gm add_backpack_item <food_item_id> 5`
2. [接近] 走近 dog（<3m）
3. [验证] 弹出交互 UI
4. [操作] 点击喂食
5. [验证] Dog 进入 Follow + 背包食物数量 -1
验证方式：script-execute 检查背包 + screenshot-game-view
