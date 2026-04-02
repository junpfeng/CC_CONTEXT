═══════════════════════════════════════════════
  Feature Review 报告
  功能：V2_NPC
  版本：0.0.1
  任务：task-08（端到端集成联调）
  审查文件：6 个
  审查轮次：第 2 轮（验证 round-2 修复）
═══════════════════════════════════════════════

## 审查范围

### 客户端（3 个文件）
- `BigWorldNpcEmotionComp.cs` — 新增，情绪组件 P0 骨架
- `BigWorldNpcController.cs` — 修改，注册 EmotionComp
- `GameInitialize.cs` — 修改，注册 BigWorldNpcManager

### 服务端（3 个文件）
- `scene_impl.go` — 修改，CitySceneInfo 分支初始化 V2 NPC 管线 + BigWorldNpcSpawner
- `scene_type.go` — 修改，CitySceneInfo.GetNpcAIConfig 启用 EnableSensor/EnableDecision
- `traffic_light_system.go` — 修改，新增 GetJunctionState/GetTrafficLightSystem/GetJunctionTrafficLightState 便捷函数

---

## 前轮问题修复验证

| 问题 | 状态 | 说明 |
|------|------|------|
| [CRITICAL] BigWorldNpcEmotionComp.OnClear 访问修饰符 `public` → `protected` | ✅ 已修复 | 第 53 行现为 `protected override void OnClear()`，与基类 `Comp.OnClear()` (protected abstract) 一致 |
| [MEDIUM] intensity 参数未缓存 | ✅ 可接受 | P0 骨架仅日志输出 intensity，P1 迭代时补充字段，符合 plan 设计 |

---

## 一、合宪性审查

### 客户端

| 条款 | 状态 | 说明 |
|------|------|------|
| 编译：using | ✅ | using 完整，无歧义。Controller 有 Vector2/Vector3 alias |
| 编译：命名空间 | ✅ | `FL.Gameplay.Modules.BigWorld` 与目录层级对应 |
| 编译：API 存在性 | ✅ | `Comp.OnAdd`/`OnClear`、`AddComp<T>()`、`LogModule.BigWorldNpc`、`BigWorldNpcManager.CreateInstance()` 均确认存在 |
| 编译：类型歧义 | ✅ | EmotionComp 未引入 `FL.NetModule`，无 Vector3 歧义 |
| 编译：访问修饰符 | ✅ | OnClear 已修复为 `protected override`，与基类一致 |
| 1.1 YAGNI | ✅ | EmotionComp 为 plan 要求的 P1 骨架，无多余功能 |
| 1.2 框架优先 | ✅ | 复用 Comp 基类、ManagerCenter |
| 2.1-2.5 Manager 架构 | ✅ | BigWorldNpcManager 通过 `CreateInstance().Forget()` 注册 |
| 3.1-3.4 事件驱动 | ✅ | 无事件订阅，不涉及 |
| 4.1-4.3 异步编程 | ✅ | Controller 使用 UniTask + CancellationTokenSource，OnDispose/ResetForPool 正确 Cancel+Dispose |
| 5.1-5.5 网络通信 | ✅ | 不涉及新网络通信 |
| 6.1-6.3 内存性能 | ✅ | 无热路径分配 |
| 7.1 日志 | ✅ | MLog + `+` 拼接，无 `$""` 插值（grep 确认） |
| 7.2 错误处理 | ✅ | OnInit null 检查有错误日志 |
| 7.3 命名规范 | ✅ | `_currentEmotionId`/`CurrentEmotionId`/`UpdateEmotion` 符合规范 |
| 8.1-8.2 资源加载 | ✅ | 不涉及 |

### 服务端

| 条款 | 状态 | 说明 |
|------|------|------|
| 禁编辑区域 | ✅ | 未修改 orm/proto 生成代码 |
| 错误处理 | ✅ | `LoadData` 失败有 `log.Errorf`；spawner 禁用有 `log.Warningf`；管线未注册有 `log.Warningf` |
| 全局变量 | ✅ | 未新增全局变量 |
| Actor 独立性 | ✅ | 数据在场景协程内操作 |
| 消息传递 | ✅ | 不涉及跨 Actor 通信 |
| defer 释放锁 | ✅ | 不涉及锁 |
| safego | ✅ | 不涉及新 goroutine |
| 日志格式 | ✅ | 使用 `%v` 格式符，`[BigWorld]` 模块标签格式正确（grep 确认无 `%d`/`%s`） |

---

## 二、Plan 完整性

### 已实现
- [x] `scene_impl.go:185-221` — CitySceneInfo 分支初始化 V2 NPC 管线 + BigWorldNpcSpawner，符合 plan
- [x] `scene_type.go:109-116` — CitySceneInfo.GetNpcAIConfig 启用 EnableSensor + EnableDecision，符合 plan
- [x] `traffic_light_system.go:198-227` — 便捷查询函数（GetJunctionState/GetTrafficLightSystem/GetJunctionTrafficLightState），符合 plan
- [x] `BigWorldNpcEmotionComp.cs` — P0 骨架，缓存 emotionId，符合 plan
- [x] `BigWorldNpcController.cs:60` — EmotionComp 注册在正确位置（基础→驱动→表现顺序最后），符合 plan
- [x] `GameInitialize.cs:163` — BigWorldNpcManager.CreateInstance().Forget() 注册，符合 plan

### 遗漏
无。plan 中 task-08 要求的所有文件和功能均已实现。

### 偏差
- plan 提到 "SceneImplI 接口新增 GetTrafficManager/GetTrafficLightState 方法"，实际实现为 traffic_light_system.go 中的包级便捷函数（`GetTrafficLightSystem`/`GetJunctionTrafficLightState`），未修改接口。这是合理的简化——包级函数避免了侵入式接口修改，调用方式等价，且更符合 Go 惯例。

---

## 三、边界情况

无新增 CRITICAL/HIGH 边界问题。

[MEDIUM] `traffic_light_system.go:200-205` — GetJunctionState 对不存在的 junctionId 静默返回 Green
  场景: 配置错误导致路口 ID 不在 timers 映射中时，NPC 默认通行
  影响: 功能上合理（默认通行避免 NPC 卡死），但生产环境可能掩盖配置错误
  建议: 可选——对高频查询不存在的 junctionId 添加限流日志（P1 可补充）

---

## 四、代码质量

无 CRITICAL/HIGH 质量问题。

[MEDIUM] `scene_impl.go:195` — `InitLocomotionManagers(nil, nil, nil, bigWorldRoadNetQ)` 前三个参数传 nil
  说明: 大世界场景不需要 Town 的三个适配器（townRoadNetQ/townScenarioQ/townTrafficQ），传 nil 功能正确。但缺少注释说明为何传 nil，后续维护者可能困惑。
  建议: 可选——在上方加一行注释 `// 大世界仅需路网查询器，无 Town 适配器`

---

## 五、总结

  CRITICAL: 0 个
  HIGH:     0 个
  MEDIUM:   2 个（均为可选改进，不影响功能和编译）

  结论: 通过

  重点关注:
  1. 前轮 CRITICAL（OnClear 访问修饰符）已正确修复，编译无问题
  2. 整体实现质量高——服务端初始化链路有防重复注册哨兵，客户端组件生命周期管理完整
  3. 日志格式、命名规范、异步模式全部合规

<!-- counts: critical=0 high=0 medium=2 -->
