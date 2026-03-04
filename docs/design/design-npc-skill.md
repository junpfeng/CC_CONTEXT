# NPC 技能系统技术设计

## 1. 需求回顾

| 项目 | 内容 |
|------|------|
| 功能 | NPC 技能系统（近战普攻 + 远程射击） |
| 攻击目标 | 仅玩家 |
| 适用范围 | 仅小镇 NPC |
| 弹道判定 | 即时命中（距离+角度校验） |
| 技能配置 | 新建 NpcSkill.xlsx 配置表 |
| 伤害系统 | 独立实现，不使用 GAS 伤害管线 |

## 2. 系统架构概览

```
┌─────────────────────────────────────────────────────────────┐
│  感知层 (已有)                                               │
│  VisionComp + VisionSystem → 发现可见玩家                     │
│  HateComp → 仇恨目标排序                                     │
└──────────────┬──────────────────────────────────────────────┘
               │ Feature: feature_combat_target, feature_has_target
               ▼
┌─────────────────────────────────────────────────────────────┐
│  决策层 (Brain, 1秒)                                         │
│  condition: feature_has_target == true → plan: npc_combat    │
│  condition: feature_has_target == false → plan: daily_schedule│
└──────────────┬──────────────────────────────────────────────┘
               │ Plan name = "npc_combat"
               ▼
┌─────────────────────────────────────────────────────────────┐
│  执行层 (BT, 每帧)                                           │
│  npc_combat.json:                                            │
│    SimpleParallel (边移动边攻击)                               │
│    ├── Main: ChaseTarget (持续追逐目标)                       │
│    └── Background: Repeater[SelectSkill → NpcAttack] (循环攻击)│
│                                                              │
│  工作原理（单线程协作式调度，非多线程并行）：                    │
│    每帧 OnTick 内顺序执行:                                    │
│      ① tickChild(ChaseTarget)  → 推进追逐一步                │
│      ② tickChild(攻击循环)      → 推进攻击一步                │
│    宏观效果: NPC 同时在移动和攻击                              │
└──────────────┬──────────────────────────────────────────────┘
               │ 命中 → 调用独立伤害系统
               ▼
┌─────────────────────────────────────────────────────────────┐
│  伤害层 (新建, 独立于 GAS)                                    │
│  NpcDamageHelper.ApplyDamage(scene, attacker, target, dmg)   │
│  → 读取目标 HP → 扣减 → 死亡检查 → 广播 SceneEvent          │
└─────────────────────────────────────────────────────────────┘
```

## 3. 组件设计

### 3.1 NpcSkillComp（新增组件）

**文件**: `servers/scene_server/internal/ecs/com/cnpc/npc_skill_comp.go`

```go
type NpcSkillComp struct {
    common.ComponentBase

    // 技能列表（从配置加载）
    skills []*NpcSkillSlot

    // 冷却追踪
    cooldownMap map[int32]int64  // skillID → 下次可用时间戳(ms)

    // 当前状态
    currentSkillID   int32   // 正在施放的技能 ID，0=空闲
    currentTargetID  uint64  // 当前攻击目标
    attackStartTime  int64   // 攻击开始时间(ms)
}

type NpcSkillSlot struct {
    SkillID  int32   // 技能 ID（对应 CfgNpcSkill.id）
    Priority int32   // 优先级（越大越优先）
}

// --- 查询接口 ---

// CanUseSkill 检查技能是否可用（冷却完毕）
func (c *NpcSkillComp) CanUseSkill(skillID int32, nowMs int64) bool

// GetBestSkill 根据距离选择最优技能（优先级 > 类型匹配）
func (c *NpcSkillComp) GetBestSkill(distance float32, nowMs int64) *NpcSkillSlot

// GetMeleeSkill 获取近战技能（type=melee 且冷却完毕）
func (c *NpcSkillComp) GetMeleeSkill(nowMs int64) *NpcSkillSlot

// GetRangedSkill 获取远程技能（type=ranged 且冷却完毕）
func (c *NpcSkillComp) GetRangedSkill(nowMs int64) *NpcSkillSlot

// --- 状态管理 ---

// StartSkill 标记开始施放技能
func (c *NpcSkillComp) StartSkill(skillID int32, targetID uint64, nowMs int64)

// FinishSkill 标记施放完成，设置冷却
func (c *NpcSkillComp) FinishSkill(skillID int32, cooldownMs int32, nowMs int64)

// IsAttacking 是否正在攻击中
func (c *NpcSkillComp) IsAttacking() bool

// GetCurrentTargetID 获取当前攻击目标
func (c *NpcSkillComp) GetCurrentTargetID() uint64
```

