# GTA5 风格武器系统 — 技术设计

## 1. 需求回顾

| ID | 标题 | 优先级 | 端 | 摘要 |
|----|------|--------|-----|------|
| REQ-001 | 武器持久化与登录下发 | P0 | 双端 | PlayerWeaponBag 持久化 MongoDB，登录 WeaponBagNtf 下发，新角色默认手枪 |
| REQ-002 | 掏枪/收枪 | P0 | 双端 | DrawWeapon/HolsterWeapon + 上半身动画 + 模型挂载，DrawWeaponReq/Res 状态同步 |
| REQ-003 | 瞄准系统 | P0 | 客户端 | 准心 UI + FOV 缩放(~40°) + IK 权重渐入，补齐 PlayerGunFightComp Aim 状态 |
| REQ-004 | 辅助瞄准(Snap-to) | P0 | 客户端 | AimAssistComp，OverlapSphere 扇形检测最近敌人，Snap 相机朝向 |
| REQ-005 | 射击流程与伤害 | P0 | 双端 | Raycast → ShotData/HitData → CheckManager(RPM+距离+方向) → DealDamage |
| REQ-006 | 伤害反馈 UI | P1 | 客户端 | Hit Marker 准心闪白 + NPC 受击动画 |

## 2. 架构设计

### 2.1 系统边界

```
old_proto/               → 协议定义（WeaponBagNtf, DrawWeaponReq/Res）
P1GoServer/
  common/citem/          → Weapon 数据结构（复用）
  common/db_entry/       → PlayerWeaponBag 持久化
  scene_server/damage/   → HandleShotData/HandleHitData/CheckManager（扩展 RPM+方向校验）
  scene_server/net_func/ → DrawWeaponReq 处理
  logic_server/          → 登录时 WeaponBagNtf 下发
freelifeclient/
  BigWorld/Common/Comp/Weapon/WeaponComp.cs  → DrawWeapon/HolsterWeapon（扩展）
  BigWorld/Entity/Player/Comp/PlayerGunFightComp.cs → Aim 子状态补齐
  BigWorld/Entity/Player/Comp/AimAssistComp.cs      → 新增
  BigWorld/Player/State/GunFightState.cs     → 射击 Raycast 流程
  UI/                                        → 准心 Widget + Hit Marker
```

**调用关系**:
- 客户端按键 → PlayerInputComp(Aim/Attack) → GunFightState → WeaponComp.DrawWeapon → 发 DrawWeaponReq
- 客户端射击 → Raycast → 发 ShotData+HitData → 服务端 HandleShotData → CheckManager.AddShotInfo → HandleHitData → DealDamage → 广播 SceneEvent
- 登录 → logic_server 加载 PlayerWeaponBag → WeaponBagNtf → 客户端 WeaponComp 初始化武器列表

### 2.2 状态流转

武器状态机（集成在 PlayerGunFightComp._subFsm 已有框架上）:

```
空手(Idle) ──[按掏枪键]──→ 掏枪中(DrawWeaponReq) ──[Res成功+blend完成]──→ 持枪(Armed)
持枪(Armed) ──[按瞄准键]──→ 瞄准(Aim) ──[按攻击键]──→ 射击(Fire)
瞄准(Aim) ──[松开瞄准]──→ 持枪(Armed)
射击(Fire) ──[射击动画完成/松开攻击]──→ 瞄准(Aim)
持枪(Armed) ──[按收枪键/进车/死亡]──→ 收枪中(Holster) ──[blend完成]──→ 空手(Idle)
掏枪中(DrawWeaponReq) ──[Res失败]──→ 空手(Idle)（回滚动画）
```

**状态锁**: `_isTransitioning` 在 Draw/Holster blend 0.2s 期间为 true，阻止重入。超时兜底 0.5s 强制清除。

### 2.3 错误处理

| 错误码(int32) | 名称 | 场景 | 处理 |
|--------------|------|------|------|
| 0 | Success | 掏枪/射击成功 | — |
| 1 | PlayerDead | 死亡状态掏枪 | 客户端回滚动画 |
| 2 | PlayerInVehicle | 载具中掏枪 | 客户端回滚动画 |
| 3 | PlayerControlled | 被控状态掏枪 | 客户端回滚动画 |
| 4 | WeaponNotFound | weapon_id 无效 | 客户端提示 |
| 5 | RateLimit | RPM 超频射击 | 丢弃 ShotData，不扣弹药 |
| 6 | DirectionInvalid | 射击方向与目标夹角过大 | 丢弃 HitData |
| 7 | InGunFreeZone | 禁枪区掏枪（客户端本地校验） | 客户端直接阻止，不发 Req |

