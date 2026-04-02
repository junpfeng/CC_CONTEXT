# 小镇交通系统完善 — 设计方案

> **注意**：本文档针对 S1Town 小镇交通系统（轻量方案）。大世界交通系统（GTA5 式）请参阅 `design/ai/big_world_traffic/`。

## 需求回顾

当前小镇交通系统：15 辆车沿固定 Catmull-Rom 路线匀速巡航，无碰撞避让、无速度差异、无 AI。
目标：参考 GTA5 和大世界方案，在不引入 ECS 的前提下，用轻量 GameObject 方案完善交通表现。

## 改动范围

仅客户端 `freelifeclient/`，不涉及协议、服务器、配置表。

## 功能设计

### 1. 前方碰撞检测与避让

**核心逻辑**：每帧沿车辆前方做 SphereCast 检测障碍物（其他车辆、玩家车辆），发现后减速/停车。

**检测参数**：
- 检测距离：15m（远距离减速）+ 5m（紧急制动）
- SphereCast 半径：1.5m
- 检测层：Vehicle layer
- 检测频率：与 AI LOD 等级联动

**行为**：
- 15m 内发现前车 → 线性减速到前车速度
- 5m 内发现障碍 → 紧急制动（速度因子 → 0）
- 障碍消失 → 恢复原速（加速率 2f，与弯道加速一致）

### 2. 速度差异化（简化驾驶人格）

**不做完整 17 参数人格系统**，仅引入速度随机化：
- 基础速度范围：9~14 m/s（≈32~50 km/h）
- Init 时随机分配，整个生命周期不变
- 弯道减速比例不变（统一 55%）

### 3. 车辆数量提升

- MaxTrafficVehicles：15 → 25
- 路线数量：15 → 25（需重新生成 traffic_routes.json）
- gen_cruise_routes.py 参数调整：NUM_ROUTES = 25

### 4. AI LOD（更新频率分级）

基于与玩家的 XZ 距离，降低远处车辆的更新频率：

| LOD | 距离 | Update 频率 | 碰撞检测 |
|-----|------|------------|---------|
| FULL | <80m | 每帧 | 每帧 SphereCast |
| MEDIUM | 80-150m | 每 3 帧 | 每 6 帧 |
| FAR | >150m | 每 5 帧 | 无 |

隐藏阈值保持 200/220m 不变。

### 5. 跟车行为

当前方检测到同向交通车辆时：
- 计算前车速度（通过 TownTrafficMover 引用）
- 匹配前车速度 + 保持安全距离（8m）
- 距离 < 8m 时减速，距离 > 12m 时恢复自身速度

## 代码改动

### TownTrafficMover.cs 改动

1. 新增字段：
   - `_detectionDistance = 15f`
   - `_brakeDistance = 5f`
   - `_obstacleSpeedFactor = 1f`（障碍物导致的减速因子）
   - `_lodLevel`（0=FULL, 1=MEDIUM, 2=FAR）
   - `_lodFrameCounter`

2. Update 流程改造：
   ```
   UpdateLOD()           // 计算 LOD 等级
   if (跳帧) return      // LOD 跳帧
   DetectObstacle()      // 前方检测（LOD 联动频率）
   原有移动逻辑          // effectiveSpeed *= _obstacleSpeedFactor
   ```

3. DetectObstacle()：SphereCast 前方 → 更新 _obstacleSpeedFactor

### TownTrafficSpawner.cs 改动

1. MaxTrafficVehicles = 25
2. Init 时传入随机速度：`Random.Range(9f, 14f)`

### gen_cruise_routes.py 改动

1. NUM_ROUTES = 25
2. 重新生成 traffic_routes.json

## 验收测试

1. 登录小镇场景，观察车辆数量（应有 25 辆）
2. 观察不同车辆速度差异
3. 站在车辆前方，观察是否减速/停车
4. 在远处观察车辆是否正常移动（LOD 不应产生视觉卡顿）
5. 两辆车在同一路线前后行驶时，后车应跟车减速
