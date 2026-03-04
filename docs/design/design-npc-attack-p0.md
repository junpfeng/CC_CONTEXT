# NPC 攻击系统 P0 - 技术设计

> 范围：伤害系统核心 + 血量/死亡处理 + 仇恨补全
> 命中模式：客户端权威（沿用 Rust 设计）
> Rust 参考文档：`docs/research-rust-npc-attack-system.md`

---

## 1. 需求回顾

### P0 功能点

| # | 功能 | 说明 |
|---|------|------|
| 1 | handle_hit_data | 处理客户端上报的 HitData，入口在 action.go EventList |
| 2 | can_take_damage | 伤害合法性验证（死亡/无敌/交互/红名规则） |
| 3 | attack | HitData 路径的伤害处理（验证→扣血→事件） |
| 4 | deal_damage | 通用伤害处理（碰撞/爆炸/坠落，直接扣血） |
| 5 | 血量扣减 | 调用 GAS ModifyAttribute 扣血，≤0 自动触发死亡 |
| 6 | 死亡事件广播 | 广播 SceneEvent::Kill 到 AOI 范围 |
| 7 | 仇恨联动 | 伤害发生后更新 HateComp |
| 8 | OnPlayerDeath 修复 | 玩家死亡时从所有 NPC 仇恨列表中清除 |
| 9 | UpdateHateSystem | 每帧仇恨衰减系统 |

### 不在 P0 范围

- NpcFireControl 射击控制
- 攻击 BT 节点（目标选择/瞄准/射击）
- 攻击 Brain Plan
- CheckManager 反作弊
- handle_shot_data 射击弹药扣减（NPC 不消耗弹药）

---

## 2. 架构设计

### 2.1 数据流

```
客户端 ActionReq.EventList
    ↓
action.go：事件分发
    ├── SceneEventHit     → handleHitData()
    ├── SceneEventCrash   → handleCrashData()
    ├── SceneEventShot    → (P0 跳过，仅记录日志)
    └── SceneEventFall    → handleFallData()（未来扩展）
    ↓
handleHitData():
    1. 基础验证（target≠0, target≠attacker, damage>0）
    2. canTakeDamage() 验证
    3. attack() 处理伤害
    4. 广播 SceneEvent::Hit 到 AOI
    ↓
attack():
    1. GAS ModifyAttribute(health, Sub, damage)
       → 内部自动检查 health≤0 → TriggerDeathEvent
    2. 仇恨更新：OnNpcDamaged / OnNpcAttackPlayer
    3. 如果目标死亡：广播 SceneEvent::Kill
    ↓
canTakeDamage():
    1. 目标已死亡 → 拒绝
    2. 目标无 GAS 组件 → 拒绝
    3. NPC 攻击玩家 → 检查红名（WantedComp.IsRedName）
    4. 返回 (可攻击, HitResultType)
```

### 2.2 现有集成点

| 集成点 | 现有代码 | 状态 |
|--------|----------|------|
| 事件入口 | `action.go` 第 112 行 TODO | 需实现分发 |
| 血量扣减 | `gas_complete.go` ModifyAttribute | ✅ 可直接调用 |
| 死亡触发 | `gas_integration.go` TriggerDeathEvent | ✅ 自动触发(health≤0) |
| BaseStatusComp | `base_status.go` IsDead/SetDead | ✅ 可用 |
| 红名检查 | `wanted.go` IsRedName | ✅ 可用 |
| 仇恨增加 | `hate_system.go` OnNpcDamaged/OnNpcAttackPlayer | ✅ 可用 |
| 仇恨清理 | `hate_system.go` OnPlayerDeath | ⚠️ 需修复 |
| 事件广播 | `message_cache.go` AddEvent | ✅ 可用 |
| GAS 常量 | `gas_constants.go` GAS_ATTRIBUTE_UNIT_COMBAT_HEALTH_CURRENT | ✅ 6050010 |

---

## 3. 详细设计

### 3.1 新增文件

#### `servers/scene_server/internal/ecs/system/damage/types.go`

```go
package damage

// DamageType 伤害类型
type DamageType int32

const (
    DamageTypeAttack    DamageType = 0 // 攻击伤害（枪械/近战）
    DamageTypeCrash     DamageType = 1 // 碰撞伤害（载具）
    DamageTypeFall      DamageType = 2 // 坠落伤害
    DamageTypeExplosion DamageType = 3 // 爆炸伤害
    DamageTypeForce     DamageType = 4 // 强制伤害
)

// AttackerType 攻击者类型
type AttackerType int32

const (
    AttackerTypePlayer AttackerType = 0
    AttackerTypeNpc    AttackerType = 1
)
```