**生命周期**：
- 创建：NPC Entity 创建时，根据 NpcCfgId 查询配置表，填充 skills 列表
- 销毁：随 Entity 销毁

**注册**：
- ComponentType: `ComponentType_NpcSkill`（新增枚举值）
- 注册位置: `common/component_types.go`

### 3.2 独立伤害系统

**文件**: `servers/scene_server/internal/ecs/com/cnpc/npc_damage.go`

```go
// DamageResult 伤害结算结果
type DamageResult struct {
    AttackerEntityID uint64
    TargetEntityID   uint64
    SkillID          int32
    Damage           int32    // 最终伤害值
    RemainingHP      int32    // 目标剩余 HP
    IsDead           bool     // 目标是否死亡
    HitPosition      Vector3  // 命中位置
}

// ApplyNpcDamage 独立伤害结算（不走 GAS Effect 管线）
// 流程：验证目标 → 读 HP → 扣减 → 死亡检查 → 广播事件
func ApplyNpcDamage(
    scene common.Scene,
    attackerEntityID uint64,
    targetEntityID uint64,
    skillCfg *config.CfgNpcSkill,
    hitPosition Vector3,
) (*DamageResult, error) {
    // 1. 获取目标 Entity
    targetEntity := scene.GetEntity(targetEntityID)
    if targetEntity == nil {
        return nil, ErrTargetNotFound
    }

    // 2. 检查目标存活
    statusComp := getBaseStatusComp(targetEntity)
    if statusComp != nil && statusComp.IsDead() {
        return nil, ErrTargetDead
    }

    // 3. 读取目标当前 HP（通过 HealthAccessor 接口）
    currentHP := ReadTargetHP(scene, targetEntityID)
    if currentHP <= 0 {
        return nil, ErrTargetDead
    }

    // 4. 计算最终伤害（基础伤害，后续可扩展防御计算）
    finalDamage := int32(skillCfg.GetDamage())

    // 5. 扣减 HP
    newHP := currentHP - finalDamage
    if newHP < 0 {
        newHP = 0
    }
    WriteTargetHP(scene, targetEntityID, newHP)

    // 6. 死亡检查
    isDead := newHP <= 0
    if isDead && statusComp != nil {
        statusComp.SetDead()
    }

    // 7. 构建结果
    result := &DamageResult{
        AttackerEntityID: attackerEntityID,
        TargetEntityID:   targetEntityID,
        SkillID:          skillCfg.GetId(),
        Damage:           finalDamage,
        RemainingHP:      newHP,
        IsDead:           isDead,
        HitPosition:      hitPosition,
    }

    // 8. 广播伤害事件
    BroadcastHitEvent(scene, result)

    return result, nil
}
```

**HP 读写接口**（与 GAS 解耦的桥接层）：

```go
// ReadTargetHP 读取目标 HP
// 当前实现：从目标 Entity 的 GAS AttributeSet 读取 HP 属性
// 设计意图：如果未来 HP 存储位置变化，只需修改此函数
func ReadTargetHP(scene common.Scene, entityID uint64) int32

// WriteTargetHP 写入目标 HP
func WriteTargetHP(scene common.Scene, entityID uint64, hp int32)
```

**为什么这样设计**：
- GAS AttributeSet 是玩家 HP 的唯一存储位置，不创建冗余组件
- 通过 `ReadTargetHP`/`WriteTargetHP` 桥接函数隔离 GAS 细节
- 独立的伤害计算逻辑，不走 GAS 的 Effect→Modifier→Hook 管线
- 独立的死亡处理，直接操作 BaseStatusComp
- 独立的事件广播，自己构建 HitData

### 3.3 命中判定

**文件**: `servers/scene_server/internal/ecs/com/cnpc/npc_hit_check.go`

