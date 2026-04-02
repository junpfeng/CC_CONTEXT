# traffic 已修复 bug

## 2026-03-29

- [x] 玩家站在路口导致所有车辆死锁
  - **根因**：玩家被硬编码为 Vehicle 类型障碍（`ObstacleType.Player` 枚举从未接入 `Evaluate()` 处理分支），触发无限 Reroute 循环；同时 `HasCrossingTraffic` 未过滤停止车辆，导致死锁级联扩散至全路口
  - **修复**：
    - `GTA5VehicleAI.cs:260-262`：检测玩家时使用 `ObstacleType.Player` 而非 `ObstacleType.Vehicle`
    - `AvoidanceUpgradeChain.cs`：在 `Evaluate()` 中为 `Player` 添加独立分支（仿照 Pedestrian，直接 EmergencyBrake，不进入 Reroute 升级链）
    - `JunctionDecisionFSM.cs:238-239`：`HasCrossingTraffic` 添加速度过滤（`CurrentSpeed > 0.5f`），停止车辆不计为有效交叉流量
