# 射击系统 Rust→Go 迁移设计方案

## 1. 需求回顾

将 Rust 遗留工程 (`server_old/servers/scene/src/damage/`) 中的玩家射击系统迁移到 Go 版本 (`P1GoServer`)。

**最小可行范围**：
- Shot 事件处理（扣弹药 + 注册 + 广播）
- Hit 事件处理（验证 + 伤害 + 广播）
- Explosion 事件处理（验证 + 范围伤害 + 广播）
- CheckManager 反作弊验证

**暂缓**：
- 死亡/复活完整流程（SetDead 已有，复活逻辑暂不实现）
- NPC 射击（需 AI 行为树支持）
- 成长属性更新（UNIT_GROWTH_SHOOT）
- Crash/Fall 伤害（非射击核心）

---

## 2. 架构总览

### 2.1 消息流序列图

```
Client                    ActionHandler              damage pkg            SnapshotMgr
  │                           │                          │                     │
  │── ActionReq ─────────────>│                          │                     │
  │   (EventList: Shot+Hit)   │                          │                     │
  │                           │── HandleShotData ───────>│                     │
  │                           │                          │─ 扣弹药(EquipComp)  │
  │                           │                          │─ 注册(CheckManager) │
  │                           │                          │── AddEvent(Shot) ──>│
  │                           │                          │                     │
  │                           │── HandleHitData ────────>│                     │
  │                           │                          │─ 验证(CheckManager) │
  │                           │                          │─ CanTakeDamage()    │
  │                           │                          │─ DealDamage(GAS)    │
  │                           │                          │── AddEvent(Hit) ───>│
  │                           │                          │                     │
  │                           │                          │                     │
  │   (下一帧)                │                          │                     │
  │<──────────── FrameDataUpdate(包含 SceneEvent::Shot + SceneEvent::Hit) ────│
```

### 2.2 包结构

```
servers/scene_server/internal/
├── damage/                          ← 新增包
│   ├── check_manager.go             # CheckManager Resource（反作弊射击记录）
│   ├── shot.go                      # HandleShotData（射击事件）
│   ├── hit.go                       # HandleHitData（命中事件）
│   ├── explosion.go                 # HandleExplosionData（爆炸事件）
│   ├── damage.go                    # CanTakeDamage + DealDamage（伤害核心）
│   └── event.go                     # addSceneEvent 辅助函数
│
├── net_func/action/
│   └── action.go                    ← 修改：事件分发到 damage 包
│
├── common/
│   └── resource_type.go             ← 修改：新增 ResourceType_CheckManager
│
└── scene 初始化代码                   ← 修改：注册 CheckManager Resource
```

---

## 3. 详细设计

### 3.1 CheckManager（反作弊验证）

**对标 Rust**: `server_old/servers/scene/src/damage/check.rs`

**职责**: 记录玩家每次射击，Hit 上报时验证是否有对应的 Shot 记录。

```go
// damage/check_manager.go

package damage

// CheckManager 射击验证管理器（场景级 Resource）
// 每个场景一个实例，追踪所有玩家的射击记录用于反作弊验证
type CheckManager struct {
    common.ResourceBase
    userMap map[uint64]*shotInfoByUser // entityID → 射击记录
}

type shotInfoByUser struct {
    entityID  uint64
    uniqueMap map[int64]*shotInfo // unique → 射击信息
}

type shotInfo struct {
    weaponID   int32
    unique     int64
    createTime int64 // 秒级时间戳
    shotNum    int32 // 剩余弹丸数（霰弹枪多弹丸）
}
```

**核心方法**:

| 方法 | 调用时机 | 行为 |
|------|----------|------|
| `AddShotInfo(entityID, weaponID, unique)` | Shot 事件处理 | 记录射击，scatter_count 从 CfgGunFeature 读取，默认 1 |
| `CheckShotInfo(entityID, weaponID, unique) bool` | Hit 事件处理 | 验证匹配 + 递减 shotNum，归零移除，不匹配返回 false |
| `CheckExplosionInfo(entityID, unique) bool` | Explosion 事件处理 | 验证存在 + 武器类型为火箭筒 |
| `CleanupExpired()` | 每次 AddShotInfo 时附带清理 | 移除超过 15 秒的记录 |