#### `servers/scene_server/internal/ecs/system/damage/damage.go`

核心函数：

```go
// CanTakeDamage 伤害合法性验证
// 参考 Rust: damage.rs:179-226
func CanTakeDamage(scene Scene, attacker, target Entity) (bool, proto.HitResultType) {
    // 1. 自己不能伤害自己
    // 2. 目标已死亡 → 拒绝
    // 3. 目标无 GAS 组件 → 拒绝
    // 4. NPC 攻击玩家 → 检查红名
    //    checkWantedStatusNpcAttackPlayer()
}

// Attack 处理 HitData 路径的伤害
// 参考 Rust: damage.rs:40-100
// 简化：Go 版本直接调用 ModifyAttribute，不走 BP 函数链路
func Attack(scene Scene, attacker, target Entity, hitData *proto.HitData) (int32, proto.HitResultType) {
    // 1. canTakeDamage 验证
    // 2. 计算最终伤害（P0 直接使用客户端上报的 damage 值）
    // 3. ModifyAttribute(health, Sub, damage) 扣血
    // 4. 仇恨更新
    // 5. 死亡检查 + KillInfo 广播
    // 返回 (实际伤害, HitResultType)
}

// DealDamage 通用伤害处理（碰撞/爆炸/坠落）
// 参考 Rust: damage.rs:103-177
func DealDamage(scene Scene, source, target Entity, damage int32, damageType DamageType) {
    // 1. canTakeDamage 验证
    // 2. ModifyAttribute(health, Sub, damage) 扣血
    // 3. 仇恨更新（仅 NPC 相关时）
    // 4. 死亡检查 + KillInfo 广播
}
```

#### `servers/scene_server/internal/ecs/system/damage/hit.go`

```go
// HandleHitData 处理客户端上报的命中数据
// 参考 Rust: hit.rs:15-60
func HandleHitData(scene Scene, attackerEntity Entity, hitData *proto.HitData) {
    // 1. 输入验证：target≠0, target≠attacker
    // 2. 获取目标实体
    // 3. 调用 Attack()
    // 4. 广播 SceneEvent::Hit（设置 hit_result）
}
```

#### `servers/scene_server/internal/ecs/system/damage/crash.go`

```go
// HandleCrashData 处理碰撞伤害
// 参考 Rust: crash.rs
func HandleCrashData(scene Scene, crashData *proto.CrashData) {
    // 1. 获取双方实体
    // 2. DealDamage(self→target) + DealDamage(target→self) 双向伤害
    // 3. 广播 SceneEvent::Crash
}
```

### 3.2 修改文件

#### `action.go` — 事件分发

在现有 TODO 处实现事件类型判断和分发：

```go
// 第 112-127 行 TODO 替换为：
for _, event := range req.EventList {
    if event.EventInfo == nil {
        continue
    }
    switch ev := event.EventInfo.(type) {
    case *proto.SceneEventHit:
        damage.HandleHitData(h.scene, playerEntity, ev.Data)
    case *proto.SceneEventCrash:
        damage.HandleCrashData(h.scene, ev.Data)
    case *proto.SceneEventShot:
        // P0: 仅记录日志，不处理弹药
        log.Debugf("[Damage] Shot event from entity=%d", playerEntity.ID())
    default:
        log.Debugf("[Damage] Unknown event type: %T", event.EventInfo)
    }
}
```

#### `hate_system.go` — 修复 OnPlayerDeath

```go
// 修复 OnPlayerDeath 中被注释的 NPC 清理逻辑
// 关键：通过 scene.GetEntity() 获取 NPC 实体
for _, npcEntityID := range npcList {
    npcEntity := scene.GetEntity(npcEntityID)
    if npcEntity == nil {
        continue
    }
    iComp := npcEntity.GetComponent(common.ComponentType_Hate)
    if iComp == nil {
        continue
    }
    hateComp := iComp.(*HateComp)
    hateComp.RemoveHate(playerEntity.ID())
}
```

#### `hate_system.go` — 实现 UpdateHateSystem

```go
func UpdateHateSystem(scene common.Scene) {
    // 遍历所有有 HateComp 的实体
    // 调用 UpdateHateDecay()
    // 对移除的仇恨目标，清理 ReverseHateComp
}
```

### 3.3 死亡事件补全

现有 `TriggerDeathEvent` (gas_integration.go) 只设置了 `SetDead()`。需要在死亡发生时：

