# Plan Review 报告

## 📊 总评

| 维度 | 评级 | 问题数 |
|------|------|--------|
| 需求覆盖度 | ⚠️ 有遗漏 | 2 |
| 边界条件 | ⚠️ 有遗漏 | 3 |
| 协议设计 | ✅ 完善 | 1 |
| 服务端设计 | ⚠️ 有遗漏 | 2 |
| 客户端设计 | ⚠️ 有遗漏 | 2 |
| 安全防滥用 | ✅ 完善 | 0 |
| 可测试性 | ⚠️ 有遗漏 | 2 |

**总体评价**：Plan 整体架构设计扎实，正交 Pipeline 解耦清晰，协议零新增策略优秀。主要风险集中在 6 个未决开放问题影响 P0 范围界定、客户端 HiZCulling 缺少实现细节、以及断线重连场景下大批量 NPC 全量同步的消息体积。

## 🔴 必须修复（Critical）

### C1: 6 个开放问题未决，P0 范围存在歧义
- **位置**：feature.json Open Questions 部分
- **问题**：需求文档列出 6 个待确认项（最大 NPC 数量、载具支持、特殊职业、日程复杂度、动物系统交互、对话功能），Plan 虽然做出了 P0 假设（如"P0 不含载具"），但这些假设未在 feature.json 中确认闭环。如果假设与实际需求不一致，实现后需要大规模返工。
- **影响**：开发完成后可能发现范围假设错误，导致返工
- **建议**：在 plan.json 头部增加 `scope_decisions` 节，逐一列出每个开放问题的决定及理由。例如：`"max_npc": {"decision": "server=50, client=20", "reason": "手机性能预算", "revisit": "P1"}`。将此作为实现的前置条件，如果无法确认则标注为阻塞项。

### C2: 客户端 HiZCulling 在验收标准中要求但 Plan 无实现设计
- **位置**：feature.json 验收标准 / plan.json 客户端设计
- **问题**：验收标准明确要求"HiZCulling culls out-of-view NPCs for animation/rendering"，但 Plan 中客户端设计只提到了基于距离的 LOD（<100m/100-200m/>200m），未设计 HiZCulling 遮挡剔除的具体实现——如何获取遮挡信息、如何与 LOD 层级联动、BigWorldNpcController 如何响应剔除状态。
- **影响**：验收时无法通过 HiZCulling 相关指标，或者实现时临时加入导致架构不一致
- **建议**：在客户端设计中增加 HiZCulling 小节：(1) 说明是复用现有 HiZCulling 系统还是新建；(2) 定义 BigWorldNpcController 的 `OnBecameVisible/OnBecameInvisible` 回调行为；(3) 明确与距离 LOD 的优先级关系（如：遮挡剔除优先于距离 LOD，被遮挡时暂停所有更新）。

## 🟡 建议修复（Important）

### I1: 断线重连全量同步消息体积未评估
- **位置**：plan.json 同步设计 / `is_all=true` 全量同步
- **问题**：Plan 提到断线重连时 `is_all=true` 绕过帧限流（15 NPC/frame）做全量同步，但未评估 50 个 NPC 的全量数据包大小。每个 NPC 包含位置、朝向、状态、外观、行为维度等字段，50 个 NPC 的单次消息可能超过手机端合理的单包上限。
- **建议**：(1) 估算单个 NPC 的 NpcV2Info 序列化大小；(2) 如果 50×单个 > 8KB，考虑分批全量同步（如每帧 10 个，5 帧完成）；(3) 在 plan 中记录预估值和分批策略。

### I2: A* 寻路 LRU 缓存缺少失效策略
- **位置**：plan.json 服务端 NavigationHandler
- **问题**：Plan 提到 A* 寻路使用 LRU 缓存（max 10 frame continuation），但未说明缓存失效条件。大世界路网是静态的所以路径本身不会变，但 NPC 起点是动态的——如果 NPC 被推离路径（碰撞/传送），缓存的路径就失效了。
- **建议**：明确 LRU 缓存的 key 设计（起点+终点 hash？）和失效条件（NPC 偏离路径超过阈值时清除缓存并重新寻路）。

### I3: 客户端对象池耗尽时的降级策略未定义
- **位置**：plan.json 客户端 BigWorldNpcManager
- **问题**：Plan 设定客户端最多 20 个 NPC 实例（对象池预热 20 个），但 AOI 范围内可能有超过 20 个服务端 NPC 需要表现。Plan 未说明当池子满时新进入 AOI 的 NPC 如何处理。
- **建议**：增加降级策略：(1) 按距离排序，最远的 NPC 回收给最近的新 NPC；(2) 或简单丢弃超出的 NPC 直到有空闲池对象；(3) 定义优先级——与玩家交互中的 NPC 不被回收。

