# 技术设计文档：行为树系统支持小镇和樱花校园 NPC

**文档版本**: v1.0
**创建日期**: 2026-02-25
**需求文档**: `requirements/bt-town-sakura-compatibility.md`

---

## 1. 需求回顾

**目标**：让行为树系统能够同时支持小镇和樱花校园两种场景的 NPC，消除小镇特定组件的硬编码。

**核心问题**：
- IdleBehavior 硬编码 `TownNpcComp.SetOutDurationTime()`
- SetInitialPositionNode 硬编码 `TownNpcMgr` + `config.GetCfgTownNpcById()`
- SetTownNpcOutDurationNode 硬编码 `TownNpcComp`

**验收标准**：
- ✅ 小镇 NPC 功能不变（Dan, Customer, Dealer, Blackman）
- ✅ 樱花校园 NPC 可使用共享行为树（daily_schedule, dialog, init）
- ✅ 消除共享节点的场景特定硬编码
- ✅ 所有现有测试通过

---

## 2. 架构设计

### 2.1 三层架构

```
┌─────────────────────────────────────────────────────────────┐
│                    行为树节点层                               │
│  (IdleBehavior, SetInitialPositionNode, DialogBehavior...)  │
│                        │ 依赖                                 │
│                        ▼                                     │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              能力接口层 (Capability)                   │   │
│  │  - PositionInitializer      获取初始位置               │   │
│  │  - IdleBehaviorProvider     设置外出时长               │   │
│  │  - MovementController       移动控制                   │   │
│  │  - DialogController         对话控制                   │   │
│  └──────────────────┬───────────────────────────────────┘   │
│                     │ 实现                                   │
│  ┌──────────────────▼───────────────────────────────────┐   │
│  │            适配器层 (Adapters)                        │   │
│  │  Town:   TownPositionInitializer                     │   │
│  │          TownIdleBehaviorProvider                    │   │
│  │  Sakura: SakuraPositionInitializer                   │   │
│  │          SakuraIdleBehaviorProvider                  │   │
│  └──────────────────┬───────────────────────────────────┘   │
│                     │ 操作                                   │
│  ┌──────────────────▼───────────────────────────────────┐   │
│  │           ECS 组件层 (Components)                     │   │
│  │  Town:   TownNpcComp, TownNpcMgr, CfgTownNpc         │   │
│  │  Sakura: SakuraNpcControlComp, NpcManager, CfgSakura │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 设计模式

| 模式 | 应用 | 目的 |
|------|------|------|
| **适配器模式** | 为不同场景的组件提供统一的能力接口 | 隔离场景差异 |
| **依赖倒置** | 节点依赖抽象接口而非具体组件 | 提升可扩展性 |
| **注册模式** | BtContext 根据场景类型自动注册可用能力 | 运行时能力发现 |

### 2.3 核心原则

1. **依赖抽象不依赖实现**：节点只依赖能力接口
2. **开闭原则**：新增场景只需添加适配器，不修改节点
3. **向后兼容**：小镇 NPC 的行为表现完全不变

---

## 3. 能力接口设计

### 3.1 接口定义

**文件位置**：`servers/scene_server/internal/common/ai/bt/capability/capability.go`

```go
package capability

// ========== 基础能力接口（所有场景） ==========

// PositionInitializer 初始位置获取能力
type PositionInitializer interface {
	// GetInitialPosition 获取初始位置
	// 优先返回保存的位置，如果没有则返回配置的默认位置
	// Returns: (position, hasPosition)
	GetInitialPosition() (common.Vector3, bool)
}

// ========== 场景特定能力接口 ==========

// IdleBehaviorProvider 空闲行为能力
// 注意：小镇使用，樱校可以空实现
type IdleBehaviorProvider interface {
	// SetOutDurationTime 设置外出持续时间
	SetOutDurationTime(duration int64)
}
```

### 3.2 接口设计原则

| 原则 | 说明 |
|------|------|
| **最小接口** | 每个接口只包含一个职责的方法 |
| **返回值明确** | 使用 (value, ok) 模式表示成功/失败 |
| **幂等操作** | 方法可重复调用无副作用 |
| **无状态** | 接口方法不依赖调用顺序 |

---

## 4. 适配器实现设计

### 4.1 小镇适配器

#### 4.1.1 TownPositionInitializer

**职责**：为小镇 NPC 提供初始位置

**依赖**：
- `town.TownNpcMgr`：获取数据库保存的位置
- `config.CfgTownNpc`：获取配置的默认位置

**逻辑**：
1. 优先从 TownNpcMgr 获取保存的位置
2. 如果没有，从配置读取默认位置（DefaultX/Y/Z）
3. 如果都失败，返回 (zero, false)

**文件位置**：`servers/scene_server/internal/common/ai/bt/adapters/town_adapter.go`

```go
type TownPositionInitializer struct {
	npcCfgId int32
	townMgr  *town.TownNpcMgr
}

