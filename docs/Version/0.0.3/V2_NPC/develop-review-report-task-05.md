═══════════════════════════════════════════════
  Feature Review 报告
  功能：V2_NPC
  版本：0.0.3
  Task：task-05（REQ-005 Face 层 + 面部动画 + EmotionComp 联动）
  审查文件：2 个
═══════════════════════════════════════════════

## 一、合宪性审查

### 客户端

| 条款 | 状态 | 说明 |
|------|------|------|
| 编译：using 完整性 | ✅ | 两个文件 using 均完整，Vector2/Vector3 alias 已消歧义 |
| 编译：命名空间 | ✅ | namespace FL.Gameplay.Modules.BigWorld，与目录层级对应 |
| 编译：API 存在性 | ✅ | AnimancerLayer.Play(clip, fadeDuration)、LoaderManager.LoadAssetAsync 均真实存在 |
| 编译：枚举存在性 | ✅ | SingleAssetType.Face=5、SingleAssetType.RightArm=4、AnimancerLayers.Face=8、AnimationStatus.NpcWpn00=1000 均存在 |
| 编译：类型歧义 | ✅ | using Vector2/Vector3 = UnityEngine.Vector2/Vector3 已正确添加 |
| 1.2 框架优先 | ✅ | 使用 LoaderManager.LoadAssetAsync 而非直接 Resources.Load |
| 3.3 订阅配对 | ✅ | 无 EventManager 订阅，不适用 |
| 4.1 UniTask 使用 | ⚠️ | BigWorldNpcAnimationComp.cs 头部 using Cysharp.Threading.Tasks，但文件内无任何 UniTask API 调用（见中等问题） |
| 6.1 热路径零分配 | ✅ | UpdateSpeedDrivenAnimation 有 Threshold 守卫，仅变化时调用 SetSpeed；_faceClips 使用字典缓存 |
| 7.1 日志规范 | ✅ | 全部使用 MLog，用 + 拼接，无 $"" 插值 |
| 7.2 错误处理 | ✅ | 异步回调中 Owner==null 守卫，clip==null 静默跳过并打 Warning |
| 7.3 命名规范 | ✅ | 私有字段 _camelCase，常量 PascalCase，方法 PascalCase |
| 8.1 资源加载 | ✅ | 通过 LoaderManager.LoadAssetAsync 异步加载，无同步加载 |

### 服务端

本 task 为纯客户端改动，无服务端文件变更，服务端合宪性审查不适用。

---

## 二、Plan 完整性

### 已实现
- [x] BigWorldNpcAnimationComp.cs — `_faceMask`、`_faceClips`、`_isFaceClipsReady`、`_pendingEmotion` 字段
- [x] BigWorldNpcAnimationComp.cs — `LoadFaceClips()` 预加载 Angry/Happy/Sad/Idle 四个 Clip，失败静默跳过
- [x] BigWorldNpcAnimationComp.cs — `PlayFaceAnim(EmotionType)` 接口，None 映射到 Idle，Clip 缺失静默跳过
- [x] BigWorldNpcAnimationComp.cs — `_pendingEmotion` 机制，加载完成后补调
- [x] BigWorldNpcAnimationComp.cs — Face 层 Weight=1，FaceAvatarMask 异步绑定
- [x] BigWorldNpcAnimationComp.cs — `IsFaceClipsReady` 属性暴露
- [x] BigWorldNpcEmotionComp.cs — `EmotionType` 枚举（None/Angry/Happy/Sad/Idle）
- [x] BigWorldNpcEmotionComp.cs — `OnAdd()` 获取 AnimationComp 引用
- [x] BigWorldNpcEmotionComp.cs — `UpdateEmotion(emotionId, intensity)` 接口
- [x] BigWorldNpcEmotionComp.cs — `ResetEmotion()` 恢复 FaceIdle
- [x] BigWorldNpcEmotionComp.cs — `OnClear()` 清理引用
- [x] BigWorldNpcController.cs — EmotionComp 注册在 AnimationComp 之后（顺序正确）

### 遗漏