### I4: NpcState 新增字段需同步 Snapshot + FieldAccessor
- **位置**：plan.json 服务端数据结构
- **问题**：根据项目经验（已有规则），NpcState 新增任何字段都必须同步更新 Snapshot 和 FieldAccessor，否则帧同步不推送。Plan 中 BigWorld NPC 可能引入新的状态字段（如 schedule 阶段、外观 ID），但未在数据结构设计中提及 Snapshot/FieldAccessor 的同步。
- **建议**：在服务端数据结构章节明确列出所有新增/复用的 NpcState 字段，并标注哪些需要新增 FieldAccessor。

### I5: 瞬移/传送场景下 AOI 快速变化未处理
- **位置**：plan.json BigWorldNpcSpawner
- **问题**：Spawner 设计了 200m 生成 / 300m 回收的滞后机制（hysteresis），对正常移动有效。但玩家传送时会瞬间改变位置，可能导致：(1) 旧位置的 NPC 全部需要回收 + 新位置的 NPC 全部需要生成，瞬间负载极大；(2) 3 秒延迟创建在传送场景下体验差（玩家到达后 3 秒才看到 NPC）。
- **建议**：增加传送专用逻辑：检测位移 > 阈值（如 > 500m）时，跳过渐进式回收/创建，直接全量重建 AOI 内 NPC（类似断线重连逻辑）。

## 🟢 可选优化（Nice to have）

### N1: 增加 BigWorld NPC 专用 GM 调试命令
- **建议**：设计 2-3 个 GM 命令用于开发调试：(1) `/ke* gm bwnpc spawn <count>` 强制生成指定数量 NPC；(2) `/ke* gm bwnpc info` 输出当前 AOI 内 NPC 数量和状态分布；(3) `/ke* gm bwnpc pipeline <npc_id>` 输出指定 NPC 的 Pipeline 各维度当前决策。

### N2: 服务端 Pipeline Tick 性能监控指标
- **建议**：在 BigWorldSceneNpcExt 中增加 Pipeline 单次 Tick 耗时的 P99 监控。验收标准要求 <2ms/NPC，需要有数据支撑。建议在 Plan 中预留监控埋点位置。

### N3: 客户端动画 Clip Loop 配置校验
- **建议**：根据项目经验（feedback_anim_clip_loop_check），Animancer 播放 clip 时必须检查 isLooping（FBX 可能未勾选 Loop）。建议在 AnimationComp 初始化时增加 Idle/Walk/Run clip 的 loop 属性校验，避免动画播放一次后停止。

## 📝 遗漏场景清单

1. **玩家传送后 NPC 重建** — 需要在 BigWorldNpcSpawner 中补充传送检测和快速重建逻辑（已在 I5 详述）
2. **NPC 在路口处的避让优先级** — NavigationHandler 提到车辆/交通避让，但未说明 NPC 之间在狭窄路口的避让规则（谁让谁？死锁检测？）
3. **服务器热重启时 NPC 状态恢复** — Plan 提到内存状态，但未说明服务器重启后 BigWorld NPC 的恢复策略（是否需要持久化？还是全部重新生成？）
4. **LOD 层级切换的平滑过渡** — 客户端 LOD 切换（如从 >200m paused 到 <100m full）时，NPC 可能突然"跳跃"到新位置，需要补间处理

## ✅ 做得好的地方

1. **零协议新增策略**：复用 NpcDataUpdate/NpcV2Info/TownNpcData，避免了协议膨胀和跨端同步成本，是一个非常务实的设计决策。这也意味着 BigWorld 和 Town 的 NPC 可以共用客户端解析逻辑，降低维护成本。

2. **AOI 滞后机制（Hysteresis）**：200m 生成 / 300m 回收的非对称阈值设计有效避免了玩家在边界来回移动时 NPC 频繁创建销毁的"乒乓问题"，这是一个有经验的设计选择。

3. **正交 Pipeline 架构**：engagement→expression→locomotion→navigation 四维度独立决策，各维度互不干扰，扩展性好。P0 只实现 engagement=idle 就能跑通完整链路，后续添加行为只需扩展对应维度的 Handler，不影响其他维度。

<!-- counts: critical=2 important=5 nice=3 -->
