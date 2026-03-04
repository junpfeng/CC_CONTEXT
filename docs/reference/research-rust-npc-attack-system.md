# Rust 服务器 NPC 攻击玩家系统 - 深度技术调研

> 调研目标：完整理解 server_old/ 中 NPC 攻击玩家的全链路设计，为 Go 版本迁移提供参考
> 调研时间：2026-02-26
> 基础路径：`/home/miaoriofeng/workspace/server/server_old/`

---

## 目录

1. [架构总览](#1-架构总览)
2. [仇恨系统 (Hate System)](#2-仇恨系统)
3. [伤害系统 (Damage System)](#3-伤害系统)
4. [行为树攻击节点](#4-行为树攻击节点)
5. [AI 决策层与 MonsterComp](#5-ai-决策层与-monstercomp)
6. [协议定义与配置](#6-协议定义与配置)
7. [网络同步](#7-网络同步)

---

## 1. 架构总览

NPC 攻击玩家通过 5 层架构实现：

```
决策层 (AI Decision)
  │  Brain 决策系统，1秒周期，驱动状态转移
  ↓
仇恨层 (Hate System)
  │  维护 NPC 对玩家的仇恨值，管理攻击目标
  ↓
行为层 (Behavior Tree)
  │  执行具体的目标选择、瞄准、射击动作
  ↓
伤害层 (Damage System)
  │  验证伤害合法性、计算伤害、处理死亡
  ↓
网络层 (Sync)
     状态同步、事件广播、AOI 管理
```

### 完整攻击流程

```
玩家进入 AOI → 成为 NPC 主控者(master_entity) → 行为树激活
  ↓
BtActGetNearFovTarget → 视野内选目标 → BtCondWithinDistance → 距离检查
  ↓
BtActChangeFireMode(连射) → BtActSetFireState(持枪+瞄准)
  ↓
BtActCustomFire_New → NpcFireControl 按间隔队列逐发射击
  ↓
客户端报送 HitData → 服务器 can_take_damage() 验证
  ↓
attack() → bp_function_apply_damage() → trigger 系统 → deal_damage() → modify_attribute() 扣血
  ↓
仇恨值更新(+10/点伤害) → 死亡检查 → 事件广播
```

### 关键文件索引

| 模块 | 文件路径 | 行数 | 职责 |
|------|---------|------|------|
| 仇恨系统 | `servers/scene/src/hate_system.rs` | 200+ | 仇恨增减、衰减、清理 |
| 仇恨组件 | `servers/scene/src/entity_comp/hate_comp.rs` | 132 | HateComp 数据结构 |
| 反向仇恨 | `servers/scene/src/entity_comp/reverse_hate_comp.rs` | ~60 | ReverseHateComp |
| 伤害核心 | `servers/scene/src/damage/damage.rs` | 597 | 伤害计算、红名系统 |
| 击中处理 | `servers/scene/src/damage/hit.rs` | 60 | HitData 入口、校验 |
| 射击处理 | `servers/scene/src/damage/shot.rs` | 114 | 弹药扣减、广播 |
| 碰撞伤害 | `servers/scene/src/damage/crash.rs` | 89 | 碰撞伤害 |
| 爆炸伤害 | `servers/scene/src/damage/explosion.rs` | 143 | 范围伤害 |
| 反作弊 | `servers/scene/src/damage/check.rs` | 125 | 射击信息管理 |
| 行为树节点 | `servers/scene/src/ai/behavior_tree/bt_node.rs` | 269KB | 全部节点实现 |
| 射击控制 | `servers/scene/src/ai/npc_fire_control.rs` | 95 | NpcFireControl |
| 动画状态 | `servers/scene/src/ai/ai_anim_state.rs` | 153 | AnimStateComp |
| AI 组件 | `servers/scene/src/ai/ai.rs` | ~100 | AiComp |
| AI 控制 | `servers/scene/src/ai/ai_control.rs` | 266 | 控制权分配 |
| NPC 组件 | `servers/scene/src/entity_comp/npc/monster_comp.rs` | 282 | MonsterComp |
| 同步状态机 | `servers/scene/src/entity_comp/npc/npc_fsm/sync_state/` | - | NpcSyncFsm |
| 逻辑状态机 | `servers/scene/src/entity_comp/npc/npc_fsm/logic_state/` | - | NpcLogicFsm |
| 战术状态机 | `servers/scene/src/entity_comp/npc/npc_fsm/tactic_state/` | - | NpcTacticFsm |
| 属性修改 | `servers/scene/src/gas/attribute/func.rs` | 274+ | GAS 属性系统 |
| 死亡处理 | `servers/scene/src/entity_comp/base_status/func.rs` | 432 | 死亡事件 |

---

## 2. 仇恨系统

### 2.1 数据结构

#### HateComp（NPC 仇恨组件）

```rust
pub struct HateComp {
    pub hate_map: HashMap<Entity, i32>,    // 玩家Entity → 仇恨值
    pub max_hate_targets: usize,           // 最大仇恨目标数 = 5
    pub hate_decay_per_second: i32,        // 每秒衰减值 = 3
    pub last_decay_time: u64,              // 上次衰减时间戳(秒)
    pub is_dirty: bool,                    // 脏标记(网络同步)
}
```

#### ReverseHateComp（玩家反向仇恨组件）

```rust
pub struct ReverseHateComp {
    pub npc_hate_set: HashSet<Entity>,    // 对该玩家有仇恨的 NPC 集合
    pub is_dirty: bool,
}
```

### 2.2 公开方法

#### HateComp 方法

| 方法 | 签名 | 功能 |
|------|------|------|
| `new()` | `fn new() -> Self` | 创建, max=5, decay=3 |
| `add_hate()` | `fn add_hate(&mut self, player: Entity, value: i32)` | 增加仇恨, 超容量淘汰最低 |
| `get_highest_hate_target()` | `fn get_highest_hate_target(&self) -> Option<Entity>` | 获取最高仇恨目标 |
| `update_hate_decay()` | `fn update_hate_decay(&mut self) -> Vec<Entity>` | 衰减, 返回被移除的玩家 |
| `remove_hate()` | `fn remove_hate(&mut self, player: Entity)` | 立即移除仇恨 |

#### ReverseHateComp 方法

| 方法 | 签名 | 功能 |
|------|------|------|
| `new()` | `fn new() -> Self` | 创建 |
| `add_npc_hate()` | `fn add_npc_hate(&mut self, npc: Entity)` | 添加 NPC |
| `remove_npc_hate()` | `fn remove_npc_hate(&mut self, npc: Entity)` | 移除 NPC |
| `get_npc_hate_list()` | `fn get_npc_hate_list(&self) -> Vec<Entity>` | 获取全部 NPC |
| `clear_all_npc_hate()` | `fn clear_all_npc_hate(&mut self)` | 清空 |

### 2.3 仇恨增加触发点

#### 触发点 1: 玩家攻击 NPC（NPC 受伤）

```rust
// hate_system.rs:36-68
pub fn on_npc_damaged(world, damaged_entity, attacker_entity, damage_value) {
    // 仇恨增加公式: max(damage, 1) * 10
    let hate_increase = (damage_value as i32).max(1) * 10;
    hate_comp.add_hate(attacker_entity, hate_increase);
    // 同时添加反向索引
    reverse_hate_comp.add_npc_hate(damaged_entity);
}
```

#### 触发点 2: NPC 攻击玩家

```rust
// hate_system.rs:71-98
pub fn on_npc_attack_player(world, attacker_entity, target_entity, damage_value) {
    // 同样公式，巩固目标锁定
    let hate_increase = (damage_value as i32).max(1) * 10;
    hate_comp.add_hate(target_entity, hate_increase);
    // 注意：NPC 攻击时不更新反向索引
}
```

#### 触发点 3: 伤害事件系统集成

```rust
// damage.rs:150-157 — 仅在 deal_damage() 路径中
// 伤害发生后同时调用:
on_npc_damaged(cell_world, target, attacker_entity, damage as f32);
on_npc_attack_player(cell_world, attacker_entity, target, damage as f32);
// ⚠️ 双重触发问题（仅 deal_damage() 路径）：
//   deal_damage() 既通过 on_trigger_happened() 触发仇恨函数，
//   又直接调用 on_npc_damaged/on_npc_attack_player，导致仇恨翻倍
//   attack() 路径不受影响（只通过 trigger 事件触发仇恨）
```

### 2.4 仇恨衰减机制

```rust
// hate_comp.rs:91-123
pub fn update_hate_decay(&mut self) -> Vec<Entity> {
    let now = DateTime::local_now_stamp_sec();
    let time_diff = now - self.last_decay_time;
    if time_diff >= 1 {
        // 衰减公式: 3 * time_diff
        let decay_amount = self.hate_decay_per_second * time_diff as i32;
        // 所有目标衰减，≤0 的移除
        // ...
    }
}
```

| 参数 | 值 |
|------|-----|
| 衰减频率 | 每秒 1 次 |
| 衰减速率 | 3 点/秒 |
| 衰减公式 | `3 × 经过秒数` |
| 移除条件 | 仇恨值 ≤ 0 |

| 初始伤害 | 初始仇恨 | 完全消失时间 |
|---------|---------|-------------|
| 1 | 10 | ~4 秒 |
| 10 | 100 | ~34 秒 |
| 30 | 300 | ~100 秒 |
| 100 | 1000 | ~334 秒 |

### 2.5 容量限制与淘汰

- **最大目标数**: 5
- **淘汰策略**: LRH (Lowest Remaining Hate) — 移除仇恨值最低的
- **触发时机**: `add_hate()` 导致超过 5 个目标时

### 2.6 仇恨清理

#### 玩家死亡清理

```rust
// hate_system.rs
pub fn on_player_death(world, player_entity) {
    // 1. 从反向索引获取所有仇恨 NPC
    let npc_list = reverse_hate_comp.get_npc_hate_list();
    // 2. 逐个 NPC 移除该玩家的仇恨
    for npc in npc_list { hate_comp.remove_hate(player); }
    // 3. 清空反向索引
    reverse_hate_comp.clear_all_npc_hate();
}
```

#### 衰减后清理

```rust
// hate_system.rs:21-31 — 每帧调用
pub fn update_hate_system(world, hate_query) {
    for (npc, hate_comp) in hate_query {
        let removed = hate_comp.update_hate_decay();
        for player in removed {
            reverse_hate_comp.remove_npc_hate(npc);
        }
    }
}
```

### 2.7 仇恨系统与 AI 决策交互

```rust
// bt_node.rs:6131-6151 — 行为树节点
pub struct BtActGetHighestHateTarget {
    target_target: BlackBoardCell<Option<Entity>>,
}
// tick(): 从 HateComp 获取最高仇恨目标 → 写入黑板
```

### 2.8 调用关系图

```
伤害发生 → on_npc_damaged() / on_npc_attack_player()
         → HateComp.add_hate() → 超容量则淘汰
         → ReverseHateComp.add_npc_hate()

每帧衰减 → update_hate_system()
         → HateComp.update_hate_decay() → 移除 ≤0 的
         → ReverseHateComp.remove_npc_hate()

玩家死亡 → on_player_death()
         → 查 ReverseHateComp → 逐个清除 → 清空反向索引

AI 决策  → BtActGetHighestHateTarget.tick()
         → HateComp.get_highest_hate_target() → 写入黑板
```

---

## 3. 伤害系统

### 3.1 伤害类型

```rust
pub enum DamageType {
    Attack,      // 攻击伤害（枪械/近战）
    Crash,       // 碰撞伤害（载具）
    Fall,        // 坠落伤害
    Explosion,   // 爆炸伤害
    Force,       // 强制伤害
}
```

### 3.2 完整伤害流程

#### 主入口: handle_hit_data()

```rust
// hit.rs:15-60
pub fn handle_hit_data(world, unique, hit_data) {
    // 1. 输入验证: target!=0, target!=attacker, damage>0需weapon_id
    // 2. 玩家需 CheckManager 校验射击信息(防作弊)
    // 3. 更新射击成长属性(头射+1分)
    // 4. 调用 attack() 处理伤害
    // 5. 广播 SceneEvent::Hit
}
```

#### 核心: attack()

```rust
// damage.rs:40-100
pub fn attack(world, attacker, target, hit_info) -> (i32, HitResultType) {
    // 1. can_take_damage() 验证
    // 2. bp_function_apply_damage() 计算最终伤害(BP 函数)
    //    → BP 函数内部通过 trigger 系统调用 deal_damage() → modify_attribute() 实际扣血
    // 3. 触发 NewTriggerEventHappened::Damaged 事件（仇恨更新在此触发）
    // 返回 (伤害值, HitResultType::Common)
    // 注意：attack() 本身不直接修改血量，实际扣血链路是：
    // attack() → bp_function_apply_damage() → trigger → deal_damage() → modify_attribute()
}
```

#### 通用伤害: deal_damage()

```rust
// damage.rs:103-177 — 用于碰撞/爆炸/坠落等
pub fn deal_damage(world, source, target, damage, damage_type) {
    // 1. can_take_damage() 验证
    // 2. 检查目标是否已死
    // 3. modify_attribute() 修改血量
    // 4. 设置死亡信息(DeadInfo)
    // 5. 触发伤害事件
    // 6. 仇恨系统处理: on_npc_damaged() + on_npc_attack_player()
    // 7. 红名系统处理: handle_player_attack_npc() + handle_passive_mode_attack_consequences()
    // 8. 死亡处理: on_kill() + SceneEvent::Kill
}
```

### 3.3 伤害验证: can_take_damage()

```rust
// damage.rs:179-226
pub fn can_take_damage(world, attacker, target) -> (bool, HitResultType) {
    // 1. 场景类型判断
    //    - 副本: 同阵营不可攻击
    //    - 主世界: 红名系统检查
    // 2. 交互状态: 正在交互则无敌
    // 3. 自己不能伤害自己
    // 4. BaseStatusComp 检查: 已死亡/无敌
}
```

### 3.4 红名系统详细逻辑

#### 玩家 vs 玩家

```rust
// damage.rs:353-420
fn check_wanted_status_can_attack(world, attacker, target) -> bool {
    // 规则:
    // - 被动模式玩家只能攻击红名玩家
    // - 红名玩家不能攻击被动模式玩家
    // - 白名玩家之间不能相互攻击
    // - 红名玩家可以攻击红名玩家
}
```

#### NPC vs 玩家

```rust
// damage.rs:423-470
fn check_wanted_status_npc_attack_player(world, attacker, target) -> bool {
    // 规则:
    // - NPC 只能攻击红名玩家(is_wanted=true)
    // - NPC 不能攻击被动模式玩家
    // - NPC 不能攻击白名玩家
}
```

#### 玩家攻击 NPC 触发红名

```rust
fn handle_player_attack_npc(world, attacker, target) {
    // - 攻击城市 NPC(CITYNPC_MASTER flag) → 玩家进入红名
    // - 大世界任务中不触发红名
}
```

#### 被动模式攻击后果

```rust
fn handle_passive_mode_attack_consequences(world, attacker, target) {
    // - 被动模式玩家攻击其他玩家 → 退出被动模式
    // - 被动模式玩家攻击城市NPC → 进入红名 + 退出被动模式
}
```

### 3.5 血量计算: modify_attribute()

```rust
// gas/attribute/func.rs:136-211
pub fn modify_attribute(world, entity, gas_comp, attribute_key, modify_type, value) {
    // 伤害使用 AttributeOptType::Sub
    // new_value = current_value - damage
    // 如果 new_value <= 0: 标记 base_status.dead_event = true
    // 属性ID: GAMEPLAYFLAG_GAS_ATTRIBUTE_UNIT_COMBAT_HEALTH_CURRENT = 6050010
}
```

### 3.6 死亡处理

```rust
// base_status/func.rs:356-432
pub fn deal_dead_event(world, entity) {
    // 1. 玩家死亡: 释放家具交互点 + on_player_die() + 清除仇恨
    // 2. 清除交互状态
    // 3. 清除复活状态
    // 4. 下车处理
    // 5. 标记 is_dead=true, dead_event=false
    // 6. 触发 trigger 死亡事件
}

pub fn on_kill(world, killer, dead) {
    // 1. 记录 NPC 击杀记录
    // 2. 玩家击杀统计
    // 3. 大世界任务目标击杀处理
}
```

### 3.7 反作弊: CheckManager

```rust
// check.rs
pub struct CheckManager {
    user_map: HashMap<Entity, ShotInfoByUser>,
}

pub struct ShotInfo {
    weapon_id: i32,
    unique: i64,
    time: i64,        // 射击时间戳
    shot_num: i32,    // 散射数量(支持霰弹枪)
}

// 流程:
// 1. handle_shot_data() → add_shot_info(entity, weapon_id, unique)  // 记录射击
// 2. handle_hit_data()  → check_shot_info(entity, weapon_id, unique) // 校验命中
//    - weapon_id 必须匹配
//    - shot_num 递减（散射武器多次命中）
//    - shot_num=0 时移除记录
// 3. update_shot_info() → 清理超过 15 秒的过期记录
```

### 3.8 射击和弹药

```rust
// shot.rs — weapon_fire()
// 1. 获取 EquipComp 中当前武器
// 2. 检查弹药: GAMEPLAYFLAG_GAS_ATTRIBUTE_ITEM_PROPERTY_BULLETCURRENT
// 3. 弹药 <= 0 → 射击失败
// 4. 弹药 -= 1.0
// 5. 同步到 BackPackComp
// NPC 射击不消耗弹药，不需要校验
```

### 3.9 碰撞伤害

```rust
// crash.rs — CrashData 结构
// selfEntity, targetEntity, selfDamage, targetDamage, speed, crashDirection
// 流程: deal_crash_status() → crash() → deal_damage() 双向
// 碰撞NPC时还会触发行为树的碰撞响应(last_crash_data)
```

### 3.10 爆炸伤害

```rust
// explosion.rs — 配置驱动
// 1. 获取爆炸配置(cfg_destruct_event)
// 2. 对主目标造成 main_entity_damage
// 3. 范围伤害: 遍历所有实体, 按距离查表获取伤害值
//    damage_list: [{x: 距离, y: 伤害}, ...]
```

---

## 4. 行为树攻击节点

### 4.1 NpcFireControl 组件

```rust
// npc_fire_control.rs
pub struct NpcFireControl {
    pub start_time: i64,                   // 射击开始时间(毫秒)
    pub fire_intervals: VecDeque<i64>,     // 射击间隔队列(毫秒)
    pub just_fire: bool,                   // 标记刚射过一次
    pub fire_mode_active: bool,            // 射击模式是否激活
}

// 核心系统: deal_npc_fire_command() — 每帧调用
// if fire_mode_active:
//   if just_fire: 清除 is_fire, just_fire=false
//   else if now >= start_time + interval:
//     触发 is_fire=true, pop interval, start_time=now, just_fire=true
```

### 4.2 射击节点

#### BtActSetFireState — 设置射击状态

```rust
// bt_node.rs:4353-4399
pub struct BtActSetFireState {
    is_holding_gun: MetaDataCell<bool>,  // 是否持枪
    is_aim: MetaDataCell<bool>,          // 是否瞄准
    is_fire: MetaDataCell<bool>,         // 是否射击
}
// tick(): 通过 NpcLogicFsm.SetFireState 设置状态
```

#### BtActSetGunFireState — 设置枪支射击状态

```rust
// bt_node.rs:4460-4505
pub struct BtActSetGunFireState {
    is_fire: MetaDataCell<bool>,
    fire_target_entity: BlackBoardCell<Option<Entity>>,
    fire_target_pos: BlackBoardCell<Option<Vec3>>,
}
// tick(): 设置 AnimStateComp.is_fire + MonsterComp.target_entity_id
```

#### BtActChangeFireMode — 改变射击模式

```rust
// bt_node.rs:2483-2546
pub struct BtActChangeFireMode {
    fire_mode: MetaDataCell<i32>,  // 0=None, 1=Single, 2=Continuous, 3=MultiShot
}
// tick(): 从 cfg_gun 校验武器是否支持该模式 → 设置 AnimStateComp.fire_mode
```

#### BtActCustomFire_New — 自定义射击（核心）

```rust
// bt_node.rs:3010-3108
pub struct BtActCustomFire_New {
    fire_intervals: MetaDataCell<Vec<i64>>,             // 射击间隔(毫秒)
    fire_target_entity: BlackBoardCell<Option<Entity>>,
    fire_target_position: BlackBoardCell<Option<Vec3>>,
}
// begin(): 初始化 NpcFireControl, 激活射击, push_front(0) 立即射一次
//          设置 MonsterComp.target_entity_id 和 target_position
// tick():  检查 is_fire_over() → Running 或 Success
// end():   fire_mode_active=false, 清空 intervals
```

### 4.3 目标获取节点

#### BtActGetNearFovTarget — 视野内最近目标

```rust
// bt_node.rs:5811-5910
pub struct BtActGetNearFovTarget {
    target_target: BlackBoardCell<Option<Entity>>,  // 输出
    range: DynamicCell<f32>,                        // 搜索范围
    check_dying: MetaDataCell<bool>,                // 含濒死目标?
}
// tick(): 从 MonsterComp.fov_checklist 过滤 → 距离最近的存活目标
```

#### BtActGetNearWantedPlayer — 附近红名玩家

```rust
// bt_node.rs:5915-6022
pub struct BtActGetNearWantedPlayer {
    target_target: BlackBoardCell<Option<Entity>>,
    range: DynamicCell<f32>,
}
// tick(): 从 fov_list 过滤 WantedStatusComp.is_wanted() → 最近红名玩家
```

#### BtActGetNearPlayer — 附近任意玩家

```rust
// bt_node.rs:6027-6107
pub struct BtActGetNearPlayer {
    target_target: BlackBoardCell<Option<Entity>>,
    range: DynamicCell<f32>,
    include_same_camp: MetaDataCell<bool>,
    check_dying: MetaDataCell<bool>,
}
// tick(): 全局查询所有 PlayerComp(不限 FOV) → 距离最近的存活玩家
```

#### BtActGetHighestHateTarget — 最高仇恨目标

```rust
// bt_node.rs:6131-6151
pub struct BtActGetHighestHateTarget {
    target_target: BlackBoardCell<Option<Entity>>,
}
// tick(): HateComp.get_highest_hate_target() → 黑板
```

### 4.4 距离检查节点

#### BtCondWithinDistance — 实体距离

```rust
// bt_node.rs:7223-7270
pub struct BtCondWithinDistance {
    target: BlackBoardCell<Option<Entity>>,
    distance: DynamicCell<f32>,
}
// tick(): distance_squared < distance * distance → Success/Failure
```

#### BtCondWithinDistanceVec3 — 位置距离

```rust
// bt_node.rs:7275-7296
pub struct BtCondWithinDistanceVec3 {
    target_vec3: BlackBoardCell<Option<Vec3>>,
    distance: DynamicCell<f32>,
}
```

### 4.5 追踪节点

#### BtActChaseTarget_New — 追踪目标

```rust
// bt_node.rs:2739-2792
pub struct BtActChaseTarget_New {
    chase_target: BlackBoardCell<Option<Entity>>,
    move_type: MetaDataCell<i32>,  // 0=Walk, 1=Run
}
// tick(): NavigateProxy.set_target_entity() + 设置移动类型
```

### 4.6 武器和能力节点

#### BtActChangeWeapon

```rust
// bt_node.rs:5438-5499
pub struct BtActChangeWeapon {
    weapon_index: MetaDataCell<i32>,  // 武器索引
}
// tick(): 从 NpcEquipReadyComp 获取武器 → EquipComp.set_weapon()
```

#### BtActStartAbility

```rust
// bt_node.rs:5312-5363
pub struct BtActStartAbility {
    ability_id: MetaDataCell<i32>,
    target_pos: BlackBoardCell<Option<Vec3>>,
    target_entity: BlackBoardCell<Option<Entity>>,
}
// tick(): start_ability(world, entity, ability_id, target)
```

### 4.7 黑板和元数据类型系统

```rust
// BlackBoardCell<T> — 可变，指向黑板数据（裸指针实现）
// MetaDataCell<T>   — 不可变，配置时指定
// DynamicCell<T>    — 兼容两者，策划可配黑板变量或静态值
```

### 4.8 典型攻击行为树配置

**行为树 JSON 黑板变量示例** (T10000001FightNpc.json):

| 变量名 | 类型 | 说明 |
|--------|------|------|
| ActTarget | Option<Entity> | 当前目标 |
| STATE_FirstShoot | bool | 是否首次射击 |
| STATE_IsCover | i32 | 掩体状态 |
| STATE_IsEvade | i32 | 躲避状态 |
| Detection_PAM_ViewRange | f32 | 视野范围 |
| Detection_PAM_ViewAngle | f32 | 视野角度 |
| Detection_PAM_CloseRange | f32 | 近距离 |
| Detection_PAM_MediumRange | f32 | 中距离 |
| Tactical_PAM_CloseRange | f32 | 战术近距离 |
| Cover_PAM_CloseRange | f32 | 掩体近距离 |
| ANM_BulletReaction | i32 | 中弹反应动画(165) |
| ANM_Fell | i32 | 倒地动画(163) |
| ANM_Reload | i32 | 装弹动画(166) |

**射击间隔配置** (T11105001Shoot.json):
- `fire_intervals`: "0|100|100|100|100|100|100|100|100" (毫秒)

---

## 5. AI 决策层与 MonsterComp

### 5.1 AiComp 组件

```rust
pub struct AiComp {
    pub behavior_type: i32,              // NPC 行为类型
    pub concentrate_entity: u64,         // 专注目标
    pub control_entity: Entity,          // 控制该 NPC 的玩家
    pub is_escaping: bool,               // 逃离状态
    pub is_open: bool,                   // AI 是否开启
    pub last_action_frame: u64,          // 上次行动帧
    pub is_dirty: bool,
    pub is_permanent: bool,              // 永久 NPC
    pub is_vip: bool,                    // VIP 优先级
    pub is_server_control_monster: bool, // 服务端行为树控制
    pub is_client_physics: bool,         // 客户端物理接管
    pub is_poi_monster: bool,            // POI 怪物
}
```

### 5.2 主控者(master_entity)机制

```rust
// ai_control.rs — npc_sync_state_update() 每帧调用
// 1. 定期检查 master_entity 是否离线或距离>30米(distance_squared > 900) → 清除主控
// 2. 如果无主控者: 查询100米范围内(distance_squared < 10000)最近的已加载玩家
// 3. 有主控者 → 行为树 enable=true; 无主控者 → enable=false
// 检查间隔: check_master_entity_interval 毫秒

// AI 控制权分配:
// - 单个玩家最多控制 100 个 NPC
// - VIP NPC 优先分配给已加载完成的玩家
// - 30 帧无操作清除控制权
// - 150 帧非 permanent NPC 自动移除
```

### 5.3 MonsterComp 完整字段

```rust
pub struct MonsterComp {
    pub unit_type: i32,                          // NPC 创建者 ID
    pub monster_type: i32,                       // 怪物类型
    pub monster_appearance: i32,                 // 外观
    pub monster_cfg_id: i32,                     // 配置 ID
    pub npc_creator_cfg: Option<CfgNpc>,
    pub monster_strength: i32,                   // 强度
    pub npc_tag_cfg: Option<CfgNpcTag>,
    pub server_behavior_type: i32,              // 服务端行为树类型
    pub monster_danger_state: MonsterDangerState,// Idle/Alert/Attack
    pub target_entity_id: u64,                  // 当前目标
    pub target_position: Option<Vec3>,          // 目标位置
    pub navigate_info: Option<NavigateProto>,
    nav_agent_velocity: Vec3,
    pub monster_ambient_data: Vec<MonsterAmbientData>,
    pub fov_checklist: IndexMap<Entity, bool>,  // 视野列表(有序)
    pub fov_check_set: HashSet<Entity>,         // 视野集合(快查)
    pub master_entity: u64,                     // 主控玩家
    npc_sync_state: NpcSyncState,
    pub fast_reflex_cmd: Option<FastReflexReq>,
    pub weak_state_cmd: Option<NpcWeakStateCommand>,
    pub last_check_master_entity_time: i64,
    pub check_master_entity_interval: i64,
    pub path_points: Vec<Vec3>,
    pub hold_item_id: i32,
    pub npc_sync_fsm: NpcSyncFsm,              // 同步状态机
    pub npc_logic_fsm: NpcLogicFsm,            // 逻辑状态机
    pub npc_tactic_fsm: NpcTacticFsm,          // 战术状态机
    pub interest_handhold_list: Vec<i32>,
    pub receive_handhold: Option<bool>,
    pub interact_player: Option<(Entity, i32)>,
}
```

### 5.4 FOV 视野系统

```rust
// 数据结构: IndexMap<Entity, bool> — 有序映射
// 位运算更新:
pub fn update_fov_checklist(&mut self, fov_res: u64) {
    // fov_res 的第 i 位 = 第 i 个实体是否在视野内
    self.fov_checklist.iter_mut().enumerate().for_each(|(i, (_, val))| {
        *val = (fov_res & (1 << i)) != 0;
    });
}

pub fn get_in_fov_list(&self) -> Vec<Entity> {
    self.fov_checklist.iter().filter(|(_, v)| **v).map(|(e, _)| *e).collect()
}

pub fn check_entity_in_fov(&self, entity: Entity) -> bool {
    self.fov_checklist.get(&entity).copied().unwrap_or(false)
}
```

### 5.5 三层 NPC 状态机

#### NpcSyncFsm（网络同步）

| 状态 | 说明 |
|------|------|
| WeakControl | 弱控制（默认） |
| Override | 完全覆盖 |
| FastReflex | 快速反应/应激 |

#### NpcLogicFsm（逻辑状态）

| 状态 | 值 | 说明 |
|------|----|------|
| Stand | 0 | 站立（子FSM: Move, PlayAnim, RemoteAttack） |
| Ground | 1 | 地面移动 |
| Death | 2 | 死亡（最终状态） |
| Shelter | 3 | 掩体 |
| Drive | 4 | 驾驶 |
| Interact | 5 | 交互 |

输入:
```rust
pub enum NpcBaseLogicInput {
    ChangeLogicState(NpcState),
    DeadEvent,
    EnterShelter(u32, u32),
    MoveRequest,
    PlayAnim(i32, bool),
    SetFireState(Option<bool>, Option<bool>, Option<bool>), // 腰射, 瞄准, 开火
    EnterCar(Entity, i32),
    LeaveCar,
    // ...
}
```

#### NpcTacticFsm（战术状态）

| 状态 | 值 | 说明 |
|------|----|------|
| Idle | 0 | 非战斗 |
| Alert | 1 | 警觉 |
| Combat | 2 | 战斗（存储 target_player） |
| Evade | 3 | 躲避 |

### 5.6 AnimStateComp（动画状态）

```rust
pub struct AnimStateComp {
    pub is_dirty: bool,
    pub movement_layer: Option<(i32, i64)>,    // 移动层(动画ID, 结束时间)
    pub base_layer: Option<(i32, i64)>,
    pub upper_layer: Option<(i32, i64)>,
    pub override_layer: Option<(i32, i64)>,
    pub input_xy: Vector2,                     // 移动输入
    pub monster_state: NpcState,
    pub anim_id: i32,
    pub is_anim_loop: bool,
    pub audio_id: i32,
    is_aim: bool,                              // 瞄准
    is_fire: bool,                             // 开火
    is_holding_gun: bool,                      // 持枪
    fire_target_entity: Option<Entity>,        // 射击目标
    fire_target_pos: Option<Vec3>,             // 射击位置
    gun_fire_mode: FireMode,                   // 射击模式
    pub skill_id: i32,
    pub skill_target_entity: Option<Entity>,
    pub skill_target_position: Option<Vec3>,
    pub mood_bubble_type: i32,
    pub mood_bubble_duration: f32,
    enter_shelter_param: Option<EnterShelterParam>,
    drive_vehicle_id: u64,
    drive_seat_index: i32,
    interact_object: (u64, i32),
}

// 射击相关 API:
// set_is_aim(bool), set_is_holding_gun(bool), set_is_fire(bool)
// set_fire_target(entity, pos), set_fire_mode(mode)
// get_proto() → ServerAnimState (序列化到协议)
```

### 5.7 AI 决策配置

**Dan_State.json** — Pursuit 触发:
```json
{
  "name": "daily_schedule_to_pursuit",
  "from": "daily_schedule",
  "to": "pursuit",
  "priority": 2,
  "condition": { "op": "eq", "key": "feature_state_pursuit", "value": true }
}
```

**Blackman_State.json** — Police Enforcement:
```json
{
  "name": "daily_schedule_to_police_enforcement",
  "from": "daily_schedule",
  "to": "police_enforcement",
  "priority": 2,
  "condition": { "op": "eq", "key": "feature_state_pursuit", "value": true }
}
```

---

## 6. 协议定义与配置

### 6.1 攻击相关协议

#### HitData (scene.proto:1236-1254)

```protobuf
message HitData {
  uint64 attack_entity = 1;
  uint64 attacker_type = 2;
  int32 weapon_id = 3;
  int32 cell_index = 4;
  base.Vector3 fire_position = 5;
  base.Vector3 hit_position = 6;
  int32 hit_type = 7;
  uint64 target_entity = 8;
  int32 bodyPart = 9;             // BodyPartType
  int32 passed_dis = 10;
  int32 attack_combo_id = 11;
  int32 damage = 12;
  repeated int32 hit_damage_type = 13;
  bool is_strong_hit = 14;
  int32 element_type = 15;
  HitResultType hit_result = 16;
  bool is_execution_hit = 17;
}
```

#### MonsterData (npc.proto:74-93)

```protobuf
message MonsterData {
  int32 serverBehaviorType = 1;
  int32 monsterType = 2;
  int32 unitType = 3;
  MonsterDangerState monsterState = 4;  // Idle/Alert/Attack
  uint64 target_entity = 5;
  int32 monsterCfgId = 6;
  uint64 master_entity = 7;
  int32 monsterAppearance = 8;
  NavigateProto navigateProto = 9;
  repeated MonsterAmbientData monster_ambient = 10;
  repeated uint64 fov_checklist = 11;
  NpcWeakStateCommand weak_state_cmd = 12;
  NpcSyncState sync_state = 13;
  repeated Vector3 path_points = 14;
  Vector3 nav_agent_velocity = 15;
  int32 holdItemId = 16;
  repeated int32 interest_handhold_list = 17;
  Vector3 target_position = 18;
}
```

#### 关键枚举

```protobuf
enum HitResultType { Common = 0; Invincible = 1; }
enum MonsterDangerState { Idle = 0; Alert = 1; Attack = 2; }
enum NpcSyncState { None = 0; WeakControl = 1; Override = 2; FastReflex = 3; }
```

### 6.2 配置结构

#### CfgGun（枪械配置）

```rust
pub struct CfgGun {
    pub id: i32,
    pub bullet_type: BulletType,
    pub fire_modes: Vec<FireMode>,     // 支持的射击模式
    pub gun_fire_comp: GunFireComp,
}
// FireMode: Single(1), Continuous(2), MultiShot(3)
// BulletType: NormalBullet(1), SpecialBullet(2), HeavyBullet(3), InstantaneousBullet(4)
```

#### CfgNpc（NPC 配置）

```rust
pub struct CfgNpc {
    pub id: i32,
    pub name: String,
    pub server_behaivor_type: ServerBehaviorTree,
    pub behavior_type: i32,
    pub base_speed: f32,
    pub weapon_list: Vec<i32>,
    pub invincible: bool,
    pub fast_reflex_list: Vec<i32>,
    // ...
}
```

---

## 7. 网络同步

### 7.1 MonsterData to_proto()

```rust
// monster_comp.rs:131-166
pub fn to_proto(&mut self) -> MonsterData {
    // 序列化后清空一次性数据:
    // - monster_ambient_data.clear()
    // - weak_state_cmd.cmd_dirty = false
    MonsterData {
        monster_state: self.monster_danger_state,
        target_entity: self.target_entity_id,
        target_position: ...,
        master_entity: self.master_entity,
        sync_state: self.npc_sync_fsm.current_state(),
        fov_checklist: self.fov_checklist.keys().collect(),
        // ...
    }
}
```

### 7.2 事件广播

```rust
// 所有攻击事件通过 try_add_event_to_scene() 广播:
pub enum SceneEvent {
    Hit(HitData),              // 攻击事件
    Kill(KillInfo),            // 死亡事件
    Shot(ShotData),            // 射击事件
    Crash(CrashData),          // 碰撞事件
    Explosion(ExplosionInfo),  // 爆炸事件
}

// 添加到 FrameDataUpdateCache, 帧末统一广播给 AOI 范围内玩家
```

### 7.3 客户端→服务器流程

```
客户端射击 → ShotData(shooter_entity, weapon_cell_index)
  → handle_shot_data() → weapon_fire() 扣弹药
  → add_shot_info() 记录到 CheckManager

客户端命中 → HitData(attack_entity, target_entity, weapon_id, damage, ...)
  → handle_hit_data() → check_shot_info() 校验
  → attack() → can_take_damage() → bp_function_apply_damage()
  → 广播 SceneEvent::Hit
```

### 7.4 AOI 与攻击的关系

- AOI 使用 GridMap 网格管理实体位置
- 攻击事件仅广播给 AOI 范围内的玩家
- master_entity 机制确保 NPC 附近有玩家时才激活行为树

---

## 设计要点总结

### 关键设计特点

1. **客户端报送命中**: 服务器不做弹道计算，客户端上报 HitData，服务器只做合法性验证
2. **射击间隔队列**: NpcFireControl 的 `fire_intervals` 支持不规则节奏(如 [0,100,100,500,100])
3. **视野位图**: `update_fov_checklist()` 用位运算批量更新
4. **主控者机制**: NPC 只在有主控玩家时激活 AI（清除阈值 30m，搜索阈值 100m）
5. **仇恨反向索引**: ReverseHateComp 实现 O(1) 快速查询/清理
6. **红名系统**: NPC 只能攻击红名玩家，白名/被动玩家免疫
7. **反作弊**: CheckManager 校验射击-命中一致性，支持散射武器
8. **BP 函数伤害计算**: 实际伤害值由 bp_function_apply_damage() 决定
9. **三层状态机**: Sync(同步) + Logic(逻辑) + Tactic(战术) 解耦

### 潜在问题

1. **仇恨双重触发（仅 deal_damage 路径）**: deal_damage() 同时通过 trigger 事件和直接函数调用增加仇恨，导致碰撞/爆炸/坠落伤害的仇恨翻倍；attack()（HitData）路径不受影响
2. **NPC 攻击不更新反向索引**: on_npc_attack_player() 不添加 ReverseHateComp
3. **无仇恨持久化**: 玩家下线后仇恨重置
4. **已废弃节点**: BtActCustomFire、BtActAttack 已被注释废弃