```go
// CheckMeleeHit 近战命中判定：距离检查
func CheckMeleeHit(
    scene common.Scene,
    attackerPos, targetPos Vector3,
    attackRange float32,
) bool {
    dist := Distance(attackerPos, targetPos)
    return dist <= attackRange
}

// CheckRangedHit 远程命中判定：距离 + 角度检查
func CheckRangedHit(
    scene common.Scene,
    attackerPos, attackerForward, targetPos Vector3,
    maxRange float32,
    maxAngleDeg float32,  // 射击锥半角（度）
) bool {
    // 1. 距离检查
    dist := Distance(attackerPos, targetPos)
    if dist > maxRange {
        return false
    }

    // 2. 角度检查（攻击者朝向 vs 目标方向）
    dirToTarget := Normalize(Sub(targetPos, attackerPos))
    angle := AngleBetween(attackerForward, dirToTarget)
    return angle <= maxAngleDeg
}
```

## 4. BT 节点设计

### 4.1 NpcAttack 节点（异步攻击节点）

**文件**: `servers/scene_server/internal/common/ai/bt/nodes/npc_attack.go`

**类型**: 异步节点（OnEnter→Running, OnTick 监控完成, OnExit 清理）

```go
type NpcAttackNode struct {
    BaseLeafNode
    skillIDKey   string  // BB key 或 params 中的技能 ID
    targetIDKey  string  // BB key: 攻击目标 entity ID

    // 节点实例状态（每次 Run 重建，NPC 间隔离）
    skillCfg     *config.CfgNpcSkill  // 缓存的技能配置
    hitApplied   bool                  // 是否已施加伤害
    startTimeMs  int64                 // 攻击开始时间
}
```

**生命周期**：

```
OnEnter:
  1. 从 BB/params 获取 skillID
  2. 查配置表获取 CfgNpcSkill
  3. 从 BB 获取 targetID
  4. 验证目标存活 + 在技能射程内
  5. 验证技能冷却完毕（NpcSkillComp.CanUseSkill）
  6. 设置 NpcSkillComp 状态: StartSkill(skillID, targetID)
  7. 更新 ServerAnimState: skill_id, skill_target_entity, is_fire(远程)
  8. 记录 startTimeMs
  → return Running

OnTick (每帧):
  1. 计算已过时间 = now - startTimeMs
  2. 如果已过时间 >= hitDelayMs 且 !hitApplied:
     - 执行命中判定（Check[Melee|Ranged]Hit）
     - 命中 → ApplyNpcDamage() 造成伤害
     - hitApplied = true
  3. 如果已过时间 >= durationMs:
     - NpcSkillComp.FinishSkill(skillID, cooldownMs)
     → return Success
  4. 检查目标是否已死亡/离开范围（可选提前结束）
  → return Running

OnExit:
  1. 清除 NpcSkillComp 攻击状态
  2. 重置 ServerAnimState（清除 skill_id, is_fire 等）
  3. 如果被 Abort 打断（n.Status() == Running）:
     - 如果伤害未施加，不补伤（打断 = 攻击失败）
     - 仍需设置冷却（防止打断后立即重新攻击）
```

**JSON 配置示例**：
```json
{
  "type": "NpcAttack",
  "params": {
    "skill_id_key": "selected_skill_id",
    "target_id_key": "combat_target_id"
  }
}
```

### 4.2 SelectCombatSkill 节点（同步技能选择节点）

**文件**: `servers/scene_server/internal/common/ai/bt/nodes/npc_select_skill.go`

**类型**: 同步动作节点（OnEnter 一次性完成）

```
OnEnter:
  1. 获取 NpcSkillComp
  2. 获取目标距离（从 BB 的 combat_target_distance 或实时计算）
  3. 调用 NpcSkillComp.GetBestSkill(distance, now)
  4. 如果无可用技能 → return Failed
  5. 将 skill_id 写入 BB: ctx.SetBlackboard("selected_skill_id", skillID)
  → return Success
```

### 4.3 UpdateCombatTarget 服务节点（Service）

**文件**: 复用或扩展 `SyncFeatureToBlackboard`

**作用**: 定期把战斗目标信息同步到 BB

```json
{
  "type": "SyncFeatureToBlackboard",
  "interval_ms": 200,
  "params": {
    "mappings": {
      "feature_combat_target_id": "combat_target_id",
      "feature_combat_target_distance": "combat_target_distance",
      "feature_has_combat_target": "has_combat_target"
    }
  }
}
```

