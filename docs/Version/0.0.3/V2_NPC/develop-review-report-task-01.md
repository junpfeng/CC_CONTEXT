═══════════════════════════════════════════════
  Feature Review 报告
  功能：V2_NPC / task-01 REQ-001 性别Prefab选择
  版本：0.0.3
  审查文件：2 个
═══════════════════════════════════════════════

## 一、合宪性审查

### 客户端（BigWorldNpcController.cs + BigWorldNpcManager.cs）

| 条款 | 状态 | 说明 |
|------|------|------|
| 编译：using 完整性 | ✅ | 两文件均有 Vector3 alias，无 FL.NetModule 引入无歧义风险 |
| 编译：命名空间 | ✅ | `FL.Gameplay.Modules.BigWorld` 与目录层级一致 |
| 编译：API 存在性 | ✅ | 新增 API（常量+静态方法）均自包含，ObjectPoolUtility 调用签名未变 |
| 编译：类型歧义 | ✅ | 已添加 Vector2/Vector3 alias，无歧义 |
| 1.1 YAGNI | ✅ | 仅实现 plan 要求的性别选择逻辑，无多余功能 |
| 1.2 框架优先 | ✅ | 复用 ObjectPoolUtility、BaseManager、AddComp 等已有基础设施 |
| 2.1 Manager 架构 | ✅ | BigWorldNpcManager 继承 BaseManager\<T\>，生命周期合规 |
| 3.x 事件驱动 | ✅ | EventManager.SendEvent 正确调用，无新增订阅 |
| 4.1 UniTask | ✅ | 全程 UniTask，无 System.Thread.Tasks 或协程 |
| 4.3 CancellationToken | ✅ | OnInit 创建 _cts，OnDispose/ResetForPool 均 Cancel+Dispose |
| 5.x 网络通信 | ✅ | 本 task 无网络变动 |
| 6.1 热路径零分配 | ✅ | OnUpdate 使用 _tempTickKeys 等预分配列表，无新增热路径 GC |
| 7.1 日志规范 | ✅ | 全部使用 MLog，使用 `+` 拼接，无 `$""` 插值，无 Debug.Log |
| 7.2 错误处理 | ✅ | AcquireFromPool/SpawnNpc/PrewarmPoolAsync 均有 try-catch 日志 |
| 7.3 命名规范 | ✅ | public const 用 UPPER_SNAKE_CASE，private 用 _camelCase |
| 8.x 资源加载 | ✅ | 通过 ObjectPoolUtility 异步加载，无同步加载 |

### 服务端
本 task 无 Go 文件变动，跳过服务端审查。

---

## 二、Plan 完整性

### 已实现
- [x] `BigWorldNpcController.cs` — 新增 NPC_PREFAB_MALE/FEMALE 常量，SelectPrefabByGender 方法，Female(2)→女性路径，其他→男性兜底
- [x] `BigWorldNpcManager.cs` — PrewarmPoolAsync 同时预热男女池，AcquireFromPool 增加 prefabPath 参数，SpawnNpc 读取 Gender 并调用 SelectPrefabByGender

### 遗漏
- 无（BigWorldNpcAppearanceComp.cs 按任务说明确认不需要修改）

### 偏差
- `BigWorldNpcController.cs:163` — plan 要求 `SelectPrefabByGender` 为**私有方法**，实际实现为 `public static`。原因：实例化逻辑在 BigWorldNpcManager 而非 Controller 自身，设计上需要跨类访问。已在 develop-log 中记录。技术上合理，但与 plan 规格不一致（MEDIUM）

---

## 三、边界情况

[HIGH] BigWorldNpcController.cs:165 — SelectPrefabByGender 使用魔法数字 `2` 判断女性
  场景: Gender 枚举定义重新排列或版本迭代后 Female 值发生变化
  影响: 所有女性 NPC 静默显示男性 Prefab，编译不报错难以察觉
  建议: 将 `if (gender == 2)` 改为 `if (gender == (uint)ConfigEnum.Gender.Female)`；若 ConfigEnum 命名空间不可直接引用，应在类内提取为具名常量 `private const uint GenderFemale = 2`

[MEDIUM] BigWorldNpcManager.cs:250 — _pendingDespawnList.Contains(kvp.Key) 为 O(n) 线性查找
  场景: SyncWithDataManager 每帧调用，当 NPC 数量接近上限（200+）时，内层 foreach 含 Contains 操作复杂度为 O(n²)
  影响: 性能轻微下降，目前 200 NPC 场景可接受，但接近上限时每帧约 40000 次比较
  建议: _pendingDespawnList 改为 HashSet\<ulong\>（Contains 降为 O(1)），注意 Remove 操作同步调整

---

## 四、代码质量

[MEDIUM] BigWorldNpcController.cs:163 — plan 设计偏差（public static vs private）
  plan 原意是封装性别选择逻辑为 Controller 私有实现细节，外部无需感知；
  实际因调用方在 Manager 层而改为 public static，耦合了 Manager 对 Controller 内部路径常量的知识。
  影响: Controller 公开了两个 Prefab 路径常量 + 一个选择方法，形成对外 API 契约，未来改路径时需留意所有调用方。
  建议: 可接受现有设计（已有注释说明），也可考虑将路径常量移至 BigWorldNpcManager（调用方自己持有），彻底解耦。本次不强制修改。

---

## 五、总结

  CRITICAL: 0 个（必须修复）
  HIGH:     1 个（强烈建议修复）
  MEDIUM:   2 个（建议修复，可酌情跳过）

  结论: 需修复后再提交

  重点关注:
  1. [HIGH] SelectPrefabByGender 中的魔法数字 `2` 需替换为枚举引用或具名常量，防止枚举值变化导致的静默错误

<!-- counts: critical=0 high=1 medium=2 -->