1. 调用 `chate.OnPlayerDeath()` 清理仇恨
2. 广播 `SceneEvent::Kill` 到 AOI

**方案**：在 damage 包的 Attack/DealDamage 中，扣血后主动检查死亡状态并处理后续逻辑，不修改 GAS 内部代码。

```go
// 在 Attack() / DealDamage() 中：
ModifyAttribute(entity, gasComp, healthKey, Sub, damage)

// 检查是否刚死亡
if baseStatusComp.IsDead() {
    // 1. 仇恨清理
    chate.OnPlayerDeath(scene, targetEntity)
    // 2. 广播 KillInfo
    cache.AddEvent(proto.NewSceneEventKill(&proto.KillInfo{
        KillerEntity: attackerEntity.ID(),
        DeadEntity:   targetEntity.ID(),
        FinalHitData: hitData,
    }))
}
```

---

## 4. 与 Rust 的关键差异

| 点 | Rust | Go P0 |
|----|------|-------|
| BP 函数链路 | attack→bp_function→trigger→deal_damage→modify_attribute | attack→ModifyAttribute（直接调用，跳过 BP） |
| 仇恨双重触发 | deal_damage 中存在 bug（双重触发） | Go 版本不复现此 bug，仅触发一次 |
| 反作弊 | CheckManager 射击-命中校验 | P0 不实现，后续 P2 补充 |
| 射击弹药 | handle_shot_data 扣弹药 | P0 不实现 |
| 碰撞 NPC 响应 | crash 触发 BT 碰撞响应 | P0 仅处理伤害，不触发 BT |

---

## 5. 文件改动清单

### 新增文件

| 文件 | 职责 |
|------|------|
| `ecs/system/damage/types.go` | 伤害类型枚举 |
| `ecs/system/damage/damage.go` | CanTakeDamage + Attack + DealDamage |
| `ecs/system/damage/hit.go` | HandleHitData |
| `ecs/system/damage/crash.go` | HandleCrashData |

### 修改文件

| 文件 | 改动 |
|------|------|
| `net_func/action/action.go` | 实现 EventList 事件分发（替换 TODO） |
| `ecs/com/chate/hate_system.go` | 修复 OnPlayerDeath + 实现 UpdateHateSystem |

### 不修改的文件

| 文件 | 原因 |
|------|------|
| `gas_complete.go` | ModifyAttribute 已满足需求，不改动 |
| `gas_integration.go` | TriggerDeathEvent 保持现状，死亡后续逻辑在 damage 包处理 |
| `base_status.go` | IsDead/SetDead 已满足需求 |
| `wanted.go` | IsRedName 已满足需求 |
| `hate_comp.go` | 功能完整，无需改动 |
| `reverse_hate_comp.go` | 功能完整，无需改动 |

---

## 6. 验收标准

| # | 验收项 | 验证方法 |
|---|--------|----------|
| 1 | HitData 事件能被正确分发和处理 | action.go 接收 HitData → 调用 HandleHitData |
| 2 | 目标血量正确扣减 | ModifyAttribute 调用后 health 值减少 |
| 3 | 死亡自动触发 | health ≤ 0 时 BaseStatusComp.IsDead() = true |
| 4 | 已死亡目标不能再受伤 | canTakeDamage 返回 false |
| 5 | 仇恨正确更新 | 伤害后 HateComp 中仇恨值增加 |
| 6 | 玩家死亡仇恨清理 | 死亡后所有 NPC 的 HateComp 中移除该玩家 |
| 7 | KillInfo 事件广播 | 死亡时 FrameDataUpdateGlobalCache 中有 Kill 事件 |
| 8 | HitData 事件广播 | 命中时 AOI 范围内玩家收到 Hit 事件 |
| 9 | 碰撞伤害双向处理 | CrashData 双方都扣血 |
| 10 | 构建通过 | make build 无错误 |

---

## 7. 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| scene.GetEntity() API 不确定 | OnPlayerDeath 无法获取 NPC 实体 | 探索 Scene 接口确认实体查询方法 |
| EventList 中事件类型的 Go 类型断言 | 分发逻辑可能写错类型 | 参考 proto 生成代码确认 ISceneEvent 接口 |
| GAS ModifyAttribute 内部已触发 TriggerDeathEvent | 可能与 damage 包的死亡处理重复 | damage 包在扣血后检查 IsDead 而非自己触发死亡 |
| HateComp 衰减参数与 Rust 不一致 | 现有 DecayRate=1（Rust 为 3） | P0 保持现有值，后续调优 |