## 3. 协议设计（old_proto）

### 3.1 新增消息

在 `old_proto/scene/scene.proto` 中新增:

```protobuf
// 武器背包下发（登录时推送）
message WeaponBagNtf {
  repeated base.WeaponProto weapons = 1;  // 武器列表
  int32 in_hand_index = 2;                // 当前手持索引，-1=空手
}

// 掏枪/收枪请求（entity_id 从 session 获取，不由客户端上报）
message DrawWeaponReq {
  int32 weapon_id = 1;    // 目标武器配置 ID，0=收枪
}

// 掏枪/收枪响应
message DrawWeaponRes {
  int32 result_code = 1;  // 0=成功，非零见错误码表
  int32 weapon_id = 2;    // 回传武器 ID
}
```

注册到 scene service 的消息路由：WeaponBagNtf 为 Ntf 类型（服务端主动推送），DrawWeaponReq/Res 为 Req/Res 类型。

### 3.2 复用消息

- **ShotData**（scene.proto:1260）: `shooter_entity` + `weapon_cell_index`，原样复用
- **HitData**（scene.proto:1239）: 包含 `attack_entity`、`weapon_id`、`fire_position`、`hit_position`、`target_entity`、`damage` 等完整字段，原样复用
- **WeaponProto**（base.proto:114）: `weapon_id` + `weapon_type` + `weapon_level` + `weapon_quality` + `attributes` + `weapon_gun_data`，WeaponBagNtf 直接引用
- **GunDataProto**（base.proto:108）: `gun_id` + `appendix_list` + `enhance_list`，透传

## 4. 服务端设计（P1GoServer）

### 4.1 PlayerWeaponBag 数据结构与持久化

**数据结构**（`common/citem/weapon_bag.go` 新增）:

```go
// PlayerWeaponBag 玩家武器背包
type PlayerWeaponBag struct {
    Weapons     []*Weapon // 武器列表，复用已有 citem.Weapon
    InHandIndex int32     // 当前手持武器索引，-1=空手
}
```

**持久化**:
- 存储位置：玩家 MongoDB 文档，新增 `weapon_bag` 字段
- 序列化：通过 ORM 工具生成（XML 定义 → make orm），或直接在 db_entry 中手动添加
- 读取时机：logic_server 登录流程加载玩家数据时一并读取
- 写入时机：dirty flag 延迟持久化（登出/定期存盘时写入），不在每次掏枪/收枪时立即写库

**ToProto 方法**:

```go
func (bag *PlayerWeaponBag) ToWeaponBagNtf() *proto.WeaponBagNtf {
    weapons := make([]*proto.WeaponProto, 0, len(bag.Weapons))
    for _, w := range bag.Weapons {
        if w != nil {
            weapons = append(weapons, w.ToProtoWeapon())
        }
    }
    return &proto.WeaponBagNtf{
        Weapons:     weapons,
        InHandIndex: bag.InHandIndex,
    }
}
```

### 4.2 掏枪状态校验逻辑

在 `scene_server/internal/net_func/` 新增 DrawWeaponReq 处理函数:

```
校验顺序:
1. 死亡检查 (BaseStatusComp.IsDead) → result_code=1
2. 载具检查 (VehicleComp.IsInVehicle) → result_code=2
3. 被控检查 (BaseStatusComp 控制状态) → result_code=3
4. weapon_id 合法性 (EquipComp.WeaponList 中查找) → result_code=4
注: 禁枪区(GunFreeZone)仅客户端碰撞体实现，服务端无区域系统，本期不做服务端禁枪区校验
5. 更新 EquipComp.ActiveWeaponCellIndex + SetSync()（帧同步广播给场景内其他玩家，远端玩家 WeaponComp 响应同步事件触发 DrawWeapon/HolsterWeapon 表现）
6. 标记 PlayerWeaponBag dirty（延迟持久化，登出/定期存盘时写入 MongoDB）
8. 返回 DrawWeaponRes{result_code=0, weapon_id=req.WeaponId}
```

weapon_id=0 表示收枪，将 ActiveWeaponCellIndex 置为 -1。

### 4.3 射击验证增强（RPM + 方向角度）