- [ ] **UpdateEmotion 无调用点**：EmotionComp.UpdateEmotion 在整个代码库中没有任何调用者。Plan 要求"接收服务端情绪数据，驱动 Face 层表情动画"，但缺少将服务端 NPC 状态同步（BigWorld NPC 帧同步处理器）连接到 EmotionComp.UpdateEmotion 的调用代码。
- [ ] **Face 层初始 Clip 未播放**：NPC 生成后 Face 层 Weight=1 但无 Clip，直到外部调用 UpdateEmotion 才有动画。若 UpdateEmotion 从未被调用，FaceAvatarMask 覆盖区域始终无动画驱动（可能呈现 T-Pose 或无叠加）。

### 偏差

无其他重大偏差。

---

## 三、边界情况

[HIGH] BigWorldNpcAnimationComp.cs:205-237 — LoadFaceClips 存在 stale callback 竞态条件
  场景: NPC 对象入池（OnClear 重置 _faceClipsLoadedCount=0）后立即被另一个实体复用（OnAdd 触发新一轮 LoadFaceClips），上一轮尚未触发的 async 回调在新 Owner 非 null 的情况下火发（因为池对象被重用，Owner 指向新 controller），导致新旧计数器交叉递增，_isFaceClipsReady 可能被过早置为 true，旧轮次 Clip 写入新实例的 _faceClips 字典
  影响: Face 动画字典数据污染，可能在新实例上播放错误情绪 Clip 或 count 提前到达 total 而遗漏新 Clip 加载
  触发概率: 低（需极短时间内同一池对象被两次复用），但对象池场景下并非不可能

[HIGH] BigWorldNpcEmotionComp.cs:48 — UpdateEmotion 整个代码库无调用点
  场景: 正常游戏运行中，任何服务端情绪推送都不会触发 EmotionComp.UpdateEmotion，Face 层无有效动画驱动
  影响: REQ-005 核心功能（情绪驱动面部表情）在实际运行中完全失效；Face 层 Weight=1 但无 Clip，face mask 区域可能持续呈现空状态
  建议: 在 BigWorld NPC 状态同步处理路径（帧同步 handler 或 NpcState 变更回调）中调用 EmotionComp.UpdateEmotion

---

## 四、代码质量

[MEDIUM] BigWorldNpcAnimationComp.cs:3 — `using Cysharp.Threading.Tasks;` 导入未使用
  文件内无任何 UniTask API 调用（LoadAssetAsync 使用 Action callback，非 UniTask）。若父类 AnimationComp 未使用 UniTask，该 using 属于冗余导入
  建议: 确认父类是否需要，若不需要则移除

[MEDIUM] BigWorldNpcAnimationComp.cs:493-497 vs 499-521 — OnRemove 与 OnClear 重复清理
  OnRemove() 清理 _replaceTransitions 和 _faceClips，OnClear() 中同样清理了这两个字段（外加其余全部状态）。若框架保证 OnClear 必然在 OnRemove 之后调用，OnRemove 中的 Clear 是冗余的。若两个方法在不同生命周期路径下调用，则应明确各自边界
  建议: 统一清理逻辑到 OnClear，OnRemove 仅处理非池化清理场景（若有）

[MEDIUM] BigWorldNpcEmotionComp.cs:9-16 — EmotionType 枚举定义在 EmotionComp 中但被 AnimationComp 引用，形成兄弟组件间的单向依赖
  BigWorldNpcAnimationComp 依赖 BigWorldNpcEmotionComp 中定义的 EmotionType，语义上 EmotionType 属于动画系统公共类型，不应归属于 Comp 组件类文件
  建议: 将 EmotionType 移至独立文件（如 BigWorldNpcTypes.cs）或 AnimationComp 所在命名空间公共区域，解除 AnimationComp → EmotionComp 的隐式依赖

---

## 五、总结

  CRITICAL: 0 个
  HIGH:     2 个（强烈建议修复）
  MEDIUM:   3 个（建议修复，可酌情跳过）

  结论: 需修复后再提交

  重点关注:
  1. [HIGH] UpdateEmotion 无调用点 — 整个情绪联动功能在运行时不会触发，REQ-005 核心诉求未完成
  2. [HIGH] LoadFaceClips stale callback 竞态 — 对象池快速复用场景下可能污染 Face Clip 字典
  3. [MEDIUM] EmotionType 枚举跨组件依赖 — 兄弟 Comp 间隐式耦合，建议迁移到公共类型文件

<!-- counts: critical=0 high=2 medium=3 -->