**常量**:
```go
const shotMaxDelaySec = 15 // 射击记录最大存活时间（秒）
```

**Resource 注册**:
- 新增 `ResourceType_CheckManager` 到 `common/resource_type.go`
- 场景初始化时创建并注册

### 3.2 Shot 事件处理

**对标 Rust**: `server_old/servers/scene/src/damage/shot.rs`

```go
// damage/shot.go

// HandleShotData 处理射击事件
// 1. 验证射击者有武器
// 2. 扣减弹药（仅玩家）
// 3. 在 CheckManager 注册射击记录
// 4. 广播 SceneEvent::Shot
func HandleShotData(scene common.Scene, shooterEntity common.Entity, unique int64, shotData *proto.ShotData)
```

**流程**:

```
HandleShotData(scene, entity, unique, shotData)
│
├─ 1. 获取 EquipComp → 当前武器
│     if 无武器 → return（NPC 无需验证）
│
├─ 2. weaponFire(scene, entity) → 扣弹药
│     ├─ 获取 EquipComp.WeaponList[ActiveWeaponCellIndex]
│     ├─ 找 BULLETCURRENT 属性（config.GAS_ATTRIBUTE_ITEM_PROPERTY_BULLETCURRENTGAMEPLAYFLAG = 191）
│     ├─ curValue <= 0 → return false（无弹药）
│     ├─ curValue -= 1.0
│     ├─ 标记 EquipComp dirty（SetSync + SetSave）
│     └─ return true
│
├─ 3. CheckManager.AddShotInfo(entityID, weaponID, unique)
│     ├─ 从 CfgGunFeature 读取 scatterCount（默认 1）
│     └─ 附带清理过期记录
│
└─ 4. addSceneEvent(scene, proto.NewSceneEventShot(shotData))
```

**弹药扣减细节**:

EquipComp 持有 `[]*proto.WeaponCellInfo`，其中包含武器的 proto 数据。弹药属性 `BULLETCURRENT` 存储在武器的 `AttributeSet` 中。

需要实现的辅助函数:
```go
// weaponFire 扣减当前武器弹药
// 返回 false 表示无法射击（无武器/无弹药）
func weaponFire(scene common.Scene, entity common.Entity) bool
```

实现时需验证 EquipComp → BackpackComp 的数据同步路径（Rust 中扣减后会同步回 BackpackComp）。

### 3.3 Hit 事件处理

**对标 Rust**: `server_old/servers/scene/src/damage/hit.rs`

```go
// damage/hit.go

// HandleHitData 处理命中事件
// 1. 基础验证（非自伤、武器合法）
// 2. CheckManager 验证射击匹配（仅玩家）
// 3. 伤害验证与结算
// 4. 广播 SceneEvent::Hit
func HandleHitData(scene common.Scene, attackerEntity common.Entity, unique int64, hitData *proto.HitData)
```

**流程**:

```
HandleHitData(scene, attacker, unique, hitData)
│
├─ 1. 基础验证
│     ├─ hitData.TargetEntity == attacker.ID() → return（禁止自伤）
│     └─ hitData.Damage > 0 && hitData.WeaponId == 0 → return（有伤害必须有武器）
│
├─ 2. CheckManager 验证（仅玩家攻击者）
│     ├─ isPlayer(attacker) → CheckManager.CheckShotInfo(entityID, weaponID, unique)
│     └─ 返回 false → return（无匹配的射击记录，拒绝命中）
│
├─ 3. 获取目标实体
│     └─ scene.GetEntity(hitData.TargetEntity) → targetEntity
│
├─ 4. 伤害验证与结算
│     ├─ canTakeDamage(scene, attacker, target) → (bool, HitResultType)
│     │   ├─ false → 广播 Invincible 结果后 return
│     │   └─ true → 继续
│     ├─ DealDamage(scene, attacker, target, hitData)
│     │   ├─ 修改目标 GasComp 生命值
│     │   ├─ 生命值 <= 0 → BaseStatusComp.SetDead()
│     │   └─ 处理红名后果
│     └─ hitData.HitResult = hitResultType
│
└─ 5. addSceneEvent(scene, proto.NewSceneEventHit(hitData))
```