### 4.4 npc_combat 行为树结构

**文件**: `bt/trees/npc_combat.json`

**核心思路**: 用 `SimpleParallel` 实现"边移动边攻击"。这不是多线程并行——是**单帧内顺序驱动两个子节点**，每帧先 Tick 主任务（移动），再 Tick 后台任务（攻击），宏观上看 NPC 同时在做两件事。

```json
{
  "name": "npc_combat",
  "description": "NPC 战斗技能树：追逐目标的同时循环攻击",
  "root": {
    "type": "Selector",
    "services": [
      {
        "type": "SyncFeatureToBlackboard",
        "interval_ms": 200,
        "params": {
          "mappings": {
            "feature_combat_target_id": "combat_target_id",
            "feature_combat_target_distance": "combat_target_distance",
            "feature_has_combat_target": "has_combat_target"
          }
        }
      }
    ],
    "children": [
      {
        "type": "SimpleParallel",
        "description": "边追逐边攻击",
        "params": { "finish_mode": "immediate" },
        "decorators": [
          {
            "type": "BlackboardCheck",
            "abort_type": "both",
            "params": {
              "key": "has_combat_target",
              "operator": "==",
              "value": true
            }
          }
        ],
        "children": [
          {
            "type": "ChaseTarget",
            "description": "主任务：持续追逐目标（决定整个节点生命周期）",
            "params": {
              "target_feature": "feature_combat_target_id"
            }
          },
          {
            "type": "Repeater",
            "description": "后台任务：无限循环攻击",
            "params": { "count": 0 },
            "children": [
              {
                "type": "Sequence",
                "children": [
                  {
                    "type": "SelectCombatSkill",
                    "description": "按距离选择近战或远程技能"
                  },
                  {
                    "type": "NpcAttack",
                    "description": "执行攻击（含命中判定+伤害+冷却等待）",
                    "params": {
                      "skill_id_key": "selected_skill_id",
                      "target_id_key": "combat_target_id"
                    }
                  }
                ]
              }
            ]
          }
        ]
      },
      {
        "type": "ReturnToSchedule",
        "description": "无目标时回归日常（兜底分支）"
      }
    ]
  }
}
```

**单帧执行顺序**（SimpleParallel.OnTick 内部）：

```
每帧:
  ① tickChild(ChaseTarget)       -- 推进追逐：更新寻路、移动一步
  ② tickChild(Repeater[攻击循环]) -- 推进攻击：
     ├── SelectCombatSkill 还没完成? → 执行选技能
     ├── NpcAttack 在 Running? → 检查 hitDelay/duration
     └── NpcAttack 完成? → Repeater Reset → 下一轮
  ③ 完成判定:
     ├── ChaseTarget Failed（目标丢失）→ finish_mode=immediate → 打断攻击 → 结束
     └── ChaseTarget Running → 继续
```

**攻击循环的节奏**：

```
时间线:
  T+0     SelectCombatSkill: 距离15m → 选远程技能(1002) → Success
  T+0     NpcAttack.OnEnter: 设动画 → Running
  T+200ms NpcAttack.OnTick: hitDelay到 → 命中判定 → 造成伤害
  T+600ms NpcAttack.OnTick: duration到 → 设冷却 → Success
  T+600ms Repeater: Reset Sequence → 重新开始
  T+616ms SelectCombatSkill: 冷却中(远程3s) + 距离3m → 选近战技能(1001) → Success
  T+616ms NpcAttack.OnEnter: 近战攻击 → Running
  ...（循环）

  如果所有技能都在冷却:
  T+xxx   SelectCombatSkill: 无可用技能 → Failed
  T+xxx   Sequence → Failed
  T+xxx   Repeater: Reset → 下一轮重试（下一帧再看有没有技能可用）
```

**为什么用 SimpleParallel 而不是 Selector 互斥分支**：

| 方案 | 行为 | 问题 |
|------|------|------|
| Selector[近战/远程/追逐] | NPC 要么攻击要么移动，不能同时 | 攻击时 NPC 站桩不动 |
| SimpleParallel[追逐, 攻击] | NPC 持续追逐，同时在射程内自动攻击 | 边跑边打，体验自然 |

## 5. 配置表设计

### 5.1 NpcSkill.xlsx