func (a *TownPositionInitializer) GetInitialPosition() (common.Vector3, bool) {
	// 1. 优先数据库保存位置
	if pos := a.townMgr.GetSavedPosition(a.npcCfgId); pos != nil {
		return *pos, true
	}

	// 2. 回退配置默认位置
	cfg := config.GetCfgTownNpcById(a.npcCfgId)
	if cfg != nil {
		return common.Vector3{
			X: cfg.DefaultX,
			Y: cfg.DefaultY,
			Z: cfg.DefaultZ,
		}, true
	}

	return common.Vector3{}, false
}
```

#### 4.1.2 TownIdleBehaviorProvider

**职责**：为小镇 NPC 设置外出时长

**依赖**：
- `cnpc.TownNpcComp`：调用 `SetOutDurationTime()`

**逻辑**：直接委托给 TownNpcComp

```go
type TownIdleBehaviorProvider struct {
	comp *cnpc.TownNpcComp
}

func (a *TownIdleBehaviorProvider) SetOutDurationTime(duration int64) {
	a.comp.SetOutDurationTime(duration)
}
```

---

### 4.2 樱花校园适配器

#### 4.2.1 SakuraPositionInitializer

**职责**：为樱花校园 NPC 提供初始位置

**依赖（已确认）**：
- `sakura.SakuraNpcMgr`：✅ 存在，但**无位置保存/获取方法**
- `config.CfgSakuraNpc`：✅ 存在，但**无位置字段**

**关键发现**：
- ❌ 樱校 NPC 配置表无 `birthPos` 或 `DefaultX/Y/Z` 字段
- ❌ `SakuraNpcMgr` 无 `GetSavedPosition()` 方法
- ❌ 樱校场景不持久化 NPC 位置数据
- ✅ 樱校 NPC 创建时初始位置硬编码为 **(0, 0, 0)**

**实现策略**：

**方案 1**：返回硬编码原点（与当前行为一致）
```go
func (a *SakuraPositionInitializer) GetInitialPosition() (common.Vector3, bool) {
	// 与樱校 NPC 创建时的行为一致
	return common.Vector3{X: 0, Y: 0, Z: 0}, true
}
```

**方案 2**：从日程系统读取第一个位置（更智能）
```go
func (a *SakuraPositionInitializer) GetInitialPosition() (common.Vector3, bool) {
	// 从 NPC 的日程配置读取第一个位置
	cfg := config.GetCfgSakuraNpcById(a.npcCfgId)
	if cfg == nil {
		return common.Vector3{}, false
	}

	// 读取日程配置的第一个位置
	scheduleFile := cfg.GetSchedule()
	schedule := confignpcschedule.GetNpcSchedule(scheduleFile)
	if schedule != nil && len(schedule.Schedules) > 0 {
		firstSchedule := schedule.Schedules[0]
		if firstSchedule.Position != nil {
			return *firstSchedule.Position, true
		}
	}

	// 回退到原点
	return common.Vector3{X: 0, Y: 0, Z: 0}, true
}
```

**推荐方案**：方案 1（硬编码原点）
- 理由：与当前樱校 NPC 创建逻辑一致，避免引入新的依赖
- 后续优化：如果需要从日程系统读取位置，可以在后续迭代中实现

**文件位置**：`servers/scene_server/internal/common/ai/bt/adapters/sakura_adapter.go`

```go
type SakuraPositionInitializer struct {
	npcCfgId int32
	// 注意：不依赖 SakuraNpcMgr（因为无位置保存功能）
}

func NewSakuraPositionInitializer(npcCfgId int32) *SakuraPositionInitializer {
	return &SakuraPositionInitializer{npcCfgId: npcCfgId}
}

func (a *SakuraPositionInitializer) GetInitialPosition() (common.Vector3, bool) {
	// 返回硬编码原点（与樱校 NPC 创建时的行为一致）
	return common.Vector3{X: 0, Y: 0, Z: 0}, true
}

