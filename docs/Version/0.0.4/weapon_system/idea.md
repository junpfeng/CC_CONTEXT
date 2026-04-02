# GTA5 风格玩家武器系统

## 核心需求
给玩家角色设计同 GTA5 一样的武器系统。

## 调研上下文

### 已有基础架构
项目已有较完整的武器框架，0.0.2 版本有设计文档（`docs/version/0.0.2/weapon/idea.md`）：

**客户端已有：**
- 武器类型体系：`Weapon`(基类) → `RemoteWeapon`(枪械) / `MeleeWeapon`(近战) / `ThrowWeapon`(投掷) / `HandleWeapon`(手持)
- 核心组件：`WeaponComp`(装备管理/槽位) + `PlayerGunFightComp` + `GunFightState`(战斗状态机)
- 枪械子组件：`GunComp`、`RecoilComp`(后坐力)、`BulletDiffusionComp`(散射)、`WeaponAccessoryComp`(配件)
- 武器 IK：`PlayerWeaponIK`（持枪姿态骨骼绑定）
- UI 组件：武器轮盘(`WeaponWheelOptionWidget`)、弹药购买、武器商店、武器属性面板
- 输入系统：`PlayerInputComp` 已有 Aim/Attack/Reload 事件
- 禁枪区：`GunFreeZone` / `CityGunFreeZone`
- 动画层：PlayerAnimationComp 有 UpperBody/Arms/RightArm 层

**服务端已有：**
- 武器数据结构：`Weapon` struct (cfg + attributes + GunDataProto)
- 协议：WeaponProto、GunDataProto、GunAppendixProto（配件）
- 伤害系统：`damage/` 目录（CheckManager 验证 + 伤害计算）
- 配置加载：cfg_weapon.go、cfg_gun.go、cfg_gunappendix.go、weapon_json.go
- 射击验证：weapon net_func 处理

**配置表（Excel）：**
- `RawTables/Weapon/`: Weapon.xlsx、Bullet.xlsx、Projectile.xlsx、ThrowableObject.xlsx

### GTA5 参考资料
- 项目有 GTA5 逆向文档（`E:/workspace/PRJ/GTA/GTA5/docs/`）
- NPC 行为树文档中有武器决策系统描述
- 0.0.2 武器设计已参考 GTA5 的射击验证、伤害计算、后坐力 Pattern 等

### 架构集成点
- 玩家 27 个组件中已包含 WeaponComp、PlayerWeaponIK、CombatComp、PlayerGunFightComp
- 网络同步通过 ActionReqClient + AliveData.EquipProto
- 动画通过 Animancer 多层混合

## 范围边界
- 做：掏枪/收枪、辅助瞄准（锁定吸附）、步行射击、Raycast 命中检测、服务端伤害验证、NPC+载具可被攻击、武器持久化、准心 UI、Hit Marker
- 不做：载具内射击、掩体射击、PvP 伤害、弹药限制、武器购买/升级、后坐力系统、弹道物理、音效/特效

## 初步理解
打通已有武器框架（WeaponComp + PlayerGunFightComp + damage 系统），补齐掏枪→瞄准→射击→伤害闭环，新增辅助瞄准（锁定吸附）。

## 待确认事项
已全部确认。

## 确认方案

核心思路：打通已有武器框架（WeaponComp + PlayerGunFightComp + damage 系统），补齐掏枪→瞄准→射击→伤害闭环，新增辅助瞄准（锁定吸附）。

### 锁定决策

**服务端：**
- 武器持久化：在玩家 MongoDB 数据中增加武器背包字段，登录时下发、变更时存储
- 伤害目标：NPC + 载具（复用已有 `damage/` 包的 `DealDamage()`，扩展 `canTakeDamage()` 支持载具实体类型）
- 弹药：本期不限制，`HandleShotData()` 中跳过弹药扣减逻辑
- 射击验证：复用已有 ShotData/HitData 协议和 CheckManager 反作弊流程。服务端新增 RPM 射速校验（按武器配置表 fire_rate 限制），超频 ShotData 丢弃并返回 rate_limit 错误码通知客户端
- 掏枪状态校验：服务端收到 DrawWeaponReq 时校验玩家状态（死亡/上车/被控 → 返回失败码），客户端收到失败 Res 后回滚动画
- 命中校验增强：CheckManager 在距离校验基础上增加方向角度校验（验证射击方向与目标方位夹角合理），Go 端无物理引擎不做 Raycast 遮挡
- 默认武器：玩家创建时初始化一把手枪（DesertEagle），写入武器背包

