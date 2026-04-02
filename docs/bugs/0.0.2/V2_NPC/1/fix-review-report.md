═══════════════════════════════════════════════
  Bug Fix Review 报告
  版本：0.0.2
  模块：V2_NPC
  审查文件：25 个（服务端 16 + 客户端 9）
═══════════════════════════════════════════════

## 一、根因修复验证

### 根因对应性
✅ **scene_npc_mgr.go:359** 正确添加了 `entity.AddComponent(csystem.NewAnimStateComp())`，
同步在 line 17 追加了 `"mp/servers/scene_server/internal/ecs/com/csystem"` import。
对应根因 A：`CreateDynamicBigWorldNpc` 缺失 `AnimStateComp` → `getNpcMsg` 返回 nil →
客户端 `SyncWithDataManager` 过滤所有 BigWorld NPC。

### 修复完整性
✅ 修复点覆盖了唯一触发路径。`bigworld_npc_spawner.go:630` 调用 `CreateDynamicBigWorldNpc`，
所有动态生成的 BigWorld NPC 都会经过该函数，修复一次即全量生效。
`bt_tick_system.go` 额外添加了 AnimStateComp 缺失时的 warning 日志，属于防御性改进。

### 影响范围覆盖
✅ 根因 B（小地图图例立即自删）是根因 A 的级联效果，分析报告已预判其随 A 修复自动解决。
客户端 `BigWorldNpcFsmComp.cs` 扩展了服务端状态映射（新增 Interact/Death/Shelter 等 17 种），
确保 AnimStateComp 现在能正确推送的状态在客户端侧有对应处理路径。

---

## 二、合宪性审查

### 客户端（涉及 9 个 .cs 文件）

| 条款 | 状态 | 说明 |
|------|------|------|
| 编译正确性 | ✅ | Config/Gen 文件均为工具自动生成（文件头 `// This file is generated from template`），非手动编辑 |
| 禁止手动编辑生成区 | ✅ | `CfgLegendType.cs` / `CfgNpc.cs` 在 `Config/Gen/`，均有标准生成头，走打表工具更新，未违规 |
| 7.1 日志 | ✅ | 修改的 .cs 文件未发现 `MLog` + `$""` 插值（未涉及新增日志） |
| 3.3 事件配对 | ✅ | `BigWorldNpcController.cs` 移除了直接置 null 的组件引用，改由框架统一管理；未发现新增事件订阅缺配对取消 |
| SetMoveTarget 删除 | ✅ | `BigWorldNpcMoveComp.cs` 删除了 `SetMoveTarget()` 方法，全局 grep 确认零调用者，无遗漏引用 |

### 服务端（涉及 16 个 .go 文件，仅审查本次 diff）

| 条款 | 状态 | 说明 |
|------|------|------|
| 错误处理 | ✅ | `CreateDynamicBigWorldNpc` 新增了 entity 孤儿泄漏防护（AddNpc 失败时 `scene.RemoveEntity`）；extHandler 失败时完整回滚 |
| 错误传播上下文 | ✅ | 所有 error return 均使用 `fmt.Errorf("... %w", err)` 包裹，携带上下文 |
| 日志格式（新增文件） | ✅ | 在本次 diff 的新增文件（bigworld_npc_spawner.go / bigworld_gm.go / bigworld_ext_handler.go）中，grep 未发现 `%d`/`%s` 格式符违规 |
| safego | ✅ | 未发现裸 goroutine |
| 禁止手动编辑生成区 | ✅ | 未触碰 `common/proto/` 或 `service/*.go` 生成文件 |

> **旁注（预存在违规，不计入本次）**：`animal_init.go:35/43/162` 和 `bigworld_npc_config.go:120` 存在 `%d`/`%s` 格式符，但这些文件不在本次 diff 范围内，属于历史遗留。

---

## 三、副作用与回归风险

[HIGH] 提交范围超出 Bug 修复边界
  场景: 本次提交混合了核心 Bug 修复（AnimStateComp）与大量新功能
  影响:
    - 服务端新增：WalkZone 配额驱动 Spawner（+397 行）、GM 命令（bigworld_gm.go 150 行）、
      ExtHandler 扩展（bigworld_ext_handler.go +100 行）
    - 客户端新增：OnPatrolNodeArrive 消息处理、动画速度防抖优化、
      小地图图例完整显示逻辑（MapPanel.cs +51 行）
    - 这些变更引入了新的执行路径，若出现回归，难以区分是 Bug 修复引起还是新功能引起
  建议: 后续类似情况将 Bug 修复提交（fix）与功能增强提交（feat）分开，
        便于 bisect 和回归定位。本次已提交，建议在 changelog 中注明混合变更

---

## 四、最小化修改检查

❌ 存在超出 Bug 修复范围的代码变更（功能增强，非格式化/重构）

- 根因分析报告结论："仅需修改服务端 scene_npc_mgr.go，客户端无需修改"
- 实际变更：服务端 16 文件（含全新配额系统）+ 客户端 9 文件
- 超出范围的变更均为合理的功能迭代，未发现危险副作用
- 核心 Bug 修复（scene_npc_mgr.go +5 行）本身是最小化的，超出部分是并行功能工作

---

## 五、总结

  CRITICAL: 0 个
  HIGH:     1 个（提交范围超边界，混合 Bug 修复与新功能）
  MEDIUM:   0 个

  结论: **通过**（核心 Bug 修复正确，HIGH 问题为工程规范建议，不阻塞上线）

  重点关注:
  1. 核心修复正确且完整：AnimStateComp 已正确挂载，注释清晰说明原因，回滚防护完善
  2. 提交包含大量新功能（配额 Spawner、GM 命令、FSM 状态扩展），回归测试需覆盖这些新路径
  3. 下次修复类 Bug 时，建议拆分提交（fix: AnimStateComp + feat: 配额系统），降低回归定位成本

<!-- counts: critical=0 high=1 medium=0 -->