var _ capability.PositionInitializer = (*SakuraPositionInitializer)(nil)
```

#### 4.2.2 SakuraIdleBehaviorProvider

**职责**：为樱花校园 NPC 提供空闲行为能力

**依赖（已确认）**：
- `cnpc.SakuraNpcComp`：✅ 存在，有 `outDurationTime` 字段和 `SetOutDurationTime()` 方法

**关键发现**：
- ✅ `SakuraNpcComp` 有 `outDurationTime int64` 字段
- ✅ 有 `SetOutDurationTime(time int64)` 方法
- ⚠️ 用途与小镇不同：樱校用于**客户端显示**，小镇用于**超时控制**

**实现策略**：直接委托给 `SakuraNpcComp`

**文件位置**：`servers/scene_server/internal/common/ai/bt/adapters/sakura_adapter.go`

```go
type SakuraIdleBehaviorProvider struct {
	comp *cnpc.SakuraNpcComp
}

func NewSakuraIdleBehaviorProvider(comp *cnpc.SakuraNpcComp) *SakuraIdleBehaviorProvider {
	return &SakuraIdleBehaviorProvider{comp: comp}
}

func (a *SakuraIdleBehaviorProvider) SetOutDurationTime(duration int64) {
	// 直接委托给 SakuraNpcComp（与小镇行为一致）
	a.comp.SetOutDurationTime(duration)
}

var _ capability.IdleBehaviorProvider = (*SakuraIdleBehaviorProvider)(nil)
```

**说明**：虽然樱校和小镇的 `outDurationTime` 用途不完全相同，但接口行为一致，可以复用。

---

## 5. BtContext 能力注册机制

### 5.1 数据结构变更

**文件**：`servers/scene_server/internal/common/ai/bt/context/context.go`

```go
type BtContext struct {
	// ... 原有字段

	// 通用组件缓存（不变）
	moveComp      component.IComponent
	transformComp component.IComponent
	decisionComp  component.IComponent
	npcComp       component.IComponent
	visionComp    component.IComponent

	// 删除场景特定组件缓存
	// policeComp component.IComponent // ❌ 删除

	// 新增：能力注册表
	capabilities map[reflect.Type]interface{} // ✅ 新增
}
```

### 5.2 能力注册流程

```go
// Reset() 中调用
func (ctx *BtContext) Reset() {
	// 1. 清理组件缓存
	ctx.moveComp = nil
	ctx.decisionComp = nil
	ctx.transformComp = nil
	ctx.npcComp = nil
	ctx.visionComp = nil

	// 2. 清理并重新注册能力
	ctx.capabilities = nil
	ctx.registerCapabilities() // 根据场景类型自动注册
}

// 场景检测和能力注册
func (ctx *BtContext) registerCapabilities() {
	scene := ctx.Scene()
	if scene == nil {
		return
	}

	sceneInfo := scene.GetSceneInfo()

	switch sceneInfo.(type) {
	case *common.TownSceneInfo:
		ctx.registerTownCapabilities(ctx.Entity(), scene)
	case *common.SakuraSceneInfo:
		ctx.registerSakuraCapabilities(ctx.Entity(), scene)
	default:
		ctx.Warn("[BtContext] Unknown scene type")
	}
}
```

### 5.3 小镇能力注册

```go
func (ctx *BtContext) registerTownCapabilities(entity component.Entity, scene common.Scene) {
	npcCfgId := ctx.GetNpcCfgId()

	// 1. 注册位置初始化能力
	if townMgr, ok := component.GetResourceAs[*town.TownNpcMgr](scene); ok {
		posInit := adapters.NewTownPositionInitializer(npcCfgId, townMgr)
		ctx.registerCapability((*capability.PositionInitializer)(nil), posInit)
	}

	// 2. 注册空闲行为能力
	if townComp, ok := component.GetComponentAs[*cnpc.TownNpcComp](entity, component.ComponentType_TownNpc); ok {
		idleProvider := adapters.NewTownIdleBehaviorProvider(townComp)
		ctx.registerCapability((*capability.IdleBehaviorProvider)(nil), idleProvider)
	}
}
```

### 5.4 樱校能力注册

```go
func (ctx *BtContext) registerSakuraCapabilities(entity component.Entity, scene common.Scene) {
	npcCfgId := ctx.GetNpcCfgId()

	// 1. 注册位置初始化能力（不依赖 SakuraNpcMgr）
	posInit := adapters.NewSakuraPositionInitializer(npcCfgId)
	ctx.registerCapability((*capability.PositionInitializer)(nil), posInit)

	// 2. 注册空闲行为能力（依赖 SakuraNpcComp）
	if sakuraComp, ok := component.GetComponentAs[*cnpc.SakuraNpcComp](entity, component.ComponentType_SakuraNpc); ok {
		idleProvider := adapters.NewSakuraIdleBehaviorProvider(sakuraComp)
		ctx.registerCapability((*capability.IdleBehaviorProvider)(nil), idleProvider)
	}
}
```

### 5.5 能力查询 API

```go
// 类型安全的能力获取（泛型）
func GetCapabilityAs[T any](ctx *BtContext) (T, bool) {
	var zero T
	cap, exists := ctx.GetCapability((*T)(nil))
	if !exists {
		return zero, false
	}
	typed, ok := cap.(T)
	return typed, ok
}

