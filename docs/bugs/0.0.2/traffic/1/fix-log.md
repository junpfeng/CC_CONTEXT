# Bug 修复日志 #1

- **版本**: 0.0.2
- **模块**: traffic
- **Bug**: 玩家站在路口导致所有车辆死锁
- **启动时间**: 2026-03-29 10:01:54

| 轮次 | 操作 | Critical | High | Medium | 状态 |
|------|------|----------|------|--------|------|
| 0 | 根因分析 | - | - | - | done (153s) |
| 1 | 代码修复 | - | - | - | done |

## 修复详情

### GTA5VehicleAI.cs
- 新增 `foundPlayer` 布尔变量，记录最近障碍是否为玩家
- 玩家检测命中时设置 `foundPlayer = true`
- UpdateObstacle 调用改为按 `foundPlayer` 选择 `ObstacleType.Player` vs `ObstacleType.Vehicle`

### AvoidanceUpgradeChain.cs
- 行人/玩家特殊处理条件扩展：`ObstacleType.Pedestrian` → `ObstacleType.Player || ObstacleType.Pedestrian`
- 玩家障碍直接进入 EmergencyBrake，不进入升级链，彻底防止 Reroute 循环

### JunctionDecisionFSM.cs
- `HasCrossingTraffic` 的 `nearby.Count > 0` 替换为速度过滤循环
- 仅 `CurrentSpeed > 0.5f` 的移动车辆计为有效交叉交通，停止车辆不再级联扩散死锁

ALL_FILES_FIXED
| 1 | 修复 | - | - | - | done |
| 1.c | 编译验证 | - | - | - | 通过 |
| 2 | Review | 0 | 2 | 1 | done |

## 总结
- **总轮次**：2
- **终止原因**：质量达标
- **最终质量**：Critical=0, High=2, Medium=1
- **完成时间**：2026-03-29 10:15:45