### 3.4 Explosion 事件处理

**对标 Rust**: `server_old/servers/scene/src/damage/explosion.rs`

```go
// damage/explosion.go

// HandleExplosionData 处理爆炸事件
// 1. CheckManager 验证（仅玩家，且武器必须是火箭筒类型）
// 2. 根据 CfgExplosionEvent/CfgDestructEvent 计算范围伤害
// 3. 对主目标 + 范围内实体造成伤害
// 4. 广播 SceneEvent::Explosion
func HandleExplosionData(scene common.Scene, attackerEntity common.Entity, unique int64, explosionData *proto.ExplosionData)
```

**流程**:

```
HandleExplosionData(scene, attacker, unique, explosionData)
│
├─ 1. CheckManager 验证（仅玩家）
│     └─ CheckManager.CheckExplosionInfo(entityID, unique) → false → return
│
├─ 2. 加载爆炸配置
│     └─ config.GetCfgExplosionEventById(explosionData.ExplosionId)
│         ├─ mainEntityDamage: 直接命中伤害
│         └─ damageList: [(距离, 伤害)] 衰减列表
│
├─ 3. 确定爆炸中心
│     ├─ explosionData.TargetEntity != 0 → 目标实体位置
│     └─ 否则 → explosionData.Position
│
├─ 4. 对主目标造成伤害
│     └─ if mainEntityDamage > 0 && targetEntity 存在
│         → DealDamage(scene, attacker, target, mainEntityDamage)
│
├─ 5. 范围伤害（遍历场景实体）
│     ├─ 计算每个实体到爆炸中心的距离
│     ├─ 匹配 damageList 中最近的距离档位
│     └─ DealDamage(scene, attacker, entityInRange, rangeDamage)
│
└─ 6. addSceneEvent(scene, proto.NewSceneEventExplosion(...))
```

**范围查询**: 使用 GridMgr 或直接遍历附近实体（MVP 阶段可简化）。

### 3.5 伤害核心逻辑

**对标 Rust**: `server_old/servers/scene/src/damage/damage.rs`

#### 3.5.1 CanTakeDamage 验证

```go
// damage/damage.go

// canTakeDamage 验证目标是否可以受到伤害
// 返回 (能否受伤, 命中结果类型)
func canTakeDamage(scene common.Scene, attacker, target common.Entity) (bool, proto.HitResultType)
```

**验证链**（按 Rust 逻辑移植）:

```
canTakeDamage(scene, attacker, target)
│
├─ 1. 自伤检查
│     └─ attacker.ID() == target.ID() → (false, Invincible)
│
├─ 2. 目标已死亡检查
│     └─ BaseStatusComp.IsDead() → (false, Invincible)
│
├─ 3. 场景类型分流
│     ├─ 副本场景 → canTakeDamageInDungeon()
│     │   └─ 同阵营（CampComp.CampId 相同且 != 0）→ (false, Invincible)
│     │
│     └─ 大世界场景 → canTakeDamageInMainWorld()
│         ├─ 玩家 vs 玩家:
│         │   ├─ 双方都是白名（WantedLevel == 0）→ (false, Invincible)
│         │   ├─ 攻击者被动模式 → 只能打红名
│         │   └─ 目标被动模式 → (false, Invincible)
│         │
│         └─ NPC vs 玩家:
│             ├─ 目标白名 → (false, Invincible)
│             └─ 目标被动模式 → (false, Invincible)
│
├─ 4. 交互免疫检查
│     └─ PersonInteraction 组件中有活跃交互 → (false, Invincible)
│
└─ return (true, Common)
```

#### 3.5.2 DealDamage 伤害结算

