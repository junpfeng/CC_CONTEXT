═══════════════════════════════════════════════
  Feature Review 报告
  功能：V2_NPC
  版本：0.0.1
  任务：task-04（Server GM 命令 + JSON 配置文件）
  审查文件：6 个代码文件 + 3 个 JSON 配置文件
═══════════════════════════════════════════════

## 一、合宪性审查

### 服务端

| 条款 | 状态 | 说明 |
|------|------|------|
| 禁编辑区域 (orm/config/base/proto) | ✅ | 未修改任何禁编辑区域 |
| 错误处理：显式处理 | ✅ | 所有 error 均显式处理，无 `_ = err` |
| 错误处理：%w 包装 | ✅ | fmt.Errorf 均使用 %w 包装 |
| 错误处理：log.Errorf | ✅ | 错误日志均在产生处打印 |
| 全局变量 | ✅ | 无新增全局变量（仅 package-level 常量和编译期接口检查） |
| Actor 独立性 | ✅ | 所有数据在 Scene goroutine 内访问，rng 为实例级字段 |
| 消息传递 | ✅ | 不涉及跨 Actor 通信 |
| defer 释放锁 | ✅ | 无锁使用场景 |
| safego | ✅ | 无新 goroutine |
| time.Now 禁用 | ✅ | 未使用 time.Now()，时间通过 SetNowTime 外部注入 |

### 客户端

本 task 无客户端代码变更，不适用。

## 二、Plan 完整性

### 已实现
- [x] `gm/bigworld.go` — 5 个 GM 命令（spawn/clear/info/schedule/lod），符合 plan 设计
- [x] `bigworld_npc_config.go` — JSON 配置加载器（spawn + appearance），含完整校验
- [x] `bigworld_npc_config_test.go` — 15 个测试用例（10 spawn + 5 appearance），覆盖正常/边界/异常
- [x] `gm.go` — GM 注册集成（5 个命令正确注册于 switch 分支）
- [x] `bigworld_ext_handler.go` — 外观池加载 + 权重随机分配 + 日程模板加载
- [x] `bigworld_npc_spawner.go` — 配置集成 + AOI 动态生成/回收 + GM 公开方法
- [x] `bigworld_npc_spawn.json` — 生成配置（MaxCount=50, SpawnRadius=200, DespawnRadius=300）
- [x] `bigworld_npc_appearance.json` — 6 套外观权重配置
- [x] `V2_BigWorld_default.json` — 默认 24h patrol 日程

### 遗漏
无遗漏。Plan 要求的所有文件和功能均已实现。

### 偏差
- `bigworld_npc_appearance.json` 有 6 套外观（plan 要求 5-8 套），在合理范围内 ✅

## 三、边界情况

无 CRITICAL 或 HIGH 级别边界问题。

[MEDIUM] `bigworld_npc_spawner.go:234` - doSpawn 中 spawned 失败后 continue 但未回收 cfgId
  场景: spawnNpcAt 失败时，cfgId 已 alloc 但未加入 activeNpcs，不影响正确性（allocCfgId 跳过已占用的 ID）
  建议: 当前逻辑正确，cfgId 回绕时会自动跳过空位，无需修复

## 四、代码质量

### 日志格式违规

[HIGH] `bigworld_npc_config.go` 多处使用 `%d` 和 `%s` 格式符
  位置: 第 40/45/59/68/91/96/100/117/120 行
  规则: P1GoServer 日志规范要求统一使用 `%v`，禁止 `%d`/`%s`/`%.2f`/`%+v`
  影响: 违反日志格式规范，但不影响功能
  示例: `fmt.Errorf("max_count 必须大于 0, got %d", ...)` → 应改为 `%v`

[HIGH] `bigworld_ext_handler.go` 多处使用 `%d` 格式符
  位置: 第 65/114/115/123/124/139/152 行
  规则: 同上
  示例: `log.Infof("...加载 %d 个...", len(templates))` → 应改为 `%v`

[HIGH] `bigworld_npc_spawner.go` 多处使用 `%d` 格式符
  位置: 第 149/242/430 行
  规则: 同上

### 日志字段命名违规

[HIGH] `bigworld_ext_handler.go` NPC 相关日志未使用规范字段名
  位置: 第 114/115/123/124/139/152 行
  规则: 涉及 NPC 的日志必须使用 `npc_entity_id` + `npc_cfg_id` 成对字段名
  当前: 使用 `entityID=%d, cfgId=%d`
  应改为: `npc_entity_id=%v, npc_cfg_id=%v`

[HIGH] `bigworld_npc_spawner.go` NPC 相关日志未使用规范字段名
  位置: 第 242/422/430/450/565 行
  当前: 使用 `cfgId=%v` 或 `cfgId=%d`
  应改为: `npc_cfg_id=%v`

### 日志模块标签格式

[MEDIUM] `bigworld_ext_handler.go` 日志模块标签格式不统一
  位置: 全文件
  当前: `BigWorldExtHandler.methodName: ...`（类+方法名）
  规范: 应使用 `[BigWorldExtHandler]` 方括号格式
  影响: 日志 grep/过滤不一致

[MEDIUM] `bigworld_npc_spawner.go` 日志模块标签格式不统一
  位置: 全文件（除第 450 行已正确使用 `[BigWorldNpcSpawner]`）
  当前: 混合使用 `BigWorldNpcSpawner.methodName:` 和 `[BigWorldNpcSpawner]`
  建议: 统一使用 `[BigWorldNpcSpawner]` 方括号格式

### 代码质量

[MEDIUM] `bigworld_npc_spawner.go` 文件 607 行偏大
  建议: 可考虑将 GM 公开方法（536-607 行）拆分到独立文件，但当前可接受

## 五、总结

  CRITICAL: 0 个
  HIGH:     5 个（日志格式违规 ×3 + 日志字段命名违规 ×2，均为规范问题不影响功能）
  MEDIUM:   3 个（日志标签格式 ×2 + 文件偏大 ×1）

  结论: 需修复后再提交

  重点关注:
  1. 日志格式符全部改为 `%v`（3 个文件，约 20 处）
  2. NPC 相关日志字段名改为 `npc_entity_id`/`npc_cfg_id` 规范命名
  3. 日志模块标签统一为 `[ClassName]` 方括号格式

  整体评价: 代码逻辑质量优秀，架构设计合理，错误处理完善，测试覆盖充分。
  问题集中在日志格式规范层面，属于机械性修复，不涉及逻辑变更。

<!-- counts: critical=0 high=5 medium=3 -->
