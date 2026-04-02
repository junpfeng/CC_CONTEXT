═══════════════════════════════════════════════
  Bug Fix Review 报告
  版本：0.0.2
  模块：traffic
  审查文件：5 个（traffic 相关 3 个 + 非 traffic 2 个 + Server 多个）
═══════════════════════════════════════════════

## 一、根因修复验证

### 根因对应性

✅ 两个缺陷均有对应的代码修改：

- **缺陷 1（玩家障碍类型错误 → Reroute 死循环）**
  - `GTA5VehicleAI.cs`：新增 `foundPlayer` 标记，玩家检测独立于车辆检测，障碍类型正确设为 `ObstacleType.Player`
  - `AvoidanceUpgradeChain.cs:114-122`：`Evaluate()` 新增 Player/Pedestrian 分支，直接跳转 EmergencyBrake，完全绕过 Reroute 升级链

- **缺陷 2（HasCrossingTraffic 把停止车辆计为有效交叉交通）**
  - `JunctionDecisionFSM.cs:238-239`：SpatialGrid 查询结果中新增 `CurrentSpeed > 0.5f` 过滤，已停止车辆不再触发等待

### 修复完整性

✅ 两条触发路径均已覆盖：

- 玩家在 NPC 车辆前方：`GTA5VehicleAI.DetectAndEvaluateAvoidance()` 检测到后进入 EmergencyBrake，不再 Reroute → 解除缺陷 1
- 已停止车辆在路口附近：`HasCrossingTraffic` 仅计 `speed > 0.5f` 的移动车辆 → 解除缺陷 2
- 玩家离开后车辆恢复：距离 > 8m 时 `AvoidanceUpgradeChain` 自动 Reset，正常流程恢复

**边界案例验证：**
- 玩家（8m）+ 车辆（5m）同时存在：车辆先通过 `closestDist < 8` 更新，玩家 `fwdDot=8 ≥ closestDist=5` 条件不满足，`foundPlayer=false` → 障碍类型为 Vehicle，行为正确（近处车辆优先）
- 玩家（5m）+ 车辆（8m）同时存在：玩家先更新 `closestDist=5, foundPlayer=true`，车辆 `fwdDot=8 ≥ 5` 不满足 → 障碍类型为 Player，行为正确
- 速度恰好等于 0.5f 的车辆：`> 0.5f` 不包含，视为停止，不计入交叉交通（偏保守，可接受）

### 影响范围覆盖

✅ 分析报告中的所有影响位置均已处理：
- `GTA5VehicleAI.cs:260-262` ✅ 已修改障碍类型判断
- `AvoidanceUpgradeChain.cs` ✅ 已添加 Player 分支
- `JunctionDecisionFSM.cs:238-239` ✅ 已添加速度过滤

---

## 二、合宪性审查

### 客户端（.cs 文件）

| 条款 | 状态 | 说明 |
|------|------|------|
| 编译正确性 | ✅ | using 完整，API 存在，无类型歧义 |
| 日志规范 | ✅ | 无新增日志；原有日志用 `MLog` + `+` 拼接 |
| 错误处理 | ✅ | 无新增 try/catch；Result 类型未涉及 |
| 事件配对 | ✅ | 无新增事件订阅 |
| 热路径分配 | ✅ | `HasCrossingTraffic` 调用 `nearby.Count` 属性访问，`spatialGrid.QueryRadius` 返回缓存 List，无 new/LINQ |

### 服务端（.go 文件）

服务端变更均为 NPC Spawner 和日志格式，与 traffic bug 无关，不在本次审查范围内（见第四节）。

---

## 三、副作用与回归风险

**无 CRITICAL 风险。**

[MEDIUM] `JunctionDecisionFSM.cs:238` — 速度阈值魔法数字
  场景：HasCrossingTraffic 速度过滤判断
  影响：`0.5f` 未定义为命名常量，后续调整时需全局搜索
  建议：提取为 `private const float MinCrossingSpeedThreshold = 0.5f;`

---

## 四、最小化修改检查

❌ **存在无关修改** — 本次 commit 包含多处与 traffic bug 无关的变更：

[HIGH] `freelifeclient/BigWorldNpcController.cs` + `BigWorldNpcFsmComp.cs` — 与 traffic bug 无关
  场景：NPC FSM 状态管理优化（turn state、patrol oscillation 修复）
  影响：这些是独立的功能修复，与路口死锁问题无关联，混入同一 commit 增加回归风险且难以追溯
  建议：将 NPC FSM 修复单独 commit

[HIGH] `P1GoServer` 全部变更（`bigworld_npc_spawner.go`、`scene_impl.go`、日志格式修改）— 与 traffic bug 无关
  场景：Static Patrol NPC 预生成逻辑、日志 `%s→%v` 格式改动
  影响：与客户端 traffic 死锁无关，独立功能变更混入同一 commit
  建议：服务端 NPC Spawner 变更单独 commit；日志格式修改可附带说明

---

## 五、总结

```
  CRITICAL: 0 个（必须修复）
  HIGH:     2 个（强烈建议修复）
  MEDIUM:   1 个（建议修复，可酌情跳过）
```

  结论: **根因修复通过，建议整理 commit 后合入**

  重点关注:
  1. [HIGH] NPC FSM 变更（`BigWorldNpcFsmComp.cs`）与 traffic bug 无关，混入同一 commit 影响可追溯性，建议拆分
  2. [HIGH] P1GoServer 静态 Patrol Spawner 变更与 traffic 无关，建议单独 commit
  3. [MEDIUM] `JunctionDecisionFSM.cs` 中 `0.5f` 速度阈值建议提取为命名常量
  4. 核心 traffic 修复逻辑正确，根因对应，完整覆盖两个缺陷，无新的 CRITICAL 引入

<!-- counts: critical=0 high=2 medium=1 -->