```go
// DealDamage 对目标造成伤害
// 返回 (实际伤害值, 是否击杀)
func DealDamage(scene common.Scene, attacker, target common.Entity, damage int32) (int32, bool)
```

**流程**:

```
DealDamage(scene, attacker, target, damage)
│
├─ 1. 获取目标 GasComp
│     └─ 失败 → return (0, false)
│
├─ 2. 读取当前生命值
│     └─ GasComp.AttributeSet.GetValue(GAS_ATTRIBUTE_UNIT_COMBAT_HEALTH_CURRENT)
│
├─ 3. 扣减生命值
│     ├─ newHealth = max(0, currentHealth - float64(damage))
│     └─ GasComp.AttributeSet.SetValue(healthKey, newHealth)
│
├─ 4. 标记脏
│     └─ GasComp.SetSync()
│
├─ 5. 死亡判定
│     ├─ newHealth <= 0
│     │   ├─ BaseStatusComp.SetDead()
│     │   └─ addSceneEvent(scene, proto.NewSceneEventKill(...))
│     └─ return (damage, killed)
│
└─ 6. 红名后果处理
      ├─ handlePlayerAttackNpc(scene, attacker, target)
      │   └─ 攻击城市NPC → 攻击者变红名（WantedLevel = 1）
      └─ handlePassiveModeConsequences(scene, attacker, target)
          └─ 被动模式玩家攻击其他玩家 → 退出被动模式
```

### 3.6 Scene Event 广播辅助

```go
// damage/event.go

// addSceneEvent 将事件添加到当前帧缓存，由 net_update 系统广播
func addSceneEvent(scene common.Scene, event *proto.SceneEvent) {
    snapshotMgr, ok := common.GetResourceAs[*resource.SnapshotMgr](
        scene, common.ResourceType_SnapshotMgr,
    )
    if !ok {
        scene.Error("[Damage] SnapshotMgr not found")
        return
    }
    snapshotMgr.Cache.AddEvent(event)
}
```

已有的 Proto 工厂函数（无需新增）:
- `proto.NewSceneEventShot(&proto.ShotData{...})`
- `proto.NewSceneEventHit(&proto.HitData{...})`
- `proto.NewSceneEventExplosion(&proto.ExplosionInfo{...})`
- `proto.NewSceneEventKill(&proto.KillInfo{...})`

### 3.7 ActionHandler 事件分发

**修改文件**: `net_func/action/action.go`

将现有的 TODO 区块替换为事件分发逻辑:

```go
// action.go 第 111-128 行
if len(req.EventList) > 0 {
    for _, event := range req.EventList {
        if event.EventInfo == nil {
            continue
        }
        switch info := event.EventInfo.Data.(type) {
        case *proto.UploadEventInfoShot:
            shotData := (*proto.ShotData)(info)
            damage.HandleShotData(h.scene, h.playerEntity, event.Unique, shotData)
        case *proto.UploadEventInfoHit:
            hitData := (*proto.HitData)(info)
            damage.HandleHitData(h.scene, h.playerEntity, event.Unique, hitData)
        case *proto.UploadEventInfoExplosion:
            explosionData := (*proto.ExplosionData)(info)
            damage.HandleExplosionData(h.scene, h.playerEntity, event.Unique, explosionData)
        case *proto.UploadEventInfoCrash:
            // TODO: Phase 2 实现
        case *proto.UploadEventInfoFall:
            // TODO: Phase 2 实现
        }
    }
}
```

---

## 4. 涉及文件清单

### 4.1 新增文件

| 文件 | 说明 |
|------|------|
| `servers/scene_server/internal/damage/check_manager.go` | CheckManager Resource |
| `servers/scene_server/internal/damage/shot.go` | Shot 事件处理 |
| `servers/scene_server/internal/damage/hit.go` | Hit 事件处理 |
| `servers/scene_server/internal/damage/explosion.go` | Explosion 事件处理 |
| `servers/scene_server/internal/damage/damage.go` | 伤害验证与结算核心 |
| `servers/scene_server/internal/damage/event.go` | SceneEvent 辅助函数 |