// 使用示例（在节点中）
posInit, ok := context.GetCapabilityAs[capability.PositionInitializer](ctx)
if !ok {
	return node.BtNodeStatusFailed
}
```

---

## 6. 节点重构设计

### 6.1 IdleBehavior 重构

**文件**：`servers/scene_server/internal/common/ai/bt/nodes/behavior_nodes.go`

#### 重构前后对比

```go
// ===== 重构前（硬编码 TownNpcComp）=====
func (n *IdleBehavior) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
	townNpcComp, ok := component.GetComponentAs[*cnpc.TownNpcComp](
		ctx.Entity(), component.ComponentType_TownNpc)
	if !ok {
		return node.BtNodeStatusFailed // ❌ 樱校失败
	}
	townNpcComp.SetOutDurationTime(n.duration) // ❌ 硬编码
	// ...
}

// ===== 重构后（使用能力接口）=====
func (n *IdleBehavior) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
	// 1. 设置位置和朝向（通用逻辑，所有场景）
	targetPos, targetRot, ok := getTargetPosFromFeature(ctx)
	if !ok {
		ctx.Warn("[IdleBehavior] Failed to get target position")
		return node.BtNodeStatusFailed
	}

	transformComp := ctx.GetTransformComp()
	if transformComp == nil {
		return node.BtNodeStatusFailed
	}
	transformComp.SetPosition(targetPos)
	transformComp.SetRotation(targetRot)

	// 2. 设置外出时长（可选能力，樱校可能没有）
	if idleProvider, ok := context.GetCapabilityAs[capability.IdleBehaviorProvider](ctx); ok {
		idleProvider.SetOutDurationTime(n.duration) // ✅ 通过能力接口
	}
	// ✅ 樱校没有这个能力也不会失败，继续执行

	return node.BtNodeStatusRunning
}
```

**关键改进**：
- ✅ 不再依赖 TownNpcComp
- ✅ 外出时长是可选能力，樱校没有也不影响
- ✅ 通用逻辑（位置/朝向）保持不变

---

### 6.2 SetInitialPositionNode 重构

**文件**：`servers/scene_server/internal/common/ai/bt/nodes/init_position.go`

#### 重构前后对比

```go
// ===== 重构前（硬编码 TownNpcMgr + 配置）=====
func (n *SetInitialPositionNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
	scene := ctx.Scene()
	townNpcMgr, ok := GetResourceAs[*town.TownNpcMgr](scene)
	if !ok {
		return node.BtNodeStatusFailed // ❌ 樱校失败
	}

	npcCfgId := ctx.GetNpcCfgId()
	pos := townNpcMgr.GetSavedPosition(npcCfgId) // ❌ 硬编码
	if pos == nil {
		npcCfg := config.GetCfgTownNpcById(npcCfgId) // ❌ 硬编码
		pos = &Vector3{X: npcCfg.DefaultX, Y: npcCfg.DefaultY, Z: npcCfg.DefaultZ}
	}
	// ...
}