**客户端：**
- 掏枪/收枪：WeaponComp 新增 `DrawWeapon()`/`HolsterWeapon()` 方法，触发上半身动画层切换 + 武器模型挂载到手部骨骼点。无专用 Draw 动画资源，用已有 Idle 动画做快速过渡（0.2s blend）。客户端加状态锁防止 0.2s blend 期间重入（`_isTransitioning` flag）
- 瞄准系统：PlayerGunFightComp 已有 Aim FSM 状态，补齐：① 准心 UI（屏幕中央十字线 Widget）② 相机拉近（FOV 从默认缩到 ~40°）③ IK 权重渐入（已有 `_ikWeightTweener`）
- 辅助瞄准（Snap-to）：新增 `AimAssistComp`，按瞄准键时 OverlapSphere 检测前方扇形区域内最近敌人，自动将相机朝向 Snap 到目标，持续跟踪直到松开瞄准或目标丢失。无目标时回退自由视角控制
- 射击流程：按攻击键 → 客户端播放射击动画（已有 Atk FBX）→ 从相机中心做 Raycast → 命中判定 → 发送 ShotData+HitData 给服务端 → 服务端验证并广播
- 伤害反馈：命中时显示 Hit Marker（准心闪白）、目标播放受击动画
- 武器轮盘：复用已有 `WeaponWheelOptionWidget`，不改动

**协议变更：**
- 新增 `WeaponBagNtf`（登录时服务端推送武器背包列表）
- 新增 `DrawWeaponReq/Res`（掏枪/收枪状态同步，Req 携带 weapon_id，Res 含 result_code；失败时客户端回滚动画）
- 复用已有 `ShotData`/`HitData` 消息，不新增射击协议

**数据结构：**
- 服务端 `PlayerWeaponBag` struct：`Weapons []Weapon`（复用已有 `citem.Weapon`）、`InHandIndex int32`（当前手持武器索引，-1=空手）。操作 InHandIndex 前做边界检查（<0 或 >=len(Weapons) 视为空手）
- 客户端 `AimAssistComp`：`_lockTarget EntityBase`、`_assistRadius float = 15f`、`_assistAngle float = 60f`（扇形半角）、`_snapSpeed float = 10f`

**配置表：**
- 复用已有 `Weapon.xlsx`、`Guns.xlsx`、`Bullet.xlsx`，不新增配置表
- 默认手枪的 weapon_id 从已有配置中选取（DesertEagle 对应 ID）

**范围边界：**
- 做：掏枪/收枪、辅助瞄准（锁定吸附）、步行射击、Raycast 命中检测、服务端伤害验证、NPC+载具可被攻击、武器持久化、准心 UI、Hit Marker
- 不做：载具内射击、掩体射击、PvP 伤害、弹药限制、武器购买/升级、后坐力系统、弹道物理、音效/特效（后续版本）

### 待细化
- 载具受击后的具体表现（扣血？爆炸？冒烟？）：由实现阶段根据已有载具系统确定
- 默认手枪 weapon_id 具体数值：实现时从 Weapon.xlsx 读取确认
- 准心 UI 具体样式：基础十字线，实现时按 GTA5 参考调整
- AimAssistComp OverlapSphere 频率节流：大世界 NPC 密集区可能有性能开销，考虑每 N 帧检测或 LOD 降频
- 禁枪区交互：玩家持枪进入 GunFreeZone / 在禁枪区内尝试掏枪的处理逻辑
- 默认手枪配置表兜底：若 Weapon.xlsx 无 DesertEagle 条目时的容错处理
- 掏枪回滚竞态：网络延迟 >200ms 时 Res 返回失败但动画已完成，需缓存结果在 blend 完成时决定
- _isTransitioning 超时兜底：防止 blend 回调丢失导致 flag 永远为 true
- 辅助瞄准目标丢失回退过渡：目标死亡/出视距时相机平滑回退 vs 直接释放

### 验收标准
- [mechanical] 服务端编译通过：`make build` 无错误
- [mechanical] 客户端编译通过：Unity `console-get-logs` 无 CS 错误
- [mechanical] 武器持久化协议存在：`grep "WeaponBagNtf" old_proto/` 命中
- [mechanical] 掏枪协议存在：`grep "DrawWeaponReq" old_proto/` 命中
- [mechanical] AimAssistComp 存在：`grep -r "class AimAssistComp" freelifeclient/` 命中
- [visual] 掏枪表现：玩家按键后手中出现武器模型，上半身切换到持枪姿态
- [visual] 瞄准表现：按住瞄准键后屏幕出现准心、相机拉近、自动锁定最近 NPC
- [visual] 射击表现：按攻击键后播放射击动画，命中目标时准心闪白
- [visual] 伤害生效：射击 NPC 后 NPC 血量减少（服务端日志确认 DealDamage 调用）

### 执行引擎
dev-workflow
