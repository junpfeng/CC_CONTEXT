═══════════════════════════════════════════════
  Feature Review 报告
  功能：V2_NPC
  版本：0.0.1
  任务：task-01（大世界NPC数据模型 + Pipeline注册 + 工厂扩展）
  审查文件：6 个
═══════════════════════════════════════════════

## 一、合宪性审查

### 服务端

| 条款 | 状态 | 说明 |
|------|------|------|
| 禁编辑区域 | ✅ | 未修改 orm/golang、orm/redis、orm/mongo、cfg_*.go 等自动生成区域 |
| 错误处理 | ✅ | Deserialize 校验数据长度并返回明确错误信息，createExt 不涉及错误路径 |
| 全局变量 | ✅ | 未新增全局变量，BigWorld 配置通过 init() 注册到已有 registry |
| Actor 独立性 | ✅ | BigWorldSceneNpcExt 作为组件数据挂载在 Entity 上，不跨 Actor 访问 |
| 消息传递 | ✅ | 无跨 Actor 通信代码 |
| defer 释放锁 | ✅ | 无锁操作 |
| safego | ✅ | 无新 goroutine |

### 客户端

本次 task-01 无客户端代码变更，跳过客户端合宪性审查。

## 二、Plan 完整性

### 已实现（task-01 范围内）

- [x] `bigworld_npc.go` — BigWorldSceneNpcExt 数据模型（AppearanceId、ScheduleId、SpawnConfig），含 Serialize/Deserialize
- [x] `scene_ext.go` — 新增 SceneNpcExtType_BigWorld = 5 枚举常量
- [x] `v2_pipeline_defaults.go` — 注册 BigWorld 管线（4 感知插件 + 4 正交维度），配置文件指向 bigworld_ 前缀
- [x] `scene_npc_mgr.go` — createExt() 工厂新增 BigWorld 分支，初始化 DefaultBigWorldSpawnConfig
- [x] `bigworld_npc_test.go` — 5 个单元测试（序列化往返、错误处理、默认配置、范围判断）
- [x] `v2_pipeline_test.go` — BigWorld 管线注册验证（感知插件数、维度数、名称、优先级）

### 遗漏

无。task-01 范围内的文件均已实现。

### 偏差

- `v2_pipeline_defaults.go:77` — plan 预期 BigWorldExtHandler（独立实现），实际使用 DefaultExtHandler 占位。develop-log 已记录此决策为合理延迟（后续 task 替换）。无功能影响，因为当前 task 不涉及运行时场景加载。

## 三、边界情况

[MEDIUM] bigworld_npc.go:50-56 — Deserialize 对超过 8 字节的数据静默忽略多余部分
  场景: 未来扩展 Serialize 增加字段后，旧版 Deserialize 读取新格式数据
  建议: 当前行为等同于前向兼容策略，可接受。若需严格校验，可加 `len(data) != 8` 的 warning 日志

## 四、代码质量

[MEDIUM] v2_pipeline_test.go:60,72 — 硬编码魔法数字 `5` 表示 BigWorld 场景类型
  影响: 如果 SceneNpcExtType_BigWorld 枚举值变更，测试不会编译报错，可能产生误导性通过/失败
  建议: 改为 `int32(cnpc.SceneNpcExtType_BigWorld)`，保持与生产代码的类型安全一致性

[MEDIUM] v2_pipeline_defaults.go:77 — DefaultExtHandler 占位无代码级 TODO 注释
  影响: 后续开发者可能不知道此处需要替换为专用 BigWorldExtHandler
  建议: 添加 `// TODO(task-XX): 替换为 BigWorldExtHandler` 注释

## 五、总结

  CRITICAL: 0 个
  HIGH:     0 个
  MEDIUM:   3 个（建议修复，可酌情跳过）

  结论: 通过

  重点关注:
  1. BigWorld 维度配置 JSON 文件（bigworld_engagement.json 等）尚未创建，后续 task 需补齐
  2. DefaultExtHandler 占位需在后续 task 中替换为专用实现
  3. 测试中使用常量替代魔法数字可提升可维护性

<!-- counts: critical=0 high=0 medium=3 -->