**路径**: `config/RawTables/TownNpc/NpcSkill.xlsx`

| 字段 | 类型 | 说明 |
|------|------|------|
| id | int32 | 技能 ID（主键） |
| name | string | 技能名称（调试用） |
| skillType | int32 | 技能类型：1=近战, 2=远程 |
| npcCfgId | int32 | 所属 NPC 配置 ID（关联 CfgTownNpc） |
| priority | int32 | 优先级（同类型中优先选高优先级） |
| damage | int32 | 基础伤害值 |
| attackRange | float | 攻击射程（米） |
| cooldownMs | int32 | 冷却时间（毫秒） |
| durationMs | int32 | 攻击动作总时长（毫秒） |
| hitDelayMs | int32 | 命中帧延迟（动作开始到伤害生效的时间） |
| maxAngle | float | 命中锥半角（度，仅远程有效，近战填 180） |
| animId | int32 | 攻击动画 ID（填入 ServerAnimState.anim_id） |

**示例数据**：

| id | name | skillType | npcCfgId | priority | damage | attackRange | cooldownMs | durationMs | hitDelayMs | maxAngle | animId |
|----|------|-----------|----------|----------|--------|-------------|------------|------------|------------|----------|--------|
| 1001 | 警棍攻击 | 1 | 5001 | 10 | 20 | 3.0 | 2000 | 800 | 400 | 180.0 | 101 |
| 1002 | 手枪射击 | 2 | 5001 | 5 | 30 | 30.0 | 3000 | 600 | 200 | 15.0 | 102 |

### 5.2 运行时索引

生成的 `cfg_npcskill.go` 提供 `GetCfgNpcSkillById(id)` 和 `GetCfgMapNpcSkill()`。

需要在业务代码中构建按 NpcCfgId 的索引：

```go
// npc_skill_config_index.go
var npcSkillIndex map[int32][]*config.CfgNpcSkill  // npcCfgId → skills

func InitNpcSkillIndex() {
    npcSkillIndex = make(map[int32][]*config.CfgNpcSkill)
    for _, skill := range config.GetCfgMapNpcSkill() {
        npcCfgId := skill.GetNpcCfgId()
        npcSkillIndex[npcCfgId] = append(npcSkillIndex[npcCfgId], skill)
    }
    // 按 priority 降序排序
    for _, skills := range npcSkillIndex {
        sort.Slice(skills, func(i, j int) bool {
            return skills[i].GetPriority() > skills[j].GetPriority()
        })
    }
}

func GetNpcSkillsByNpcCfgId(npcCfgId int32) []*config.CfgNpcSkill {
    return npcSkillIndex[npcCfgId]
}
```

## 6. 协议设计

### 6.1 复用现有协议

**不新增协议消息**。复用已有定义：

| 用途 | 复用消息 | 填充字段 |
|------|----------|----------|
| NPC 攻击动画 | `ServerAnimState` | `skill_id`, `skill_target_entity`, `is_fire`(远程), `anim_id` |
| 攻击命中通知 | `HitData` | `attack_entity`, `target_entity`, `weapon_id`=skillID, `damage`, `hit_position`, `hit_type` |
| 事件广播 | `SceneEvent` | 包装 HitData |
| 帧同步 | `FrameDataUpdate.event[]` | 添加 SceneEvent |

### 6.2 ServerAnimState 填充

攻击开始时：
```go
animState.SkillId = skillCfg.GetId()
animState.SkillTargetEntity = targetEntityID
animState.AnimId = skillCfg.GetAnimId()
// 远程射击额外字段
if skillCfg.GetSkillType() == SkillType_Ranged {
    animState.IsAim = true
    animState.IsFire = true
    animState.FireTargetEntity = targetEntityID
    animState.FireTargetPos = targetPosition
}
```

攻击结束时：
```go
animState.SkillId = 0
animState.SkillTargetEntity = 0
animState.IsAim = false
animState.IsFire = false
animState.FireTargetEntity = 0
```

### 6.3 HitData 构建

