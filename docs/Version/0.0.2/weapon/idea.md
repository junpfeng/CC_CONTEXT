# 武器系统

## 做什么

实现一套完整的手枪/步枪/霰弹枪/近战/投掷物五类武器系统，涵盖射击验证、伤害计算、后坐力/散射表现、配件、弹药管理、禁枪区、武器商店等模块。服务器权威校验所有伤害结算，客户端负责本地表现（后坐力反馈、弹孔贴花、准星动画、VFX）。

## 涉及端

both

## 触发方式

- 玩家输入（PlayerInputComp.IsAttack）→ 客户端 GunComp 触发射击
- 服务器接收 HitReport / RequestFire 上行消息后执行验证与结算
- GM 调试：`/ke* gm give_weapon {weaponId}` 直接发放武器

## 预期行为

正常流程：
1. 玩家按下射击键 → 客户端检查弹匣、冷却、禁枪区
2. 客户端计算散射角（姿态乘数 × 连射衰减 × 配件精度）、后坐力累积（Pattern 查表）
3. 子弹射线检测命中后，发送 HitReport 到服务器
4. 服务器 CheckManager 验证射速（120% RPM + 50ms 容差）、Shot-Hit 匹配、weaponID
5. 服务器执行伤害公式：`baseDamage × distanceFalloff × bodyPartMultiplier × penetrationDecay`
6. 结算结果下行同步，客户端播放命中反馈特效

异常/边界情况：
- 射速异常（外挂）：返回 ErrWeaponShotRejected(13015)，丢弃该次射击
- 禁枪区内操作：前置拦截，返回 ErrWeaponInNoWeaponZone(13014)
- 弹匣为空：客户端拦截，触发换弹流程
- 投掷物哑弹（定时器到期未触发）：服务器端 ThrowableTracker 强制引爆

## 不做什么

- 不做客户端伤害权威（结算全部在服务器）
- 不做弹道物理模拟（子弹飞行用 Raycast，不做重力/风偏）
- 不做载具武器的独立系统（载具射击复用同一套 GunComp，通过 VehicleShootData 区分）

## 参考

- 服务端网络层：`P1GoServer/servers/scene_server/internal/net_func/weapon/weapon.go`
- 伤害系统：`P1GoServer/servers/scene_server/internal/damage/`
- 武器 JSON 配置管理：`P1GoServer/common/config/weapon_json.go`
- 客户端射击核心：`freelifeclient/.../Comp/Weapon/Comps/GunComp.cs`
- 客户端配置加载：`freelifeclient/.../Config/WeaponJsonConfigLoader.cs`
- 配置源文件：`freelifeclient/RawTables/Weapon/`

---

## 配置系统

### 配置文件结构

> ⚠️ **待实现**：客户端配置目前仍为 Excel 格式（`RawTables/Weapon/*.xlsx`），JSON 迁移尚未完成。以下为目标设计。

武器属性计划从 Excel 全面迁移至 JSON，存放在 `freelifeclient/RawTables/Weapon/`：

| 文件 | 内容 | 状态 |
|------|------|------|
| `json/guns.json` | 枪械完整配置（CfgId 9xxxx） | ⚠️ 待迁移 |
| `json/melee.json` | 近战武器配置 | ⚠️ 待迁移 |
| `json/throwables.json` | 投掷物配置 | ⚠️ 待迁移 |
| `json/appendix.json` | 配件模板/默认值/物品关联 | ⚠️ 待迁移 |
| `json/damage_model.json` | 全局伤害模型（部位倍数、距离衰减曲线） | ⚠️ 待迁移 |
| `json/shadow_box_config.json` | 阴影盒配置 | ⚠️ 待迁移 |
| `recoil/{weaponName}.json` | 各武器后坐力 Pattern 曲线 | ⚠️ 待迁移 |
| `diffusion/{weaponName}.json` | 各武器散射参数 | ⚠️ 待迁移 |
| `vfx_lod.json` | 武器特效 LOD 距离配置 | ⚠️ 待迁移 |
| `weapon_base.json` | 弹道与基础伤害参数 | ⚠️ 待迁移 |
| `camera_shake.json` | 射击相机震动参数 | ⚠️ 待迁移 |

**当前实际文件（Excel）：**
- `Weapon.xlsx` / `Guns.xlsx` / `Bullet.xlsx` / `Projectile.xlsx` / `ThrowableObject.xlsx`

### 服务端配置加载

服务端通过 `WeaponJsonConfig` 统一管理：

```go
type WeaponJsonConfig struct {
    weapons           map[int32]*WeaponBaseConfig
    guns              map[int32]*GunConfig
    melee             map[int32]*MeleeConfig
    throwables        map[int32]*ThrowableConfig
    damageModel       *DamageModelConfig
    appendixTemplates map[int32]*AppendixTemplate
    npcWeaponConfigs  map[int32]*NpcWeaponConfig
    noWeaponZones     []*NoWeaponZoneConfig
    bulletPrefabs     map[int32]*BulletPrefabConfig
    projectiles       map[int32]*ProjectileConfig
    audioWeapons      map[int32]*AudioWeaponConfig
}
```

