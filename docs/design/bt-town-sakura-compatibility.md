# 需求文档：行为树系统支持小镇和樱花校园 NPC

**文档版本**: v1.0
**创建日期**: 2026-02-25
**需求类型**: 重构/优化

---

## 1. 功能概述

### 1.1 当前问题

行为树系统当前存在硬编码小镇 NPC 特定逻辑的问题，导致樱花校园 NPC 无法复用相同的行为树节点。主要问题包括：

1. **组件访问硬编码**：节点直接访问 `TownNpcComp` 等小镇特定组件
2. **资源访问硬编码**：节点直接依赖 `TownNpcMgr` 等小镇特定资源
3. **配置访问硬编码**：节点调用 `GetCfgTownNpcById()` 等小镇配置查询

### 1.2 重构目标

**让行为树系统能够同时支持小镇和樱花校园两种场景的 NPC**，使共享的行为树（`daily_schedule.json`, `dialog.json`, `init.json` 等）能够被两种场景的 NPC 使用。

**非目标**：
- ❌ 不是完全通用化所有行为节点
- ❌ 不是支持所有可能的场景类型
- ✅ 聚焦于小镇和樱花校园两种已有场景的兼容性

### 1.3 范围界定

**包含范围**：
- 共享的行为树：`daily_schedule.json`, `dialog.json`, `init.json`, `return_to_schedule.json`
- 共享的行为节点：IdleBehavior, MoveBehavior, DialogBehavior 等基础节点
- 共享的工具节点：SetInitialPositionNode, WaitNode 等

**排除范围**：
- 场景特定的行为树：`meeting.json`（仅小镇）, `sakura_npc_control.json`（仅樱校）
- 场景特定的行为节点：PursuitBehavior（仅小镇警察）, PlayerControlBehavior（仅樱校）

---

## 2. 验收标准

### 2.1 功能验收

- [ ] **小镇 NPC 功能不受影响**：Dan, Customer, Dealer, Blackman 的所有行为保持原有表现
- [ ] **樱花校园 NPC 可使用共享行为树**：能够成功加载并执行 `daily_schedule.json`, `dialog.json`, `init.json`
- [ ] **初始化行为正确**：两种场景的 NPC 都能正确初始化位置（从各自的配置和存储中读取）
- [ ] **日常调度行为正确**：两种场景的 NPC 都能根据 `feature_schedule` 切换空闲/移动状态
- [ ] **对话行为正确**：两种场景的 NPC 都能响应 `feature_dialog_req` 进入和退出对话状态

### 2.2 代码验收

- [ ] **消除小镇特定组件硬编码**：共享节点不直接访问 `TownNpcComp`
- [ ] **消除小镇特定资源硬编码**：共享节点不直接依赖 `TownNpcMgr`
- [ ] **消除小镇特定配置硬编码**：共享节点不调用 `GetCfgTownNpcById()`
- [ ] **使用能力接口抽象**：共享节点通过能力接口访问场景特定功能
- [ ] **保持向后兼容**：重构后的代码不影响现有测试通过

### 2.3 测试验收

- [ ] **单元测试通过**：所有现有单元测试通过
- [ ] **集成测试通过**：小镇 NPC 的集成测试通过
- [ ] **新增樱校测试**：新增樱花校园 NPC 使用共享行为树的测试用例
- [ ] **回归测试通过**：确保小镇 NPC 的行为表现与重构前完全一致

---

## 3. Brain 配置分析

### 3.1 共享的 Plan

| Plan 名称 | 小镇 NPC | 樱校 NPC | 对应行为树 |
|----------|---------|---------|-----------|
| `init` | ✅ | ✅ | `init.json` |
| `daily_schedule` | ✅ | ✅ | `daily_schedule.json` |
| `dialog` | ✅ | ✅ | `dialog.json` |

### 3.2 场景特定的 Plan

| Plan 名称 | 小镇 NPC | 樱校 NPC | 对应行为树 |
|----------|---------|---------|-----------|
| `meeting` | ✅ | ❌ | `meeting.json` |
| `pursuit` | ✅ | ❌ | （内嵌在 `daily_schedule.json` 或独立树）|
| `police_enforcement` | ✅ (Blackman) | ❌ | `police_enforcement.json` |
| `proxy_trade` | ✅ (Dealer) | ❌ | `proxy_trade.json` |
| `sakura_npc_control` | ❌ | ✅ | `sakura_npc_control.json` |

### 3.3 共享的 Feature 键