```go
func BuildNpcHitData(result *DamageResult, skillCfg *config.CfgNpcSkill) *proto.HitData {
    return &proto.HitData{
        AttackEntity:  result.AttackerEntityID,
        AttackerType:  AttackerType_NPC,
        WeaponId:      skillCfg.GetId(),  // 复用 weapon_id 字段传技能 ID
        HitPosition:   result.HitPosition.ToProto(),
        HitType:       int32(skillCfg.GetSkillType()),  // 1=melee, 2=ranged
        TargetEntity:  result.TargetEntityID,
        Damage:        result.Damage,
        HitResult:     proto.HitResultType_Common,
    }
}
```

### 6.4 事件广播

```go
func BroadcastHitEvent(scene common.Scene, result *DamageResult) {
    hitData := BuildNpcHitData(result, skillCfg)
    sceneEvent := &proto.SceneEvent{
        Data: &proto.SceneEvent_Hit{Hit: hitData},
    }
    // 添加到帧更新缓存
    scene.GetFrameCache().AddEvent(sceneEvent)
}
```

## 7. Feature 与 Sensor 集成

### 7.1 新增 Feature

战斗目标信息需要通过 Sensor → Feature → Service → BB 链路同步到行为树。

**新增 Feature 键**：

| Feature 键 | 类型 | 来源 | 说明 |
|------------|------|------|------|
| `feature_combat_target_id` | uint64 | MiscSensor | 当前战斗目标 entity ID |
| `feature_combat_target_distance` | float32 | MiscSensor | 到目标的距离 |
| `feature_has_combat_target` | bool | MiscSensor | 是否有战斗目标 |

### 7.2 MiscSensor 扩展

在 MiscSensor 的定期更新中，增加战斗目标计算逻辑：

```go
// 在 MiscSensor.Update() 中新增
func updateCombatTarget(scene common.Scene, entityID uint64, features FeatureMap) {
    // 1. 从 HateComp 获取最高仇恨目标
    hateComp := getHateComp(scene, entityID)
    if hateComp == nil || !hateComp.HasHateTargets() {
        features.Set("feature_has_combat_target", false)
        features.Set("feature_combat_target_id", uint64(0))
        return
    }

    targetID, _ := hateComp.GetHighestHateTarget()

    // 2. 验证目标仍然存活
    targetEntity := scene.GetEntity(targetID)
    if targetEntity == nil || isEntityDead(targetEntity) {
        hateComp.RemoveHate(targetID)
        features.Set("feature_has_combat_target", false)
        return
    }

    // 3. 计算距离
    distance := calculateDistance(scene, entityID, targetID)

    features.Set("feature_has_combat_target", true)
    features.Set("feature_combat_target_id", targetID)
    features.Set("feature_combat_target_distance", distance)
}
```

### 7.3 仇恨触发

NPC 的仇恨目标建立需要触发条件。对于第一版，可通过以下方式建立仇恨：

- **玩家进入 NPC 视野 + 满足条件**（如通缉状态）
- **玩家攻击 NPC**（被动反击）
- **GM 命令触发**（调试用）

具体触发机制取决于游戏设计，此处预留 `HateComp.AddHate(playerEntityID, hateValue)` 接口。

## 8. Brain 配置集成

### 8.1 新增 Plan: npc_combat

需要在使用战斗系统的 NPC 的 Brain 配置中新增 plan 和 transition。

**示例（Blackman NPC）**：

```json
{
  "plans": [
    { "name": "daily_schedule", "main_task": "do_main" },
    { "name": "police_enforcement", "main_task": "do_main" },
    { "name": "npc_combat", "main_task": "do_main" }
  ],
  "transitions": [
    {
      "name": "any_to_combat",
      "from": "*",
      "to": "npc_combat",
      "priority": 200,
      "condition": {
        "op": "and",
        "conditions": [
          { "key": "feature_has_combat_target", "op": "eq", "value": true }
        ]
      }
    },
    {
      "name": "combat_to_daily",
      "from": "npc_combat",
      "to": "daily_schedule",
      "priority": 100,
      "condition": {
        "op": "and",
        "conditions": [
          { "key": "feature_has_combat_target", "op": "eq", "value": false }
        ]
      }
    }
  ]
}
```

**关键约束**：
- plan name `npc_combat` 必须与 BT JSON 的 `name` 字段完全一致
- combat 优先级(200) > 日常优先级，确保有目标时优先进入战斗
- 退出条件检查 `feature_has_combat_target == false`

### 8.2 与现有 Plan 的关系