兼容层：`weapon_cfg_compat.go` 保留 `CfgWeapon`/`CfgGun` 的 ORM 兼容接口，不影响新代码直接读取 JSON 配置。

### 客户端配置加载

> ⚠️ **待实现**：`WeaponJsonConfigLoader.cs` 尚未创建，依赖 JSON 迁移完成后实现。

`WeaponJsonConfigLoader`（单例）在场景加载时读取 `StreamingAssets/weapon/`（编辑器模式读 `RawTables/Weapon/`）：

```csharp
var gunCfg       = WeaponJsonConfigLoader.Instance.GetGunByCfgId(cfgId);
var recoilCfg    = WeaponJsonConfigLoader.Instance.GetRecoilConfigByWeaponId(weaponId);
var diffusionCfg = WeaponJsonConfigLoader.Instance.GetDiffusionConfig(weaponId);
```

---

## 射击系统

### 客户端射击流程

```
PlayerInputComp.IsAttack
  → GunComp.ShootVirtualBullet()
    ├─ 检查弹匣 (_magazine.CanShoot)
    ├─ 检查冷却 (SingleFireTimeout / ContinueFireTimeout)
    ├─ BulletDiffusionComp.CalculateDispersion()  散射角
    ├─ GunRecoilComp.ApplyRecoil()                后坐力 Pattern 查表
    ├─ TraditionalFireComp / CircleScatteringFireComp 选择开火模式
    │  └─ Projectile.Shoot(firePos, dir, velocity)
    ├─ GunEffectComp.PlayFireEffect()             枪口焰/烟雾
    └─ 发送 HitReport → 服务器
```

### 开火模式

| 模式 | 说明 |
|------|------|
| Single | 单发，每次扣动触发一颗 |
| Continuous | 全自动，按住持续射击，FireRate(RPM) 控制间隔 |
| Burst | 点射，BurstConfig{Count, Interval} 控制连发数和间隔 |
| MultiShot | 霰弹，ScatterConfig{Angle, Count} 控制散弹角度和数量 |

开火模式可在 `guns.json` 中通过 `FireMode []string` 字段配置多个，玩家通过 SwitchFireMode 请求切换（服务器验证合法性后下行同步）。

---

## 后坐力系统

### 实现方案

`GunRecoilComp`（`RemoteWeapon/GunRecoilComp.cs`）使用 **GTAV 风格 Pattern 查表累积模型**：

- 每次开火：`patternIndex++`，从 `recoil/{weapon}.json` 的 Pattern 数组取出偏移量
- 水平/垂直后坐力分别累积，驱动相机旋转
- 停止射击后按 `RecoverySpeed` 线性恢复
- `ShotAccuracy` 字段与 `BulletDiffusionComp` 共享，后坐力累积影响散射角

### 后坐力配置字段

```json
{
  "weaponId": 90001,
  "recoverySpeed": 8.0,
  "recoveryDelay": 0.15,
  "pattern": [
    {"vertical": 0.3, "horizontal": 0.0},
    {"vertical": 0.5, "horizontal": 0.1},
    ...
  ]
}
```

---

## 散射系统

### 散射角计算

`BulletDiffusionComp`（`RemoteWeapon/BulletDiffusionComp.cs`）：

```
finalDispersion = baseAngle
    × postureMultiplier  (站立 1.0 / 蹲姿 0.7 / 移动 1.5)
    × burstDecay         (连发累积衰减，max=maxAngle)
    × accessoryAccuracy  (配件精度修正系数)
```

- 基准角度 `baseAngle` 来自 `diffusion/{weapon}.json`
- 归一化到 120m 有效射程
- 霰弹枪通过 `ScatterConfig.Angle` 和 `ScatterConfig.Count` 控制散弹分布（`CircleScatteringFireComp`）

---

## 伤害系统

### 伤害公式

服务端 `damage/hit.go` 执行伤害结算：

```
finalDamage = baseDamage
    × distanceFalloff(distance)
    × bodyPartMultiplier[bodyPart]
    × penetrationDecay
```

- **距离衰减**：`DamageModelConfig.DistanceFalloff`，支持线性/指数两种 Model
- **部位倍数**：头部爆头 2.5×（由 `HeadshotAccuracyGate` 精度门槛过滤）
- **穿透衰减**：`penetration.go` 中 `CalcPenetration()` 返回 RemainingDamage 和 CanContinue

### 反作弊射击验证

`CheckManager`（`damage/check_manager.go`）：