| Feature 键 | 小镇 NPC | 樱校 NPC | 用途 |
|-----------|---------|---------|------|
| `feature_init_done` | ✅ | ✅ | 初始化完成标记 |
| `feature_dialog_req` | ✅ | ✅ | 对话请求 |
| `feature_dialog_finish_req` | ✅ | ✅ | 对话结束请求 |
| `feature_schedule` | ✅ | ✅ | 当前日程 |
| `feature_posx/y/z` | ✅ | ✅ | 目标位置 |
| `feature_rotx/y/z` | ✅ | ✅ | 目标朝向 |
| `feature_arrive` | ✅ | ✅ | 到达标记 |
| `feature_knock_req` | ✅ | ✅ | 敲门请求 |
| `feature_out_timeout` | ✅ | ✅ | 外出超时 |

### 3.4 场景特定的 Feature 键

**小镇特有**：
- `feature_meeting_state` - 聚会状态
- `feature_state_pursuit` - 追捕状态
- `feature_pursuit_entity_id` - 追捕目标
- `feature_has_proxy_order` - 代理订单

**樱校特有**：
- `feature_sakura_npc_control_req` - 控制请求
- `feature_sakura_npc_control_finish_req` - 控制结束请求

---

## 4. 硬编码问题清单

### 4.1 高优先级（阻止樱校使用）

| 节点/文件 | 硬编码内容 | 影响行为树 | 优先级 |
|----------|----------|-----------|-------|
| `behavior_nodes.go:IdleBehavior` | `GetComponentAs[*cnpc.TownNpcComp]` | `daily_schedule.json` | 🔴 高 |
| `init_position.go:SetInitialPositionNode` | `GetResourceAs[*town.TownNpcMgr]` + `GetCfgTownNpcById()` | `init.json` | 🔴 高 |
| `dialog.go:SetTownNpcOutDurationNode` | `GetComponentAs[*cnpc.TownNpcComp]` | `dialog.json` | 🔴 高 |

### 4.2 中优先级（可能影响）

| 节点/文件 | 硬编码内容 | 影响行为树 | 优先级 |
|----------|----------|-----------|-------|
| `behavior_helpers.go:getTargetPosFromFeature()` | 假设小镇特定的 feature 键结构 | `daily_schedule.json` | 🟡 中 |
| `context/context.go:GetNpcComp()` | 日志中调用 `GetNpcCfgId()` 可能假设小镇配置 | 所有行为树 | 🟡 中 |

### 4.3 低优先级（场景特定，不影响共享树）

| 节点/文件 | 硬编码内容 | 影响行为树 | 优先级 |
|----------|----------|-----------|-------|
| `behavior_nodes.go:PursuitBehavior` | `GetComponentAs[*cpolice.NpcPoliceComp]` | （小镇特定）| 🟢 低 |
| `behavior_nodes.go:PlayerControlBehavior` | `GetComponentAs[*csakura.SakuraNpcControlComp]` | `sakura_npc_control.json` | 🟢 低 |
| `specific_comp.go` | 所有节点都是场景特定 | 各自场景的树 | 🟢 低 |

---

## 5. 依赖关系

### 5.1 前置条件

- ✅ Brain 配置已支持樱花校园（`Sakura_Common_State.json` 已存在）
- ✅ 樱花校园场景已实现（`SakuraSceneInfo`, `SakuraNpcControlComp` 等组件已存在）
- ✅ 行为树系统核心框架已实现（BtRunner, BtContext, Selector/Sequence 等）

### 5.2 依赖模块

| 模块 | 依赖关系 | 说明 |
|------|---------|------|
| **ECS 组件系统** | 强依赖 | 需要查询 NPC 组件（NpcComp, TransformComp, MoveComp 等）|
| **配置系统** | 强依赖 | 需要读取 NPC 配置（位置、朝向等初始化数据）|
| **场景管理器** | 强依赖 | 需要访问场景级资源（如小镇的 TownNpcMgr，樱校的对应管理器）|
| **Feature 系统** | 强依赖 | 通过 Feature 键读取 AI 决策系统产生的状态 |

### 5.3 不依赖的模块

- ❌ **协议工程**：本次重构不涉及协议变更
- ❌ **配置工程**：不需要修改配置表结构
- ❌ **数据库**：不需要修改数据库表或 Migration

---

## 6. 涉及工程

| 工程 | 是否涉及 | 修改内容 |
|------|---------|---------|
| **业务工程 (P1GoServer/)** | ✅ | 重构行为树节点，引入能力接口抽象 |
| **协议工程 (proto/)** | ❌ | 不涉及 |
| **配置工程 (config/)** | ❌ | 不涉及（Brain 配置已存在）|
| **数据库** | ❌ | 不涉及 |

---

## 7. 技术方案概要

### 7.1 设计原则

1. **能力接口抽象**：定义行为能力接口（如 `IdleBehaviorProvider`, `PositionInitializer`）
2. **场景适配器模式**：为不同场景实现适配器（`TownIdleAdapter`, `SakuraIdleAdapter`）
3. **组件能力注册**：在 `BtContext` 中根据 NPC 组件类型自动注册可用能力
4. **向后兼容**：保持现有小镇 NPC 功能完全不变