在 `damage/check_manager.go` 扩展:

**RPM 校验** — CheckManager 新增 `lastShotTime` 字段（每实体每武器）:
- HandleShotData 入口处调用 `CheckRPM(entityID, weaponID)`
- 从 `config.GetCfgGunById()` 获取 `fire_rate`（发/分钟）
- 最小间隔 = `60.0 / fire_rate` 秒
- 若距上次射击时间 < 最小间隔 → 丢弃 ShotData，返回 RateLimit 错误（通过 SceneEvent 通知客户端）
- 日志: `log.Warnf("[Damage] RPM exceeded: entity_id=%v, weapon_id=%v, interval=%v", ...)`

**方向角度校验** — HandleHitData 中新增:
- 从 HitData.fire_position 和 HitData.hit_position 计算射击方向
- 从 attacker 实体位置到 target 实体位置计算目标方位
- 两向量 XZ 平面夹角 > 90° → 判定异常，丢弃 HitData
- 日志: `log.Warnf("[Damage] direction invalid: entity_id=%v, angle=%v", ...)`

### 4.4 伤害扩展（载具 canTakeDamage）

在 `damage/damage.go` 的 `canTakeDamage` 中扩展:

```
当前逻辑:
  1. 自伤检查
  2. BaseStatusComp.IsDead → Invincible
  3. 按场景类型分流

扩展（在步骤 2 之前插入）:
  1.5. 检查 target 是否为载具实体（GetComponentAs[VehicleComp]）
       → 若是载具: 返回 (true, HitResultType_Common)
       → 载具没有 BaseStatusComp，跳过步骤 2
```

DealDamage 扩展：当 target 为载具时，调用 `VehicleComp.TakeDamage(damage)` 而非操作 BaseStatusComp。注意 VehicleComp 当前无 TakeDamage 方法和 HP 字段，需 [DDRP-INLINE] 新增（约 30 行：HP 字段 + TakeDamage 方法 + 扣血逻辑）。载具受击后的具体表现（冒烟/爆炸）为待细化项，本期仅扣血。

### 4.5 默认武器初始化

在创建角色流程中新增:

```
1. 从 CfgWeapon 查找 DesertEagle 配置（按预定义 weapon_id 或 name 匹配）
2. 若找不到 → log.Warnf("[WeaponBag] DesertEagle not in config, fallback")
   兜底: 遍历 CfgWeapon 取第一个 WeaponType=Remote 的武器
3. 构造 PlayerWeaponBag{Weapons: []{desertEagle}, InHandIndex: -1}
4. 写入 MongoDB 玩家文档
```

## 5. 客户端设计（freelifeclient）

### 5.1 WeaponComp 扩展（DrawWeapon/HolsterWeapon + 状态锁）

在 `WeaponComp.cs` 中新增:

```csharp
// 状态锁，防止 blend 期间重入
private bool _isTransitioning;
private float _transitionTimeout = 0.5f;
private float _transitionTimer;

// 掏枪: 发送 DrawWeaponReq，播放上半身 blend 过渡
public void DrawWeapon(int weaponCfgId)
{
    if (_isTransitioning) return;
    _isTransitioning = true;
    _transitionTimer = _transitionTimeout;
    // 发送 DrawWeaponReq
    // 预播放上半身动画（0.2s blend 到 Idle 持枪）
    // 武器模型挂载到 HandR 骨骼点（通过 WeaponHolderPivotContainer）
}

// 掏枪响应回调
public void OnDrawWeaponRes(DrawWeaponRes res)
{
    if (res.ResultCode != 0)
    {
        // 回滚: 停止上半身动画，模型卸载
        _isTransitioning = false;
        return;
    }
    // 成功: blend 完成后清除 _isTransitioning（由动画回调触发）
}

// 收枪
public void HolsterWeapon()
{
    if (_isTransitioning) return;
    _isTransitioning = true;
    _transitionTimer = _transitionTimeout;
    // 发送 DrawWeaponReq{weapon_id=0}
    // 播放收枪过渡（0.2s blend 回空手）
    // 武器模型从手部移回背部/隐藏
}
```

OnUpdate 中增加超时兜底：`_transitionTimer` 倒计时，到 0 时执行完整回滚（停止动画+卸载模型+`_isTransitioning = false`），而非仅清 flag。超时回滚后若迟到的 Res 到达，因 `_isTransitioning = false` 直接忽略（不二次触发状态变更）。