```
┌─────────────┐  feature_has_combat_target=true  ┌─────────────┐
│             │ ─────────────────────────────────→│             │
│daily_schedule│                                   │ npc_combat  │
│             │←─────────────────────────────────  │             │
└─────────────┘ feature_has_combat_target=false   └─────────────┘
       ↕                                                 ↕
┌──────────────────┐                                     │
│police_enforcement│     （互斥：同一时间只有一个 plan）   │
└──────────────────┘                                     │
```

**注意**: `npc_combat` 和 `police_enforcement` 需要设计互斥关系。如果 Blackman 同时有逮捕目标和战斗目标，需要明确优先级。建议：`npc_combat`(200) > `police_enforcement`(150) > `daily_schedule`(100)。

## 9. 详细流程

### 9.1 SimpleParallel 单帧执行细节

SimpleParallel **不是多线程**，是单帧内顺序调用两个子节点的 OnTick：

```
SimpleParallel.OnTick(ctx):
  ① mainStatus = tickChild(ChaseTarget, ctx)   // 先驱动追逐
  ② bgStatus  = tickChild(Repeater[攻击], ctx)  // 再驱动攻击
  ③ if mainCompleted:
       if finishMode == Immediate → 打断后台 → 返回 mainStatus
  ④ if bgStatus != Running && !mainCompleted:
       bg.OnExit(ctx)   // 后台完成但主任务还在 → 后台 OnExit
  ⑤ return Running      // 两者都还在跑
```

每帧两个子节点各推进一步，类似协程的协作式调度。

### 9.2 战斗进入完整流程

```
时间线 (ms)    事件
─────────────────────────────────────────
T+0           Brain 决策: feature_has_combat_target=true → plan=npc_combat
T+0           Executor: btRunner.Run("npc_combat")

T+16          BT Tick #1 — 进入 SimpleParallel:
              - Service: sync combat target to BB
              - Selector: Decorator has_combat_target=true → 进入 SimpleParallel
              - SimpleParallel.OnEnter → Running

              帧内 SimpleParallel.OnTick:
                ① tickChild(ChaseTarget):
                   - ChaseTarget.OnEnter: NavMesh追逐 → Running
                ② tickChild(Repeater):
                   - Repeater.OnEnter → 驱动 Sequence.OnEnter
                   - SelectCombatSkill.OnEnter: 距离15m → 选远程(1002) → Success
                   - NpcAttack.OnEnter: 设动画, is_aim=true → Running
```

### 9.3 边追逐边远程射击

```
T+16~T+200    每帧 SimpleParallel.OnTick:
                ① tickChild(ChaseTarget): 持续追逐, 更新路径 → Running
                ② tickChild(Repeater→NpcAttack): NpcAttack.OnTick → Running

T+216         命中帧:
                ① tickChild(ChaseTarget): → Running（NPC 仍在移动）
                ② tickChild(Repeater→NpcAttack):
                   - elapsed=200 ≥ hitDelayMs=200
                   - CheckRangedHit: 距离12m ≤ 30m ✓, 角度8° ≤ 15° ✓
                   - ApplyNpcDamage: 扣除玩家 30 HP
                   - BroadcastHitEvent → SceneEvent(HitData)
                   → Running

T+616         攻击完成:
                ① tickChild(ChaseTarget): → Running（继续追）
                ② tickChild(Repeater→NpcAttack):
                   - elapsed=600 ≥ durationMs=600
                   - FinishSkill: 设冷却 3000ms
                   → Success
                   NpcAttack.OnExit: 清 is_aim, is_fire
                ② Sequence → Success → Repeater Reset → 下一轮

T+632         新一轮攻击:
                ① tickChild(ChaseTarget): → Running（距离缩小到 2.5m）
                ② tickChild(Repeater→Sequence):
                   - SelectCombatSkill: 距离2.5m, 远程冷却中 → 选近战(1001)
                   - NpcAttack.OnEnter: 近战技能, anim_id=101 → Running
```

### 9.4 目标丢失 → 战斗结束

```
T+5000        ChaseTarget: 视野丢失超时 → Failed
              SimpleParallel: mainCompleted=true, finishMode=Immediate
              → 打断后台: Repeater.OnExit → NpcAttack.OnExit(清理动画状态)
              → SimpleParallel 返回 Failed

              Selector: SimpleParallel Failed → 尝试 ReturnToSchedule
              ReturnToSchedule.OnEnter → Success
              树完成 → TriggerCommand → Brain 重新决策
              → feature_has_combat_target=false → plan=daily_schedule
```