// ===== 重构后（使用能力接口）=====
func (n *SetInitialPositionNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
	// 1. 查询位置初始化能力
	posInit, ok := context.GetCapabilityAs[capability.PositionInitializer](ctx)
	if !ok {
		ctx.Error("[SetInitialPosition] NPC lacks PositionInitializer capability")
		return node.BtNodeStatusFailed
	}

	// 2. 获取初始位置（适配器内部处理保存位置 vs 配置）
	initialPos, hasPos := posInit.GetInitialPosition()
	if !hasPos {
		ctx.Error("[SetInitialPosition] Failed to get initial position")
		return node.BtNodeStatusFailed
	}

	// 3. 设置到 Transform 组件
	transformComp := ctx.GetTransformComp()
	if transformComp == nil {
		return node.BtNodeStatusFailed
	}
	transformComp.SetPosition(initialPos)

	return node.BtNodeStatusSuccess
}
```

**关键改进**：
- ✅ 不再依赖 TownNpcMgr
- ✅ 不再依赖 GetCfgTownNpcById()
- ✅ 小镇/樱校通过不同适配器实现相同接口

---

### 6.3 SetTownNpcOutDurationNode 重构

**文件**：`servers/scene_server/internal/common/ai/bt/nodes/dialog.go`

#### 重构策略

1. **节点改名**：`SetTownNpcOutDurationNode` → `SetNpcOutDurationNode`（通用化）
2. **工厂注册更新**：保留旧名称别名，保证 JSON 兼容性

#### 重构后代码

```go
// 改名为通用节点
type SetNpcOutDurationNode struct {
	node.BaseNode
	durationKey string // 从 Blackboard 读取时长的键
}