### 7.2 重构范围

**需要重构的节点（共享节点）**：
- IdleBehavior
- MoveBehavior
- DialogBehavior
- SetInitialPositionNode
- SetTownNpcOutDurationNode（改名为 SetNpcOutDurationNode）

**不需要重构的节点（场景特定）**：
- PursuitBehavior（仅小镇警察）
- InvestigateBehavior（仅小镇警察）
- PlayerControlBehavior（仅樱校）
- ProxyTradeBehavior（仅小镇 Dealer）

### 7.3 预期代码变更量

- **新增代码**：
  - `capability/` 包：5-8 个能力接口定义
  - `adapters/` 包：10-15 个适配器实现
  - `keys/` 包：特征/黑板键规范化

- **修改代码**：
  - `behavior_nodes.go`：3-5 个节点重构
  - `init_position.go`：1 个节点重构
  - `dialog.go`：1 个节点重构
  - `context/context.go`：添加能力注册机制

- **测试代码**：
  - 新增：樱花校园 NPC 使用共享行为树的集成测试
  - 回归：确保小镇 NPC 所有测试通过

---

## 8. 风险点与缓解措施

### 8.1 技术风险

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|---------|
| **破坏现有小镇 NPC 功能** | 高 | 中 | 1. 保持向后兼容设计；2. 完整回归测试；3. 渐进式重构 |
| **能力接口设计不当** | 中 | 低 | 1. 参考现有组件接口；2. Phase 2 详细设计评审 |
| **樱校特定组件缺失** | 中 | 中 | 1. Phase 1 探索樱校组件现状；2. 补充缺失组件 |
| **性能回归** | 低 | 低 | 1. 能力缓存在 BtContext 中；2. 避免反射开销 |

### 8.2 业务风险

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|---------|
| **樱校 NPC 行为与预期不符** | 中 | 中 | 1. 与策划确认樱校 NPC 行为定义；2. 编写详细测试用例 |
| **Brain 配置不完整** | 低 | 低 | 1. 对比小镇和樱校配置；2. 补充缺失的 Feature 初始化 |

---

## 9. 优先级

**优先级**: P1（高优先级）

**理由**：
1. 当前樱花校园 NPC 无法复用共享行为树，限制了场景扩展性
2. 硬编码问题影响代码可维护性
3. 后续新增场景（如副本、活动场景）也会遇到相同问题

---

## 10. 后续优化方向

**本次重构不包含，但未来可以考虑**：

1. **完全通用化**：支持任意场景类型，而非仅小镇和樱校
2. **组件热插拔**：通过配置动态加载组件和能力
3. **节点元数据系统**：标记节点适用的场景类型，运行时检查
4. **可视化编辑器**：Brain 配置和行为树的可视化编辑工具

---

## 11. 相关文档

- **设计文档**：`P1GoServer/docs/design-bt-brain-integration.md`（现有）
- **辅助文档**：`.claude/skills/dev-workflow/BTree.md`（行为树系统知识库）
- **测试规范**：`.claude/skills/dev-workflow/TEST.md`
- **NPC 系统**：`.claude/skills/dev-workflow/NPC.md`

---

## 12. 验收测试用例（草案）

### 12.1 小镇 NPC 回归测试

```go
// 确保重构后 Dan 的行为不变
func TestDanBehaviorAfterRefactor(t *testing.T) {
    // 1. 初始化：从 TownNpcMgr 获取保存的位置
    // 2. daily_schedule：根据 feature_schedule 切换 idle/move
    // 3. dialog：响应 feature_dialog_req
    // 4. pursuit：响应 feature_state_pursuit
}

// 确保重构后 Customer 的行为不变
func TestCustomerBehaviorAfterRefactor(t *testing.T) {
    // 同上
}
```

### 12.2 樱花校园 NPC 新增测试

```go
// 测试樱校 NPC 使用共享行为树
func TestSakuraNpcUsesSharedBehaviorTrees(t *testing.T) {
    // 1. 加载 Sakura_Common_State.json 配置
    // 2. 执行 init.json：从樱校配置获取初始位置
    // 3. 执行 daily_schedule.json：根据 feature_schedule 切换状态
    // 4. 执行 dialog.json：响应对话请求
}

// 测试樱校和小镇 NPC 使用相同节点但不同组件
func TestSameNodeDifferentAdapters(t *testing.T) {
    // 1. 创建小镇 NPC 和樱校 NPC
    // 2. 两者都执行 IdleBehavior
    // 3. 验证小镇 NPC 使用 TownIdleAdapter
    // 4. 验证樱校 NPC 使用 SakuraIdleAdapter
    // 5. 两者行为结果都正确
}
```

---

**文档状态**: ✅ 待审核
**下一步**: 进入 Phase 2 技术设计