- 每次 Shot 记录 `{uniqueId, weaponId, burstCount}`，5 秒过期
- Hit 到来时必须匹配对应 Shot，否则拒绝
- 射速校验：`actualInterval ≥ 60000/RPM × 0.8 - 50ms`（120% RPM + 50ms 网络容差）
- 霰弹/连发：burstCount 计数，允许一次 Shot 对应多个 Hit

---

## 投掷物系统

`ThrowWeaponComp`（客户端）+ `damage/throw_weapon.go`（服务端）：

| 引爆方式 | 说明 |
|----------|------|
| 定时 | 引信时间到期自动引爆 |
| 碰撞 | 落地/碰墙即爆（榴弹） |
| 接近 | `ProximityRadius=3.0m` 范围内有玩家则引爆（地雷） |

投掷参数：起点、方向、力度(0~1)、重力系数、引信时间——全部服务端 `ThrowableTracker` 追踪，防止客户端伪造引爆位置。

---

## 爆炸系统

`damage/explosion.go`：

- 内圈（`InnerRatio`）全额伤害，外圈（`OuterRatio`）线性衰减至最小值
- 同时对主目标 + AOI 范围实体造成溅射伤害
- 与 `CfgExplosionEvent` / `CfgDestructEvent` 联动，触发场景破坏效果

---

## 配件系统

`WeaponAccessoryComp`（客户端）+ `appendix.json`（配置）：

- 支持瞄准镜、枪管、握把、弹匣等槽位
- 配件安装后统计精度/后坐力修正系数，缓存到 Comp 字段（单次计算，热路径零开销）
- 服务端验证配件合法性（`AppendixTemplate`），防止非法配件组合

---

## 禁枪区

> ⚠️ **待实现**：`no_weapon_zones.json` 在客户端工程中不存在，禁枪区配置尚未建立。

`no_weapon_zones.json` 配置两种形状：

| 形状 | 参数 |
|------|------|
| sphere | center + radius |
| box | center + halfExtents + rotation |

`checkNoWeaponZone()` 在装备武器、射击、投掷操作前执行前置校验，区域内操作返回 `ErrWeaponInNoWeaponZone(13014)`。

---

## 武器商店

`damage/weapon_shop.go`：

- `HandleWeaponShopBuy`：武器购买，扣减货币 + 写入背包
- `HandleShopBuyItem`：弹药/配件通用购买，校验库存
- 弹药不足时返回 `ErrWeaponAmmoNoStock(13002)`

---

## UI 系统

| 组件 | 文件 | 职责 |
|------|------|------|
| CrosshairPanel | `UI/Pages/Panels/CrosshairPanel.cs` | 准星面板容器 |
| CrosshairWidgetView | `UI/Pages/WidgetViews/CrosshairWidgetView.cs` | 4 种准星样式组 + 击中特效 |
| CrosshairWidget | `UI/Pages/Widgets/CrosshairWidget.cs` | 准星扩散/收缩动画，散射角驱动 |

准星扩散由 `BulletDiffusionComp` 当前散射角实时驱动，命中/击杀触发独立动画组（`hitGroup` / `killGroup`）。

---

## 视觉表现

| 模块 | 实现 | 说明 | 状态 |
|------|------|------|------|
| 枪口焰 | `MuzzleFlashComp` | VFX Particle，随 FireRate 节奏触发 | ⚠️ 待实现 |
| 弹孔贴花 | `BulletHoleManager` | DecalProjector 对象池 MAX=30，FIFO 回收；材质映射：金属/木/混凝土/玻璃/肉体 | ⚠️ 待实现 |
| 子弹曳迹 | `GunEffectComp` | 超过有效距离触发，VFX LOD 距离剔除 | ✓ 已实现 |
| 相机震动 | `camera_shake.json` | 配置驱动，按武器类型设置强度/频率 | ⚠️ 待实现（配置文件缺失） |
| 命中反馈 | `HitFeedbackComp` | 击中音效 + 准星红色闪烁 | ⚠️ 待实现 |

---

## 性能约束

- **手游预算**：热路径（射击 Tick）零 GC 分配，后坐力 Pattern 查表、散射系数缓存到 Comp 字段
- **弹孔池上限**：MAX=30，避免 DecalProjector 过多影响渲染
- **VFX LOD**：`vfx_lod.json` 按距离分级剔除枪口焰/曳迹特效
- **投掷物追踪**：场景级 ThrowableTracker，不为每颗投掷物单开协程

---

## 错误码速查

| 错误码 | 常量 | 说明 |
|--------|------|------|
| 13001 | ErrFireModeNotSupported | 请求的开火模式不在武器支持列表 |
| 13002 | ErrWeaponAmmoNoStock | 弹药不足或弹药类型不支持 |
| 13006 | ErrWeaponSpinningUp | 武器预热中（如重机枪） |
| 13014 | ErrWeaponInNoWeaponZone | 禁枪区内禁止武器操作 |
| 13015 | ErrWeaponShotRejected | 射速异常，反作弊拦截 |