### 9.5 技能全部冷却中的行为

```
T+xxx         帧内 SimpleParallel.OnTick:
                ① tickChild(ChaseTarget): → Running（继续追）
                ② tickChild(Repeater→Sequence):
                   - SelectCombatSkill: 所有技能冷却中 → Failed
                   - Sequence → Failed
                   - Repeater: Reset → 下一帧重试

              效果: NPC 持续追逐，等冷却结束后自动恢复攻击
              （不会因为无技能可用而停止追逐）
```

## 10. BtContext 扩展

### 10.1 新增组件缓存

在 `BtContext` 中新增 `NpcSkillComp` 的懒加载缓存：

```go
// context.go 新增
type BtContext struct {
    // ... 现有字段 ...
    npcSkillComp     *cnpc.NpcSkillComp
    npcSkillCompOnce bool
}

func (ctx *BtContext) GetNpcSkillComp() *cnpc.NpcSkillComp {
    if !ctx.npcSkillCompOnce {
        ctx.npcSkillCompOnce = true
        if ctx.Scene != nil {
            ctx.npcSkillComp, _ = common.GetComponentAs[*cnpc.NpcSkillComp](
                ctx.Scene, ctx.EntityID, common.ComponentType_NpcSkill)
        }
    }
    return ctx.npcSkillComp
}
```

**同步更新**：
- `BtContext.Reset()` 中清除 `npcSkillComp` 和 `npcSkillCompOnce`
- `context_test.go` 的 `TestReset` 断言中新增对应检查

## 11. 文件清单

### 新增文件

| 文件 | 说明 |
|------|------|
| `ecs/com/cnpc/npc_skill_comp.go` | NpcSkillComp 组件定义 |
| `ecs/com/cnpc/npc_damage.go` | 独立伤害系统 |
| `ecs/com/cnpc/npc_hit_check.go` | 命中判定逻辑 |
| `bt/nodes/npc_attack.go` | NpcAttack 异步攻击节点 |
| `bt/nodes/npc_select_skill.go` | SelectCombatSkill 同步选择节点 |
| `bt/trees/npc_combat.json` | 战斗行为树 JSON |
| `config/RawTables/TownNpc/NpcSkill.xlsx` | 技能配置表 |
| `ecs/com/cnpc/npc_skill_config_index.go` | 配置索引 |

### 修改文件

| 文件 | 修改内容 |
|------|----------|
| `common/component_types.go` | 新增 `ComponentType_NpcSkill` |
| `bt/nodes/factory.go` | 注册 NpcAttack, SelectCombatSkill 节点 |
| `bt/context/context.go` | 新增 GetNpcSkillComp 缓存 |
| `bt/context/context_test.go` | TestReset 新增断言 |
| `bt/integration_test.go` | 3 处列表 + phased test 更新 |
| `ecs/system/sensor/misc_sensor.go` | 新增 combat target Feature |
| `ai_decision_bt/` 对应 NPC 配置 | 新增 npc_combat plan + transitions |
| NPC Entity 创建流程 | 挂载 NpcSkillComp |

## 12. 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| 玩家 HP 仅在 GAS AttributeSet 中 | 独立伤害系统仍需读写 GAS 属性 | 通过 ReadTargetHP/WriteTargetHP 桥接，隔离依赖 |
| NpcAttack 被 Abort 时打断处理 | 攻击动画中途被切换 plan | OnExit 统一清理，打断不补伤 |
| 近战分支和远程分支频繁切换 | 目标在 3m 边界来回移动导致抖动 | Decorator 加 hysteresis（3m 进入近战，4m 退出近战） |
| npc_combat 与 police_enforcement 冲突 | 同一 NPC 可能同时满足两种条件 | 通过 Brain 优先级排序，combat > enforcement |
| Service 200ms + Sensor 1s 延迟 | 战斗响应不够即时 | 关键状态变化直接写 BB 绕过 Service 链路 |
| 配置表打表工具兼容性 | NpcSkill.xlsx 格式不被 config_gen 识别 | 遵循已有表格式（参考 npc.xlsx 的行结构） |