**注意**: 使用 `+` 拼接日志，不用 `$""`。

### 5.2 PlayerGunFightComp 瞄准补齐

在已有 SubState.Aim 分支中补齐:

1. **准心 UI**: 进入 Aim 时通过 UIManager 打开 CrosshairWidget（屏幕中央十字线），退出时关闭
2. **FOV 缩放**: 进入 Aim 时 CameraManager.SetFOV(40f, 0.2f)，退出时恢复默认 FOV
3. **IK 权重**: 通过已有 `PlayerWeaponIK` 组件控制 IK 权重，进入 Aim 时 tween 到 1.0，退出时 tween 到 0.0

SubState 流转（复用已有 FastFsm）:

```
Idle → [AimKeyDown] → Aim → [AttackKeyDown] → WaitingFire → Fire → [AnimEnd] → Aim
Aim → [AimKeyUp] → Idle
```

### 5.3 AimAssistComp 新增

新建 `BigWorld/Entity/Player/Comp/AimAssistComp.cs`:

```csharp
using UnityEngine;
using Vector3 = UnityEngine.Vector3;

public class AimAssistComp : Comp, IUpdate
{
    private EntityBase _lockTarget;
    private float _assistRadius = 15f;
    private float _assistAngleDeg = 60f;  // 扇形半角（度数）
    private float _snapSpeed = 10f;
    private int _detectInterval = 3;      // 每 N 帧检测一次（性能节流）
    private int _frameCounter;

    // 按瞄准键时调用
    public EntityBase TryAcquireTarget(Vector3 cameraForward, Vector3 playerPos)
    {
        // OverlapSphere(playerPos, _assistRadius)
        // 过滤: 仅 NPC 实体，在扇形范围内（与 cameraForward 夹角 < _assistAngleDeg）
        // 排序: 距离最近优先
        // 返回最佳目标，缓存到 _lockTarget
    }

    // 持续跟踪: 每帧将相机朝向 Lerp 到目标
    public void OnUpdate(float deltaTime)
    {
        _frameCounter++;
        if (_lockTarget == null) return;
        // 目标丢失判定: 死亡/出视距/超出扇形
        // 相机朝向 Snap: CameraManager.LookAt 平滑旋转
    }

    // 目标丢失时平滑回退自由视角（0.3s 过渡）
    public void ReleaseLock() { _lockTarget = null; }
}
```

**必须在 PlayerController.OnInit 中 AddComp<AimAssistComp>()**（lesson: feedback_client_comp_registration）。

### 5.4 射击流程（Raycast + ShotData 上报）

在 GunFightState.OnUpdate 的 Fire 子状态中:

```
1. 播放射击动画（已有 Atk FBX 资源）
2. 从 Camera.main.ViewportPointToRay(0.5, 0.5) 做 Physics.Raycast
   - 射程: 从 CfgGun 读取（默认 100m）
   - LayerMask: 包含 NPC + Vehicle + Environment
3. 命中判定:
   - Hit collider 关联的 EntityBase → 获取 entity_id
   - 计算 HitData 各字段（fire_position=枪口位置, hit_position=碰撞点, damage=本地预算）
4. 发送 ShotData{shooter_entity, weapon_cell_index}
5. 发送 HitData{完整字段}
6. RPM 节流: 本地维护 _lastFireTime，间隔不足时不发送（与服务端双重校验）
```

### 5.5 伤害反馈 UI（Hit Marker + 准心）

**CrosshairWidget**（新增 UI Widget）:
- 屏幕中央十字线，基础 UI Toolkit 实现
- 4 条短线组成十字，颜色默认白色

**Hit Marker**:
- 命中时准心闪白 0.15s（颜色变白+缩放脉冲）
- 通过 EventManager 监听 `EventId.OnHitConfirmed` 触发
- 服务端广播 SceneEvent::Hit 后客户端 HandleHitData 发出该事件

**NPC 受击动画**:
- 已有 HitReaction 系统（UpperBody 层），复用 NPC AnimationComp 的 PlayHitReaction

### 5.6 待细化项实现策略

