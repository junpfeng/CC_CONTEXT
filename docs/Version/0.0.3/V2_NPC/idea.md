# 大世界 V2 NPC 与小镇 V2 NPC 差异对齐

## 做什么

将大世界 NPC 的模型加载、动画系统、FSM 状态机对齐到小镇 V2 NPC 的成熟实现，消除当前的功能裁剪导致的表现差距。当前大世界 NPC 共享小镇的核心资源（Prefab、动画组、BodyPartsMap），但在动画层、外观加载、状态机、交互能力上做了大幅裁剪，导致表现力不足。

## 涉及端

client

## 现状差异总览

### 模型与外观

| 维度 | 小镇 NPC | 大世界 NPC | 差距 |
|------|----------|-----------|------|
| Prefab | `NewNpcPrefab.prefab`（男）+ `NewNpcPrefab_Female.prefab`（女）| 仅 `NewNpcPrefab.prefab`（通用） | 无女性专用 Prefab |
| 外观系统 | `BodyPartsMap.ApplyPartList()` 直接在 Controller 中调用 | `BigWorldNpcAppearanceComp.LoadAppearanceAsync()` 封装，含三级 Fallback | 大世界更健壮 |
| 性别区分 | 按性别选择不同 Prefab | 不区分性别 | 无法正确显示女性 NPC 体型 |
| LOD | 支持 `SetOpenLod(true)` | 支持 | 一致 |

### 动画系统

| 维度 | 小镇 NPC | 大世界 NPC | 差距 |
|------|----------|-----------|------|
| Animancer 动画层 | 9 层（Base/RightArm/UpperBody/Arms/AdditiveBodyDefault/AdditiveBodyExtra/AdditiveUpperBody/AdditiveArms/Face） | 7 层（缺 RightArm + AdditiveBodyExtra） | 无法做右手持物动画和额外叠加动画 |
| AvatarMask | 4 个（Arms/UpperBody/RightArm/Face） | 2 个（Arms/UpperBody） | 缺少右手和面部 Mask |
| 默认动画组 | `NpcWpn00` | `NpcWpn00` | 一致 |
| 动画驱动方式 | FSM 状态机直接控制播放 | 自动速度驱动（`UpdateSpeedDrivenAnimation`） | 大世界更流畅但缺少精细控制 |
| Timeline 支持 | 有（`_replaceTimelines`） | 无 | 无法播放剧情/交互 Timeline |
| 转身动画 | 有（`TownNpcTurnState`） | 无 | NPC 转向时没有转身过渡 |
| 击中反应 | 有（HitData 处理） | 无 | NPC 被攻击无反馈 |
| 面部动画 | 有（Face 层 + Face AvatarMask） | 无 | NPC 没有面部表情 |
| 动画替换 | `_replaceTransitions` + `_replaceTimelines` | 仅 `_replaceTransitions` | 替换能力不完整 |

### FSM 状态机

| 维度 | 小镇 NPC | 大世界 NPC | 差距 |
|------|----------|-----------|------|
| 状态数 | 丰富（Idle/Walk/Run/Turn/Interact/Sit/...） | 3 态（Idle/Walk/Run） | 仅基础移动 |
| 服务端状态映射 | 完整映射所有 NpcState 枚举 | 已补全映射（bug fix），但全部映射到 3 个基础状态 | 缺少专用状态的动画表现 |
| 场景点行为 | 有（坐下、驻足观景、使用设备等） | 无 | NPC 到达巡逻节点只能 Idle |
| 社交行为 | 有（聊天、打招呼等） | 无 | NPC 之间无互动 |

### 组件对比

| 组件 | 小镇 NPC | 大世界 NPC | 说明 |
|------|----------|-----------|------|
| Controller | `TownNpcController` | `BigWorldNpcController` | 平级独立 |
| AnimationComp | `TownNpcAnimationComp`（完整） | `BigWorldNpcAnimationComp`（裁剪版） | 注释标注"按大世界需求裁剪" |
| FsmComp | `TownNpcFsmComp`（多状态） | `BigWorldNpcFsmComp`（3态） | 状态极度简化 |
| MoveComp | `TownNpcMoveComp` | `BigWorldNpcMoveComp` | 大世界有速度驱动 |
| TransformComp | 共享 `BigWorldNpcTransformComp` | 共享 | 一致 |
| AppearanceComp | 无独立组件，Controller 内直接处理 | `BigWorldNpcAppearanceComp` | 大世界封装更好 |
| EmotionComp | 有 | `BigWorldNpcEmotionComp`（基础） | 大世界仅基础情绪 |

## 优先级

| 优先级 | 内容 | 说明 |
|--------|------|------|
| P0 | 女性 Prefab 支持 | 按性别加载不同 Prefab，消除体型错误 |
| P0 | FSM 状态扩展（Sit/Interact） | 巡逻节点到达行为需要坐下等状态 |
| P0 | 转身动画（TurnState） | NPC 转向时表现不自然 |
| P1 | 补齐 RightArm + AdditiveBodyExtra 动画层 | 支持持物动画 |
| P1 | 面部动画（Face 层 + Mask） | NPC 有表情 |
| P1 | Timeline 支持 | 支持场景点剧情 |
| P2 | 击中反应 | NPC 被攻击有反馈 |
| P2 | 社交行为状态 | NPC 之间有互动 |

## 不做什么

- 不改变大世界的速度驱动动画系统（比小镇的 FSM 驱动更适合大量 NPC）
- 不引入小镇的完整交互系统（对话、交易等属于 engagement 维度，独立迭代）
- 不修改 `TownNpcController` 或小镇的任何组件
- 不合并两套 Controller 为一个（保持平级独立）

## 约束

- 大世界动画层扩展不能增加每帧 CPU 开销超过 0.5ms（NPC 数量 200+）
- 新增状态必须在服务端 NpcState 枚举已有值范围内，不新增协议
- 女性 Prefab 复用小镇已有的 `NewNpcPrefab_Female.prefab`，不另建
- 所有改动限制在 `BigWorldNpc*` 文件内，不影响小镇 NPC

## 参考

- 小镇动画组件：`freelifeclient/.../S1Town/Entity/NPC/Comp/TownNpcAnimationComp.cs`
- 小镇 FSM 组件：`freelifeclient/.../S1Town/Entity/NPC/Comp/TownNpcFsmComp.cs`
- 大世界动画组件：`freelifeclient/.../BigWorld/Entity/NPC/Comp/BigWorldNpcAnimationComp.cs`
- 大世界 FSM 组件：`freelifeclient/.../BigWorld/Entity/NPC/Comp/BigWorldNpcFsmComp.cs`
- 大世界外观组件：`freelifeclient/.../BigWorld/Entity/NPC/Comp/BigWorldNpcAppearanceComp.cs`
