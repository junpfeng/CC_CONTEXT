═══════════════════════════════════════════════
  Feature Review 报告
  功能：V2_NPC (task-03: BigWorld NPC 服务端 Spawner)
  版本：0.0.1
  审查文件：7 个（3 新增 + 4 修改）
═══════════════════════════════════════════════

## 一、合宪性审查

### 服务端

| 条款 | 状态 | 说明 |
|------|------|------|
| 禁编辑区域 | ✅ | 未修改 proto/、*_service.go 等自动生成文件 |
| 错误处理 | ✅ | 所有 error 显式处理，log.Errorf 带上下文（entityID/cfgId） |
| 无 `_ = err` | ✅ | 未发现被忽略的 error |
| 无新全局变量 | ✅ | 上轮 review 的 bwNavStates 全局 map 已迁移，本轮无新全局状态 |
| Actor 数据隔离 | ✅ | 所有操作在 ECS tick 循环内，无跨 Actor 数据访问 |
| 跨 Actor 通信用 Send() | ✅ | 无跨 Actor 通信 |
| defer 释放锁 | ✅ | 无锁使用（单协程 ECS 驱动） |
| safego.Go() | ✅ | 未新增 goroutine |
| 无硬编码密钥 | ✅ | 无敏感信息 |

### 客户端

本次 task-03 无客户端文件变更，跳过客户端合宪性审查。

## 二、Plan 完整性

### 已实现
- [x] bigworld_ext_handler.go — 扩展处理器，外观池（5 外观加权随机）、调度模板加载
- [x] bigworld_npc_spawner.go — AOI 动态生成/回收，配额分配，孤儿 NPC 处理
- [x] bigworld_npc_update.go — ECS System，驱动 Spawner（500ms）+ Pipeline（每帧）
- [x] ecs.go — 新增 SystemType_BigWorldNpcUpdate 枚举
- [x] scene_npc_mgr.go — 新增 bigWorldSpawner 字段及 Get/Set 方法
- [x] v2_pipeline_defaults.go — 注册 BigWorld 管线配置（4 维度 + 4 传感器）
- [x] map.go — 新增 GetAllPointPositions/GetPointCount

### 遗漏
无。task-03 计划的服务端文件全部实现。

### 偏差
- minPlayerDistSq 已从 10.0 修正为 100.0（上轮 review 修复），与 plan "10m 最小距离" 一致

## 三、边界情况

[CRITICAL] bigworld_npc_spawner.go:377-391 — **生成位置未写入实体**
  场景: spawnNpcAt 接收 pos 参数并在日志中打印，但构造 SceneNpcInfo 时仅设置 CfgId，未将 pos 传递给 AddNpc 或后续写入实体 Transform
  影响: 所有动态生成的 BigWorld NPC 出现在原点 (0,0,0) 而非路网节点位置，核心功能失效
  建议: 在 AddNpc 后获取实体 Transform 组件设置位置，或扩展 SceneNpcInfo 携带初始位置字段

[HIGH] bigworld_npc_spawner.go:185 — **MaxCount=0 时配额语义错误**
  场景: config.MaxCount=0 时，quotaPerPlayer = 0/onlineCount = 0，被 `if < 1` 强制设为 1
  影响: 无法通过 MaxCount=0 禁用 spawner，语义不符预期
  建议: 在 TickSpawn 入口增加 `if s.config.MaxCount <= 0 { return }` 前置检查

[HIGH] bigworld_npc_spawner.go:267-274 — **map 迭代中删除元素**
  场景: doDespawn 遍历 pendingDespawn 时直接 delete，Go 规范允许但可能跳过部分 entry
  影响: 部分到期 NPC 延迟一个 tick 才被回收，非致命但行为不确定
  建议: 收集待删除 key 到 slice，遍历后统一删除

## 四、代码质量

### [HIGH] 魔法数字未提取为常量

| 文件:行号 | 值 | 含义 |
|-----------|-----|------|
| bigworld_npc_spawner.go:120 | `5` | 安全生成点均匀采样数 |
| bigworld_npc_spawner.go:334 | `100.0` | 最小距离平方（10m²） |
| bigworld_npc_spawner.go:337 | `10` | 随机选点最大尝试次数 |
| bigworld_npc_spawner.go:360 | `50` | 海平面 Y 坐标阈值 |
| bigworld_npc_update.go:81 | `1.0/30.0` | 服务器固定帧步长 |

建议: 提取为包级命名常量或 SpawnerConfig 字段，提高可读性和可维护性。

### [MEDIUM] nextCfgId 无上界保护（bigworld_npc_spawner.go:400-403）

allocCfgId() 从 10000 持续递增，长时间运行后 int32 可能溢出为负数，与配置表 ID 冲突。建议添加回绕检查或使用 int64。

### [MEDIUM] rand.Rand 非线程安全（bigworld_npc_spawner.go:62, bigworld_ext_handler.go:38）

`*rand.Rand` 非线程安全。当前单协程 ECS 驱动下安全，但设计脆弱。建议添加注释标明单协程假设。

### [MEDIUM] 上轮 review 修复确认

上轮 review 发现的 3 个 HIGH（全局状态迁移、接口断言 nil 保护、OnNpcCreated 静默失败）和 3 个 MEDIUM 均已修复，本轮验证通过。

## 五、总结

  CRITICAL: 1 个（必须修复）
  HIGH:     3 个（强烈建议修复）
  MEDIUM:   3 个（建议修复，可酌情跳过）

  结论: 需修复后再提交

  重点关注:
  1. spawnNpcAt 生成位置未写入实体 — 核心功能失效，所有 NPC 出现在原点
  2. MaxCount=0 时无法禁用 spawner — 配置语义不符
  3. 多处魔法数字降低可读性 — 应提取为命名常量

<!-- counts: critical=1 high=3 medium=3 -->
