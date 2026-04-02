═══════════════════════════════════════════════
  Feature Review 报告
  功能：V2_NPC
  版本：0.0.2
  任务：task-05（BigWorldNpcSpawner 改造）
  审查文件：2 个（bigworld_npc_spawner.go, bigworld_walk_zone.go）
═══════════════════════════════════════════════

## 一、合宪性审查

### 客户端
task-05 为纯服务端任务，无客户端文件变更，跳过客户端合宪性检查。

### 服务端
| 条款 | 状态 | 说明 |
|------|------|------|
| 禁编辑区域 | ✅ | 未触碰 orm/golang、orm/redis、cfg_*.go 等禁区 |
| 错误处理 | ✅ | 所有 error 显式处理，使用 fmt.Errorf + %w 包装，GMSpawnAt 返回 error |
| 全局变量 | ✅ | 无新增全局变量 |
| Actor 独立性 | ✅ | BigWorldNpcSpawner 在 Scene goroutine 内访问，rng 注释明确 "非并发安全" |
| 消息传递 | ✅ | 通过 npcMgr.CreateDynamicBigWorldNpc / DestroyNpc 委托上层，未直接跨 Actor 访问 |
| defer 释放锁 | ✅ | 无 mutex 使用（Actor 模型保证） |
| safego | ✅ | 无新增 goroutine |
| 日志格式 | ✅ | 全部使用 log.Infof/Warningf/Errorf，字段命名 npc_cfg_id= 格式正确 |

---

## 二、Plan 完整性

### 已实现
- [x] `bigworld_npc_spawner.go` — footwalk 路点过滤、WalkZone 配额注入、巡逻路线生成点选择、GM 命令
- [x] `bigworld_walk_zone.go` — WalkZoneQuotaCalculator（stateless）、WalkZoneConfig、QuotaResult 定义
- [x] `SetWalkZoneConfig` / `SetWalkZoneCalculator` / `LoadWalkZoneConfig` — 配额配置注入接口
- [x] `SetPatrolMgr` — 巡逻路线注入 + routesByZone 索引构建
- [x] `TickQuota` — 每 quotaInterval 秒驱动配额计算，缓存 lastQuotaResults
- [x] `findBestSpawnPosition` — 优先配额缺口 zone + 降级随机路点
- [x] `findSpawnPositionFromPatrolRoute` — 最低负载路线节点选取
- [x] `spawnNpcAt` / `despawnNpc` — zoneNpcCount +1 / -1（single source of truth）
- [x] `GMSpawnAt` / `GMSpawn` / `GMClearAll` — GM 命令，GMClearAll 走标准销毁流程
- [x] `initSpawnPoints` — footwalk 优先 + WalkZone AABB 过滤 + 降级兼容

### 遗漏
无显著遗漏，所有 plan 要求的文件和核心功能均已实现。

### 偏差
1. **`GetZoneForPos` 重叠处理算法**（HIGH）：plan 明确规定"2+ AABB 包含同一点时，返回中心距离最近的 zone"；实际实现为顺序遍历取第一个匹配，等价于按配置文件顺序确定优先级，不符合 plan 规格。
2. **`activeNpcInfo.Position` 不更新**（HIGH）：`zoneNpcCount` 的设计目标是 "single source of truth"，但 `despawnNpc` 通过 `activeNpcInfo.Position`（生成时快照）计算所属 zone 后递减计数。若 NPC 巡逻过程中跨 zone，递减的是错误 zone，导致配额统计偏差。

---

## 三、边界情况与健壮性

[HIGH] bigworld_npc_spawner.go — activeNpcInfo.Position 永久为生成时快照，不随 NPC 移动更新
  场景: NPC 生成于 zone A 边界，巡逻至 zone B 后被 despawnNpc 回收
  影响: despawnNpc 调用 GetZoneForPos(npcInfo.Position) 得到 zone A 并递减 A 的计数，实际应递减 B；导致 zone A 计数偏低、zone B 计数偏高，配额系统长期运行后误差累积，均衡分布失效
  相关代码: despawnNpc:649、doDespawn:470-476

[HIGH] bigworld_walk_zone.go:229 — GetZoneForPos 返回首个匹配 zone，不处理多 AABB 重叠
  场景: 地图边界区域两个 zone 的 AABB 存在重叠，NPC 生成在重叠区
  影响: zone 归属由配置文件中的顺序决定，而非几何中心距离。导致两 zone 之间的配额统计非确定性，且与 plan 算法不一致；生成点过滤（initSpawnPoints）与计数维护（spawnNpcAt/despawnNpc）使用同一函数，若两处结果因配置顺序变更而改变，计数会错位
  相关代码: bigworld_walk_zone.go:225-234

[MEDIUM] bigworld_npc_spawner.go:411 — findBestSpawnPosition 按非确定性 map 遍历顺序选 zone
  场景: 多个 zone 同时存在 Deficit > 0
  影响: 每次 Tick 随机选一个有缺口的 zone，而非优先填补 Deficit 最大的 zone；高峰时段可能导致各 zone 填充速度不均匀，与 plan 设计意图（均衡分布）轻微偏离
  建议: 可对 lastQuotaResults 按 Deficit 降序排序后遍历，当前实现功能上可用

[MEDIUM] bigworld_npc_spawner.go:521 — OnPlayerLeave 调用时机依赖
  场景: 若 OnPlayerLeave(accountId) 在 playerMgr 移除该玩家之前调用
  影响: getOnlinePlayerPositions() 仍包含离开玩家的位置，findNearestPlayer 可能将 NPC 重新转交给正在离开的玩家（nearestPlayer == accountId），下一 Tick 再次触发 OnPlayerLeave 时重复处理
  建议: 在方法开头排除 accountId 对应的 positions，或在外部确保先从 PlayerMap 移除再调用此方法

[MEDIUM] bigworld_npc_spawner.go:353 — updatePlayerQuotas 均分逻辑与 WalkZone 配额系统并行
  说明: playerQuotas 按玩家均分 MaxCount，而 WalkZone 配额系统有独立的 TotalNpcBudget 和 zone 分配逻辑；两套系统并行存在，总上限约束逻辑分散，后期维护时易混淆
  影响: 当前逻辑可用，最坏情况是两套上限互相干扰，最终以 MaxCount 为硬上限

---

## 四、代码质量

无 CRITICAL 安全问题。

[HIGH] 见"三、边界情况"中两个 HIGH 条目（位置追踪缺失、zone 重叠处理）。

[MEDIUM] 见"三、边界情况"中三个 MEDIUM 条目。

---

## 五、总结

  CRITICAL: 0 个
  HIGH:     2 个（必须修复）
  MEDIUM:   3 个（建议修复）

  结论: 需修复后再提交

  重点关注:
  1. [HIGH] activeNpcInfo.Position 永久为生成快照，NPC 移动后 despawnNpc 递减错误 zone 的计数，配额系统长期运行后均衡失效（bigworld_npc_spawner.go:649）
  2. [HIGH] GetZoneForPos 未实现 plan 规定的多 zone 重叠处理（最近中心距离优先），影响边界区域配额归属的确定性（bigworld_walk_zone.go:229）

<!-- counts: critical=0 high=2 medium=3 -->