### 4.2 修改文件

| 文件 | 修改内容 |
|------|----------|
| `servers/scene_server/internal/common/resource_type.go` | 新增 `ResourceType_CheckManager` |
| `servers/scene_server/internal/net_func/action/action.go` | 替换 TODO，分发事件到 damage 包 |
| 场景初始化文件（scene_impl.go 或类似） | 注册 CheckManager Resource |

### 4.3 不需修改

| 类别 | 说明 |
|------|------|
| Proto 定义 | ShotData/HitData/ExplosionData/SceneEvent 全部已存在 |
| 配置文件 | CfgWeapon/CfgGun/CfgGunFeature/CfgExplosionEvent 已生成 |
| GAS 常量 | BULLETCURRENT/HEALTH_CURRENT/HEALTH_MAX 已定义 |
| 消息缓存 | message_cache.go AddEvent 已支持（自动生成文件） |

---

## 5. 关键 API 依赖

### 5.1 现有组件访问

```go
// EquipComp - 获取当前武器
equipComp, ok := common.GetComponentAs[*cbackpack.EquipComp](scene, entityID, common.ComponentType_Equip)
weaponCell := equipComp.WeaponList[equipComp.ActiveWeaponCellIndex]

// GasComp - 读写生命值
gasComp, ok := common.GetComponentAs[*cgas.GasComp](scene, entityID, common.ComponentType_Gas)
health := gasComp.AttributeSet.GetValue(cgas.GAS_ATTRIBUTE_UNIT_COMBAT_HEALTH_CURRENT)
gasComp.AttributeSet.SetValue(cgas.GAS_ATTRIBUTE_UNIT_COMBAT_HEALTH_CURRENT, newHealth)

// BaseStatusComp - 死亡状态
baseStatus, ok := common.GetComponentAs[*cperson.BaseStatusComp](scene, entityID, common.ComponentType_BaseStatus)
baseStatus.IsDead()
baseStatus.SetDead()

// WantedComp - 红名/被动模式
wantedComp, ok := common.GetComponentAs[*cplayer.WantedComp](scene, entityID, common.ComponentType_Wanted)
wantedComp.IsRedName()
wantedComp.PassiveMode

// CampComp - 阵营
campComp, ok := common.GetComponentAs[*csocial.CampComp](scene, entityID, common.ComponentType_Camp)
campComp.CampId
```

### 5.2 GAS 常量

```go
// 弹药（武器 AttributeSet）
config.GAS_ATTRIBUTE_ITEM_PROPERTY_BULLETCURRENTGAMEPLAYFLAG  // 191 - 当前弹药数

// 生命值（实体 GasComp.AttributeSet）
cgas.GAS_ATTRIBUTE_UNIT_COMBAT_HEALTH_CURRENT  // 6050010 - 当前生命
cgas.GAS_ATTRIBUTE_UNIT_COMBAT_HEALTH_MAX      // 6050009 - 最大生命
```

### 5.3 SceneEvent 广播

```go
// 通过 SnapshotMgr.Cache.AddEvent() 添加到当前帧
// net_update 系统自动在帧末通过 FrameDataUpdate 广播给所有订阅者
snapshotMgr.Cache.AddEvent(proto.NewSceneEventShot(shotData))
```

---

## 6. Rust→Go 对标映射

| Rust 文件 | Go 文件 | 关键函数映射 |
|-----------|---------|-------------|
| `damage/shot.rs:handle_shot_data` | `damage/shot.go:HandleShotData` | 扣弹药 + 注册 + 广播 |
| `damage/shot.rs:weapon_fire` | `damage/shot.go:weaponFire` | BULLETCURRENT -= 1 |
| `damage/hit.rs:handle_hit_data` | `damage/hit.go:HandleHitData` | 验证 + 伤害 + 广播 |
| `damage/damage.rs:attack` | `damage/damage.go:DealDamage` | GAS 扣血 + 死亡判定 |
| `damage/damage.rs:can_take_damage` | `damage/damage.go:canTakeDamage` | 多层验证链 |
| `damage/damage.rs:deal_damage` | `damage/damage.go:DealDamage` | 直接扣血模式 |
| `damage/check.rs:CheckManager` | `damage/check_manager.go:CheckManager` | 射击记录验证 |
| `damage/explosion.rs:handle_explosion_data` | `damage/explosion.go:HandleExplosionData` | 范围伤害 |
| `damage/explosion.rs:del_explosion` | `damage/explosion.go:applyExplosionDamage` | 距离衰减伤害 |

