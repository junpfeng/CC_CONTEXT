# 根因分析报告 - Bug #1（V2_NPC）

## Bug 描述

大世界场景中看不到任何 NPC；点击小地图中 BigWorldNpc 图例开关后，小地图上仍无任何 NPC 标记。

---

## 直接原因

### 根因 A：服务端 `CreateDynamicBigWorldNpc` 未挂载 `AnimStateComp`

**文件**：`P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/scene_npc_mgr.go:331-388`

`CreateDynamicBigWorldNpc` 在创建 BigWorld NPC 实体时，只挂载了：
- `NpcMoveComp`（行 352-353）
- `SceneNpcComp`（行 355-365）

**漏挂了 `AnimStateComp`**。对照动物初始化（`animal_init.go:112`），动物实体明确调用了：
```go
entity.AddComponent(csystem.NewAnimStateComp())
```
但 BigWorld NPC 实体创建路径中没有此行。

---

### 根因 A 的完整传导链

```
CreateDynamicBigWorldNpc 未挂载 AnimStateComp
    ↓
getNpcMsg (net_update/npc.go:72) 调用 SetSyncComponentProto(ComponentType_AnimState)
    → 查不到组件 → res.AnimStateInfo = nil
    ↓
BtTickSystem.syncNpcStateToAnimComp (bt_tick_system.go:375)
    → GetComponentAs[AnimStateComp] 失败 → 静默 return
    → AnimStateComp 从未被写入，从未标脏，从未参与同步
    ↓
客户端收到 NpcDataUpdate，AnimStateInfo 字段为 nil
    ↓
NpcData.TryUpdateServerAnimStateData(nil) 直接 return（npc_data.go:280-283）
    → _serverAnimStateData 永远为 nil
    ↓
BigWorldNpcManager.SyncWithDataManager() (bigworld_npc_manager.cs:237)
    if (kvp.Value.ServerAnimStateData == null) continue;  // 过滤掉所有 BigWorld NPC
    ↓
_entityDict 始终为空 → 大世界无 NPC 渲染
```

---

### 根因 B：小地图图例初始化时立即自删

**文件**：`freelifeclient/Assets/Scripts/Gameplay/Modules/UI/Managers/Map/TagInfo/MapBigWorldNpcLegend.cs:36-46`

用户点击图例开关后，`LoadExistingBigWorldNpcLegends()` 为 `DataManager.Npcs` 中每个 NPC 创建图例，调用链为：
```
AddBigWorldNpcLegend → SetBigWorldNpcInfo → RefreshEntityWorldPos
```

`RefreshEntityWorldPos` 调用 `BigWorldNpcManager.TryGetNpc(id)`，由于 `_entityDict` 为空（根因 A 导致），返回 false，图例随即被 `RemoveLegend(this)` 移除。

> 根因 B 是根因 A 的直接后果：只要修复 A，B 自动消失。

---

## 根本原因分类

**遗漏检查**：新建 BigWorld NPC 实体时，参照了 `CreateSimpleNpc`（基础实体，有注释"不包含 NpcMoveComp"），但忘记同步参照动物初始化（`animal_init.go`）补充 `AnimStateComp`。V2 管线的 `syncNpcStateToAnimComp` 遇到缺失组件只做静默 return，没有日志警告，掩盖了问题。

---

## 影响范围

| 位置 | 影响 |
|------|------|
| `bt_tick_system.go:375` | `syncNpcStateToAnimComp` 静默跳过 → NPC 动画状态永不推送 |
| `getNpcMsg` → `AnimStateInfo` | 服务端帧同步中 BigWorld NPC 的 `anim_state_info` 永远为 nil |
| `BigWorldNpcManager.SyncWithDataManager` | 客户端所有 BigWorld NPC 被 `ServerAnimStateData == null` 过滤，永不生成 |
| `MapBigWorldNpcLegend.RefreshEntityWorldPos` | 图例创建后立即自删，小地图无 NPC 标记 |

---

## 修复方案

### 服务端（必须修复）

**文件**：`P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/scene_npc_mgr.go`

在 `CreateDynamicBigWorldNpc` 中，`NpcMoveComp` 挂载之后、`SceneNpcComp` 挂载之前，添加：

```go
// 挂载 AnimStateComp（V2 管线同步 NPC 动画状态到客户端，缺失时 AnimStateInfo=nil，客户端无法识别 V2 NPC）
animStateComp := csystem.NewAnimStateComp()
entity.AddComponent(animStateComp)
```

import 需补充：`"mp/servers/scene_server/internal/ecs/com/csystem"`（参考 `animal_init.go:6` 的引用方式）

### 客户端（无需修改）

客户端 `BigWorldNpcManager` 和小地图图例逻辑均正确；服务端修复后自动生效。

### 验证步骤

1. 服务端编译通过（`make build`）
2. 进入大世界场景，用 GM 命令 `/ke* gm bigworld npc status`（或等待 Spawner 自然生成）确认 NPC 出现在场景中
3. 客户端可见 NPC 在大世界移动
4. 打开小地图 → 点击 BigWorldNpc 图例 → 地图上出现 NPC 标记

---

## 是否需要固化防护

**是** — 建议在 `CreateDynamicBigWorldNpc` 加注释：
```go
// 必须挂载 AnimStateComp：客户端 BigWorldNpcManager 以 ServerAnimStateData!=nil 为 V2 管线判断依据
// 参考：animal_init.go 同样在实体创建时显式添加此组件
```

同时建议在 `syncNpcStateToAnimComp` 中补充 Warning 日志（当前静默 return 掩盖问题）：
```go
if !ok {
    log.Warnf("[BtTickSystem] syncNpcStateToAnimComp: AnimStateComp 缺失, npc_entity_id=%v", entityID)
    return
}
```

---

## 修复风险评估

**低** — 修改点单一，仅在 BigWorld NPC 实体创建时追加一个组件挂载，不影响任何现有 Town/Sakura/Animal NPC 的创建路径，不触碰协议和数据结构。
