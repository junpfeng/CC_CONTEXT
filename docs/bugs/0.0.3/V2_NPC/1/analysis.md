# 根因分析报告 - Bug #1

**版本**: 0.0.3 / V2_NPC
**Bug ID**: #1
**分析日期**: 2026-03-29

---

## Bug 描述

大世界 NPC 播放走路动画但视觉上原地踏步；部分 NPC 同时插入地面。两个现象同一根因：路网节点 Y 偏低，NPC 实际在地表以下移动。

---

## 直接原因

### 原因 A：客户端 spawn 未做地面修正（"插地"现象）

**文件**: `freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcTransformComp.cs:52-54`

```csharp
var trans = _controller.GetTransform();
trans.position = snapshotData.Position;   // ← 直接用服务端 Y，无修正
trans.rotation = Quaternion.Euler(snapshotData.EulerAngle);
```

### 原因 B：服务端 spawn 和巡逻路径节点 Y 不可信（"原地踏步"根因）

| 文件 | 行号 | 问题 |
|------|------|------|
| `P1GoServer/.../bigworld_npc_spawner.go` | `spawnNpcAt` | spawn 坐标直接取路网节点，无 Raycast 修正 |
| `P1GoServer/.../bigworld_default_patrol.go` | `pickNewTarget` | `target.Y = center.Y`（来自 spawn，延续偏低 Y） |
| `P1GoServer/.../bigworld_navigation_handler.go` | `correctTargetY` | 仅修正终点 Y，A* 中间路径节点 Y 仍来自路网 |

结果链路：NPC 在地表以下平面水平移动 → 客户端 XZ delta > 0.001 → MoveMode.Walk → 走路动画触发（逻辑正确）→ 但从地面视角看像"原地踏步"。

### 原因 C：双系统写同一动画速度参数，基准值不一致（加重动画失真）

服务端步行速度 `1.4 m/s`（`scene_npc_mgr.go:22 defaultBigWorldWalkSpeed`），客户端两处基准不同：

| 文件 | 常量 | 值 | animSpeed 计算结果 |
|------|------|----|--------------------|
| `BigWorldNpcAnimationComp.cs:72` | `WalkRefSpeed` | `1.2f` | 1.4/1.2 = **1.17**（动画快 17%） |
| `BigWorldNpcMoveState.cs:19` | `WalkRefSpeed` | `1.5f` | 1.4/1.5 = **0.93**（动画慢 7%） |

两个系统每帧都写 `TransitionKey.BaseMove` 的 animSpeed，后执行者覆盖先执行者，结果不确定。

---

## 根本原因分类

**需求遗漏 + 遗漏检查 + 数据问题**

- 已知约束 `feedback_bigworld_y_offset.md`（大世界路网 Y 不可信，必须从 Y=200 Raycast 修正）未被 V2_NPC feature 范围覆盖
- 玩家角色已有地面修正（`PositionAdjuster.FindGroundPosition()`），NPC 未跟进
- 双系统 WalkRefSpeed 常量各自硬编码，未共享，未对齐服务端

---

## 影响范围

- 所有大世界场景下 V2 NPC 的初始生成位置及行走轨迹
- 路网节点 Y 与实际地形误差越大的区域，视觉穿地越明显
- animSpeed 不确定性影响所有处于 Walk 模式的 NPC 动画节奏

---

## 修复方案

### Fix 1：客户端 spawn Y 修正（`BigWorldNpcTransformComp.cs`）

在 `InitFromSnapshot()` 中从 Y=200 向下 Raycast 到 Grounds 层：

```csharp
public void InitFromSnapshot(TransformSnapShotData snapshotData)
{
    if (snapshotData == null) return;
    var trans = _controller.GetTransform();
    var rawPos = snapshotData.Position;
    var correctedPos = CorrectYToGround(rawPos);
    trans.position = correctedPos;
    trans.rotation = Quaternion.Euler(snapshotData.EulerAngle);
}

private static Vector3 CorrectYToGround(Vector3 position)
{
    var layerMask = LayerMask.GetMask("Grounds");
    var rayStart = new Vector3(position.x, 200f, position.z);
    if (Physics.Raycast(rayStart, Vector3.down, out RaycastHit hit, 300f, layerMask))
        return hit.point;
    return position;
}
```

> 注意：`LayerMask.GetMask` 应延迟初始化（参考 `feedback_static_field_layer_mask.md`）。

### Fix 2：服务端 A* 路径节点 Y 修正（`bigworld_navigation_handler.go`）

`correctTargetY` 当前只修正终点，需对路径中所有中间节点应用 Raycast 修正：

```go
for i, node := range path {
    if correctedY, ok := s.terrainAccessor.RaycastGroundY(node.X, node.Z); ok {
        path[i].Y = correctedY
    }
}
```

### Fix 3：统一 WalkRefSpeed 常量

将两处常量统一为 `1.4f`（对齐服务端 `defaultBigWorldWalkSpeed`），并从 `BigWorldNpcMoveState` 中移除对 animSpeed 的写入（让 `AnimationComp.UpdateSpeedDrivenAnimation` 作为唯一写入方）：

- `BigWorldNpcAnimationComp.cs:72`：`WalkRefSpeed = 1.4f`
- `BigWorldNpcMoveState.cs:19`：`WalkRefSpeed = 1.4f`，删除 `OnUpdate` 中的 `SetSpeed` 调用（避免双写）

---

## 是否需要固化防护

**是** — 大世界路网 Y 不可信是项目级已知约束，应写入 `freelifeclient/.claude/rules/`：
> 从路网/服务端坐标初始化大世界实体 Transform 时，必须做 Y=200 向下 Raycast 修正到 Grounds 层。

同时建议 V2_NPC 等大世界 NPC 特性的验收清单中增加：截图确认 NPC 在地表以上且有明显移动轨迹。

---

## 修复风险评估

**低** —
- Fix 1 仅修改 `InitFromSnapshot()` 一次性调用，后续帧同步路径不变；Raycast 未命中时退化为原行为
- Fix 2 为路径后处理步骤，不改变 A* 算法本身
- Fix 3 删除 MoveState 中的冗余写入，AnimationComp 仍每帧更新，不影响动画切换逻辑

---

## 关联文件

| 文件 | 说明 |
|------|------|
| `BigWorldNpcTransformComp.cs:52` | Fix 1 修改点 |
| `bigworld_navigation_handler.go` | Fix 2 修改点 |
| `BigWorldNpcAnimationComp.cs:72` | Fix 3 修改点（常量值 + 唯一写入职责） |
| `BigWorldNpcMoveState.cs:19` | Fix 3 修改点（删除 OnUpdate SetSpeed） |
| `scene_npc_mgr.go:22` | 服务端权威步行速度来源 |
| `PositionAdjuster.cs` | 玩家地面修正参考实现 |
| `feedback_bigworld_y_offset.md` | 已知约束来源 |