func (n *SetNpcOutDurationNode) OnEnter(ctx *context.BtContext) node.BtNodeStatus {
	duration := ctx.GetBlackboardInt64(n.durationKey)

	// 查询空闲行为能力
	if idleProvider, ok := context.GetCapabilityAs[capability.IdleBehaviorProvider](ctx); ok {
		idleProvider.SetOutDurationTime(duration)
		return node.BtNodeStatusSuccess
	}

	// 如果 NPC 不支持这个能力，返回 Success（不阻塞流程）
	ctx.Debug("[SetNpcOutDuration] NPC lacks IdleBehaviorProvider, skipping")
	return node.BtNodeStatusSuccess
}
```

#### 工厂注册兼容性

```go
// factory.go
factory.Register("SetNpcOutDurationNode", createSetNpcOutDurationNode)
factory.Register("SetTownNpcOutDurationNode", createSetNpcOutDurationNode) // 别名
```

---

## 7. 文件修改清单

### 7.1 新增文件

| 文件路径 | 说明 |
|---------|------|
| `servers/scene_server/internal/common/ai/bt/capability/capability.go` | 能力接口定义 |
| `servers/scene_server/internal/common/ai/bt/adapters/town_adapter.go` | 小镇适配器实现 |
| `servers/scene_server/internal/common/ai/bt/adapters/sakura_adapter.go` | 樱校适配器实现 |

### 7.2 修改文件

| 文件路径 | 修改内容 |
|---------|---------|
| `servers/scene_server/internal/common/ai/bt/context/context.go` | 添加能力注册机制（registerCapabilities 等方法）|
| `servers/scene_server/internal/common/ai/bt/nodes/behavior_nodes.go` | IdleBehavior 重构 |
| `servers/scene_server/internal/common/ai/bt/nodes/init_position.go` | SetInitialPositionNode 重构 |
| `servers/scene_server/internal/common/ai/bt/nodes/dialog.go` | SetTownNpcOutDurationNode → SetNpcOutDurationNode |
| `servers/scene_server/internal/common/ai/bt/nodes/factory.go` | 注册新节点别名 |

---

## 8. 向后兼容性保证

### 8.1 小镇 NPC 行为不变

| 兼容性项 | 保证措施 |
|---------|---------|
| **TownNpcComp.SetOutDurationTime()** | 小镇适配器直接调用，逻辑完全一致 |
| **位置初始化** | TownPositionInitializer 使用原有的 TownNpcMgr 和配置查询 |
| **数据库保存位置** | 优先级逻辑保持不变（保存位置 > 配置默认位置）|

### 8.2 JSON 配置兼容

| 配置项 | 兼容性 |
|-------|--------|
| **节点类型名** | `SetTownNpcOutDurationNode` 通过别名保持兼容 |
| **行为树 JSON** | 无需修改任何现有 JSON 文件 |
| **Brain 配置** | 无需修改小镇和樱校的 Brain 配置 |

### 8.3 测试兼容

| 测试类别 | 要求 |
|---------|------|
| **单元测试** | 所有现有单元测试必须通过 |
| **集成测试** | 小镇 NPC 的集成测试必须通过 |
| **回归测试** | Dan/Customer/Dealer/Blackman 的行为表现与重构前完全一致 |

---

## 9. ✅ 樱花校园依赖确认（已完成）

### 9.1 实际代码探索结果

| 确认项 | 探索结果 | 说明 |
|-------|---------|------|
| **樱校 NPC 管理器** | ✅ `sakura.SakuraNpcMgr` 存在 | 位置：`sakura/sakura_npc.go` |
| **位置保存方法** | ❌ **不存在** | 无 `GetSavedPosition()` 方法，不持久化位置 |
| **樱校 NPC 配置** | ✅ `config.CfgSakuraNpc` 存在 | 位置：`common/config/cfg_sakuranpc.go` |
| **配置表位置字段** | ❌ **无位置字段** | 无 `DefaultX/Y/Z` 或 `birthPos` 字段 |
| **初始位置来源** | 硬编码 **(0, 0, 0)** | `CreateSakuraNpc()` 中硬编码原点 |
| **外出时长字段** | ✅ `outDurationTime` 存在 | `SakuraNpcComp` 有此字段，用于客户端显示 |
| **外出时长方法** | ✅ `SetOutDurationTime()` 存在 | 与小镇接口一致 |
| **场景特定组件** | ✅ `SakuraNpcComp` 存在 | 位置：`ecs/com/cnpc/sakura_npc.go` |
| **控制组件** | ✅ `SakuraNpcControlComp` 存在 | 位置：`ecs/com/csakura/sakura_npc_control.go` |
| **位置持久化** | ❌ **不持久化** | `DBSaveSakuraInfo` 无 NPC 位置字段 |

### 9.2 关键设计约束（基于实际代码）

1. **位置初始化策略**：
   - 小镇：配置表 `birthPos` → 数据库保存位置 → 配置默认位置
   - 樱校：硬编码原点 (0,0,0)（无配置位置、无保存位置）

2. **外出时长概念**：
   - 小镇：`feature_out_timeout` 用于超时控制（行为逻辑）
   - 樱校：`outDurationTime` 用于客户端显示（UI 展示）

3. **位置持久化**：
   - 小镇：有完整的保存/恢复机制
   - 樱校：无位置持久化（依赖日程系统驱动位置）

4. **玩家控制特性**：
   - 小镇：无玩家控制组件
   - 樱校：有 `SakuraNpcControlComp`（核心特性）

### 9.3 适配器实现调整

基于实际发现，适配器实现已调整：

| 适配器 | 原设计 | 实际实现 |
|-------|-------|---------|
| `SakuraPositionInitializer` | 从配置表读取位置 | 返回硬编码原点 (0,0,0) |
| `SakuraIdleBehaviorProvider` | 空实现 | 委托给 `SakuraNpcComp.SetOutDurationTime()` |

---

## 10. 性能分析

### 10.1 能力注册开销

| 阶段 | 操作 | 复杂度 | 频率 |
|------|------|--------|------|
| **注册** | registerCapabilities() | O(n) n=能力数量 | Reset() 时一次 |
| **查询** | GetCapabilityAs() | O(1) map 查找 | 每次节点 OnEnter |

**结论**：性能影响极小，能力在 Reset() 时一次性注册，后续查询是 O(1) 的 map 操作。

### 10.2 反射开销

- **仅用于注册阶段**：`reflect.TypeOf()` 仅在 registerCapability() 时调用
- **查询阶段无反射**：使用预计算的 Type 作为 map key
- **影响评估**：可忽略不计

---

## 11. 风险与缓解

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| **樱校依赖缺失** | 中 | 中 | Phase 3 前完成依赖确认，补充缺失组件 |
| **接口设计不合理** | 低 | 中 | 仅设计最小必要接口，后续可扩展 |
| **破坏小镇 NPC 功能** | 低 | 高 | 完整回归测试 + 代码审查 |
| **测试覆盖不足** | 中 | 高 | 新增樱校集成测试 + 小镇回归测试 |

---

## 12. 后续扩展方向（不在本次范围）

1. **完全通用化**：支持任意场景类型（副本、活动场景等）
2. **节点元数据**：标记节点适用的场景类型，运行时检查
3. **配置驱动**：通过配置文件定义 NPC 类型与能力的映射关系
4. **可视化编辑器**：Brain 配置和行为树的可视化编辑工具

---

## 13. 参考文档

- **需求文档**：`docs/requirements/bt-town-sakura-compatibility.md`
- **行为树规范**：`.claude/rules/behavior-tree.md`
- **ECS 架构**：`.claude/rules/ecs-architecture.md`
- **AI 决策系统**：`.claude/skills/dev-workflow/BTree.md`

---

**文档状态**: ✅ 待审核
**下一步**: Phase 3 任务拆解（需先完成樱校依赖确认）