| 待细化项 | 实现策略 |
|---------|---------|
| 载具受击表现 | 本期仅扣血值，冒烟/爆炸后续版本 |
| 默认手枪 weapon_id | 实现时从 Weapon.xlsx 读取确认 |
| 准心 UI 样式 | 基础十字线，后续按 GTA5 参考调整 |
| AimAssist 频率节流 | 每 3 帧检测一次，大世界 NPC 密集区可调为 5 帧 |
| 禁枪区交互 | 纯客户端：持枪进入 GunFreeZone → 强制 HolsterWeapon；禁枪区内掏枪 → 本地阻止不发 Req |
| 默认手枪兜底 | 配置表无 DesertEagle 时取第一个 Remote 武器 |
| 掏枪回滚竞态 | _isTransitioning 期间缓存 Res，blend 完成时检查并决定 |
| _isTransitioning 超时 | 0.5s 超时兜底强制清除 |
| 辅助瞄准目标丢失 | 0.3s 平滑回退自由视角 |

## 6. 事务性设计

### 6.1 掏枪请求-响应事务

```
时序:
  Client                          Server
    |  DrawWeaponReq(weapon_id)     |
    |------------------------------>|
    |  [预播放 blend 动画]           |  [校验状态: 死亡/载具/被控/禁枪区]
    |  [_isTransitioning = true]    |  [校验 weapon_id 合法性]
    |                               |  [更新 EquipComp + SetSync]
    |  DrawWeaponRes(result_code)   |  [持久化 InHandIndex]
    |<------------------------------|
    |  [result=0: 等 blend 完成]    |
    |  [result≠0: 回滚动画+模型]    |
```

**竞态保护**:
- blend 期间 Res 到达: 缓存 result_code，blend 回调时判断
- 网络延迟 >200ms: blend 已完成但 Res 未到 → 保持持枪姿态，Res 失败到达时立即回滚
- _isTransitioning 超时兜底: 0.5s 后强制清除，避免 flag 永驻

### 6.2 射击验证事务

```
时序:
  Client                          Server
    |  [Raycast 命中判定]            |
    |  ShotData(entity, cell_index) |
    |------------------------------>|  [CheckRPM → 超频则丢弃]
    |  HitData(完整字段)             |  [AddShotInfo 注册记录]
    |------------------------------>|  [CheckShotInfo 匹配验证]
    |                               |  [方向角度校验]
    |                               |  [canTakeDamage → DealDamage]
    |  SceneEvent::Hit (广播)       |  [addSceneEvent 广播]
    |<------------------------------|
    |  [Hit Marker + 受击动画]       |
```

客户端同一帧内先发 ShotData 后发 HitData，利用 TCP 有序性保证到达顺序。服务端先注册再验证。CheckManager 记录 15 秒过期自动清理。

## 7. 接口契约

### 7.1 协议 → 服务端

| 协议 | 处理函数 | 所在文件 |
|------|---------|---------|
| DrawWeaponReq | handleDrawWeaponReq | scene_server/internal/net_func/weapon_func.go（新增） |
| WeaponBagNtf | 登录流程主动推送 | logic_server/internal/service/（登录链路） |
| ShotData | HandleShotData | scene_server/internal/damage/shot.go（已有，扩展 RPM） |
| HitData | HandleHitData | scene_server/internal/damage/hit.go（已有，扩展方向校验） |

### 7.2 协议 → 客户端

| 协议 | 处理逻辑 | 所在文件 |
|------|---------|---------|
| WeaponBagNtf | 初始化 WeaponComp 武器列表（复用 OnRemoteWeaponListAdd 逻辑） | WeaponComp.cs |
| DrawWeaponRes | OnDrawWeaponRes 回调，成功/失败分支 | WeaponComp.cs |
| SceneEvent::Hit | HandleHitData → 发 EventId.OnHitConfirmed → Hit Marker + 受击动画 | 已有 SceneEvent 处理链路 |
| SceneEvent::Shot | HandleShotData → 播放射击音效/特效（本期跳过） | 已有 |

## 8. 验收测试方案

### [TC-001] 武器持久化登录下发

**前置条件**: 服务端运行，新角色（或已有角色）
**操作步骤**:
1. 通过 `/unity-login` 登录游戏
2. `mcp__ai-game-developer__script-execute`: 读取本地玩家 WeaponComp._weapons 列表
3. `mcp__ai-game-developer__script-execute`: 读取 WeaponComp._weapons[0].CfgId 确认武器 ID
**验证方式**:
- 武器列表非空（至少 1 把默认手枪）
- 服务端日志包含 `WeaponBagNtf` 推送记录

### [TC-002] 掏枪/收枪

