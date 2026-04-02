# Plan Review 报告

## 总评

| 维度 | 评级 | 问题数 |
|------|------|--------|
| 需求覆盖度 | ⚠️ 有遗漏 | 1 |
| 边界条件 | ✅ 完善 | 0 |
| 协议设计 | ✅ 完善 | 0 |
| 服务端设计 | ✅ 完善 | 1 |
| 客户端设计 | ⚠️ 有遗漏 | 1 |
| 安全防滥用 | ✅ 完善 | 0 |
| 可测试性 | ✅ 完善 | 1 |

**总体评价**：经过 7 轮迭代，plan 质量较高，无 Critical 问题。核心逻辑（召唤搜索、跟随切换、短路优化、并发安全、CancellationToken、玩家状态校验）设计完善。剩余 2 个 Important 问题涉及客户端宪法合规和需求验收条件覆盖，3 个 Nice-to-have 为性能和可观测性优化建议。

## 🔴 必须修复（Critical）

无。

## 🟡 建议修复（Important）

> 不修复可能导致边界场景 bug 或体验问题

### I1: 客户端协议响应未明确要求 Result.IsOk() 检查

- **位置**：plan.json `client_design.implementation_notes` 第4条（协议收发）
- **问题**：plan 描述协议收发时写到"使用 async/await UniTask 模式获取 Result\<SummonDogRes\>"，但未明确要求检查 `Result.IsOk()` 后再读取 `Res.Code`。freelifeclient 宪法第五条要求"网络请求 Result 是否都检查了 IsOk()"。若网络层返回失败（如超时、断连），直接访问 Res 字段会空引用。
- **建议**：在协议收发描述中补充："收到 Result 后先检查 IsOk()，失败时走 error_handling 中的超时/断线逻辑（按钮恢复可点击 + 超时提示），成功时再读取 Res.Code 和 Res.AnimalId"。

### I2: 面板输入模式未指定，REQ-001 验收条件可能不满足

- **位置**：plan.json `client_design.ui_panels`
- **问题**：REQ-001 验收条件明确要求"面板打开/关闭时不影响角色移动和其他操作"。但 plan 未指定面板的输入模式（是否为模态/非模态窗口）。如果 Panel 默认捕获输入焦点或添加全屏遮罩层，打开面板后玩家无法移动角色，不满足验收条件。
- **建议**：在 ui_panels 描述中补充："面板设置为非模态（non-blocking），不拦截游戏输入，玩家可在面板打开时继续移动和操作。Prefab 中面板背景不添加全屏遮罩层。"

## 🟢 可选优化（Nice to have）

> 提升代码质量、可维护性或用户体验

### N1: 两次全量 NPC 遍历可合并为一次

- **建议**：当前主流程中步骤4（搜索最近狗）和步骤6（查找旧跟随狗 FollowTargetID==playerEntityId）各做一次全量遍历。可在步骤4 的遍历中同时记录当前玩家已跟随的旧狗，省去步骤6 的第二次遍历。NPC 数量少（<500）时差异不大，但合并后逻辑更清晰、代码更紧凑。

### N2: 服务端缺少召唤操作日志

- **建议**：plan 的 server_design 未提及 handler 中的日志输出。建议在召唤成功和失败时各打一条 Info 级别日志，包含 playerEntityId、选中狗的 entityId（或无狗原因）、搜索范围内候选数量，便于线上排查"玩家说召唤不到狗"类问题。宪法要求"错误日志必须在产生错误的地方打印"。

### N3: 搜索半径硬编码与 REQ-005 "可配置" 要求不完全匹配

- **建议**：REQ-005 写到"搜索半径可通过服务器配置调整"，plan 使用 `const summonDogMaxDistSq = 2500` 硬编码。当前作为代码常量可接受（YAGNI），但建议注明"后续如需运行时调整，迁移到配置表（如 AnimalConfig 表新增 SummonSearchRange 字段）"。

## 遗漏场景清单

1. **跨场景切换时的跟随状态** — plan 依赖 animal_follow 系统自动处理，但未显式说明玩家切换场景时已召唤的狗如何处理（是否随场景卸载自动解除）。建议在 `flows.exception` 中补充一句说明，即使只是"由 animal_follow 系统自动处理，无需额外逻辑"也能消除实现者疑问。

## 做得好的地方

1. **短路优化设计精巧**：步骤5 判断最近狗已被自己跟随时直接返回成功，避免无意义的状态翻转和两次 SetSync()，体现了对性能和正确性的双重考量。
2. **YAGNI 原则贯彻彻底**：冷却错误码复用 14006 而非新增、断线重连不做客户端恢复、不缓存跟随状态——每个简化决策都有合理的理由记录，避免过度设计。
3. **并发安全分析到位**：明确说明 scene_server 单 goroutine 串行执行的天然安全性，避免了不必要的锁设计，同时在 implementation_notes 中为后续扩展留了优化路径（playerEntityId→dogEntityId 缓存映射）。

<!-- counts: critical=0 important=2 nice=3 -->