---

## 7. 实现注意事项

### 7.1 弹药扣减的数据路径

EquipComp 存储的是 `[]*proto.WeaponCellInfo`（proto 数据），而非 `*citem.Weapon` 对象。实现 `weaponFire()` 时需要：

1. 从 `WeaponCellInfo` 提取武器 proto 数据
2. 找到 BULLETCURRENT 属性并扣减
3. 确认是否需要同步回 BackpackComp（Rust 中有此步骤）
4. 标记 EquipComp dirty

**实现时需验证**: `WeaponCellInfo` 的完整结构以及与 `BackpackComp` 的数据关系。

### 7.2 实体类型判断

Rust 通过 `is_player_or_vehicle` 等函数判断实体类型。Go 中需要通过检查组件是否存在来判断：

```go
// 判断是否为玩家
func isPlayer(scene common.Scene, entityID uint64) bool {
    _, ok := common.GetComponentAs[*cplayer.PlayerComp](scene, entityID, common.ComponentType_PlayerBase)
    return ok
}
```

### 7.3 爆炸范围查询

MVP 阶段可简化范围查询：
- 方案 A: 通过 GridMgr 查询附近格子内的实体（高效）
- 方案 B: 遍历 PlayerManager 所有玩家 + 场景 NPC 列表，过滤距离（简单）

建议 MVP 用方案 B，后续优化用方案 A。

### 7.4 时间函数

根据 `go-style.md` 规范，**禁止使用 `time.Now()`**，必须使用：
```go
mtime.NowSecondTickWithOffset()  // 秒级时间戳（CheckManager 超时判断）
```

### 7.5 并发安全

ActionHandler 在 RPC goroutine 中执行。需确认：
- 场景的 RPC 处理是否单线程（串行处理所有 RPC）
- CheckManager 是否需要加锁

如果场景 RPC 是单线程的（通常游戏服务器如此），则不需要额外锁。

### 7.6 自动生成文件

以下文件不可修改（`go-style.md` 规范）：
- `common/config/cfg_*.go`
- `*_pb.go`
- `common/proto/scene_service.go`
- `servers/scene_server/internal/common/message_cache.go`

---

## 8. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| WeaponCellInfo 结构未完全理解 | 弹药扣减无法实现 | 实现时先读完 proto 定义，必要时跳过弹药扣减先做验证+广播 |
| GasComp 扣血与现有 GAS Effect 系统冲突 | 直接扣血绕过效果系统 | MVP 直接扣血，后续对齐 GAS Effect 管线 |
| 副本/大世界场景类型判断方式不明 | can_take_damage 分流失败 | 实现时搜索现有场景类型判断代码 |
| 爆炸范围遍历性能 | 大量实体时卡顿 | MVP 先简单遍历，后续用 GridMgr 优化 |

---

## 9. 验收标准

- [ ] `make build` 编译通过
- [ ] Shot 事件：玩家射击时弹药正确扣减，SceneEvent::Shot 广播给场景内所有玩家
- [ ] Hit 事件：CheckManager 正确验证 Shot-Hit 匹配，目标生命值正确扣减
- [ ] Explosion 事件：范围内实体按距离衰减受到伤害
- [ ] 反作弊：无对应 Shot 记录的 Hit 被拒绝；15 秒超时的 Shot 记录自动清理
- [ ] 伤害验证：被动模式免疫、白名互免、同阵营互免、死亡目标免疫
- [ ] 死亡判定：生命值归零时 BaseStatusComp.SetDead() 被调用，SceneEvent::Kill 广播