**前置条件**: 已登录，角色空手状态
**操作步骤**:
1. `mcp__ai-game-developer__script-execute`: 调用 `WeaponComp.DrawWeapon(手枪CfgId)`
2. `mcp__ai-game-developer__screenshot-game-view`: 截图确认武器模型出现在手部
3. 等待 0.5s
4. `mcp__ai-game-developer__script-execute`: 调用 `WeaponComp.HolsterWeapon()`
5. `mcp__ai-game-developer__screenshot-game-view`: 截图确认武器模型消失/回到背部
**验证方式**:
- 截图可见武器模型在手部 → 收枪后消失
- `mcp__ai-game-developer__console-get-logs`: 无 CS 错误

### [TC-003] 瞄准系统

**前置条件**: 已登录，持枪状态
**操作步骤**:
1. `mcp__ai-game-developer__script-execute`: 模拟 Aim 输入 `PlayerInputComp.OnAimKeyPerformed(true)`
2. `mcp__ai-game-developer__screenshot-game-view`: 截图确认准心 UI 出现 + FOV 缩小
3. `mcp__ai-game-developer__script-execute`: 读取当前 Camera FOV 值
4. `mcp__ai-game-developer__script-execute`: 模拟松开 `PlayerInputComp.OnAimKeyPerformed(false)`
**验证方式**:
- 截图可见屏幕中央十字准心
- FOV 值约为 40（±5 容差）
- 松开后 FOV 恢复默认

### [TC-004] 辅助瞄准

**前置条件**: 已登录，持枪状态，场景中有 NPC
**操作步骤**:
1. `mcp__ai-game-developer__script-execute`: 获取最近 NPC 位置
2. `mcp__ai-game-developer__script-execute`: 模拟 Aim 输入
3. `mcp__ai-game-developer__script-execute`: 读取 AimAssistComp._lockTarget
4. `mcp__ai-game-developer__screenshot-game-view`: 截图确认相机朝向 NPC
**验证方式**:
- _lockTarget 非 null
- 截图中相机朝向 NPC 方向

### [TC-005] 射击与伤害

**前置条件**: 已登录，持枪+瞄准状态，面向 NPC
**操作步骤**:
1. `mcp__ai-game-developer__script-execute`: 读取目标 NPC 当前血量
2. `mcp__ai-game-developer__script-execute`: 模拟 Attack 输入 `PlayerInputComp.OnAttackKeyPerformed(true)`
3. 等待 0.3s
4. `mcp__ai-game-developer__script-execute`: 再次读取 NPC 血量
5. `mcp__ai-game-developer__screenshot-game-view`: 截图
**验证方式**:
- NPC 血量减少
- 服务端日志包含 `DealDamage` 调用记录

### [TC-006] Hit Marker

**前置条件**: TC-005 执行后
**操作步骤**:
1. 在 TC-005 射击后立即截图
2. `mcp__ai-game-developer__screenshot-game-view`: 截图
**验证方式**:
- 截图中准心有闪白效果（可能因时机难以捕捉，备选: 通过 script-execute 检查 CrosshairWidget._isFlashing 状态）

## 9. 风险缓解

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|---------|
| PlayerWeaponIK 已存在 | — | — | 复用已有 PlayerWeaponIK（基于 FinalIK ArmIK，已在 PlayerController 注册），通过其公开接口控制 IK 权重 |
| Weapon.xlsx 无 DesertEagle | 低 | 低 | 兜底取第一个 Remote 武器，日志 Warning |
| 掏枪动画资源缺失 | 已确认 | 中 | 使用 Idle 持枪动画 0.2s blend 过渡，视觉效果可接受 |
| AimAssist 性能开销 | 中 | 中 | 每 3 帧检测 + 半径限制 15m + 扇形过滤，大世界可调为 5 帧 |
| 掏枪网络延迟竞态 | 中 | 低 | _isTransitioning 缓存 + 0.5s 超时兜底 + blend 回调判定 |
| 载具 canTakeDamage 缺失 VehicleComp 接口 | 中 | 中 | 实现时确认 VehicleComp 是否有 HP/TakeDamage，无则新增最小实现 |
| CheckManager RPM 校验时间精度 | 低 | 低 | 使用 mtime.NowMilliTickWithOffset() 毫秒级精度 |
| 禁枪区仅客户端校验 | 低 | 低 | 本期仅客户端 GunFreeZone 碰撞体本地阻止，服务端无区域系统不做校验 |
