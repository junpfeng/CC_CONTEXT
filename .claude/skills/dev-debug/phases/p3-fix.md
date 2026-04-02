## Phase 3：Bug 修复

### 3.1 修复方案制定

遵循最小改动原则：

1. **优先修根因**：不做临时绕过（workaround），除非紧急且根因修复周期长
2. **最小变更集**：只修改必要的代码，不顺手重构
3. **防御性编程**：在修复点添加必要的防御检查（nil guard、边界检查等）
4. **向后兼容**：确保修复不破坏现有行为

### 3.2 客户端错误快照（修复前基线）

修复前先采集客户端当前错误状态，作为修复后对比的基线：

1. **Unity Console 错误**：`console-get-logs(logTypeFilter="Error", lastMinutes=5, maxEntries=30)` 记录当前错误列表
2. **Editor.log 尾部**：读取最后 100 行，提取 Exception/NullReference/StackTrace
3. **MCP 不可用时**：仅读 Editor.log，记录降级状态

将采集结果记为 `baseline_errors`，后续每轮修复后对比新增/消除的错误。

### 3.3 修复-审查迭代循环（核心）

采用**奇偶轮交替**模式：奇数轮实施修复，偶数轮独立审查。每轮修复后立即进行双端编译验证。使用独立 subagent 执行审查，避免实现者与审查者共享上下文导致自我偏袒。

#### 单轮流程

```
┌─ 奇数轮：实施修复 ────────────────────────────┐
│  1. 按修复方案逐文件修改（Edit 工具）           │
│  2. 每次修改后简要说明改动意图                   │
│  3. 双端编译验证（见下方）                       │
│  4. 编译失败 → 立即修复编译错误（最多重试 3 次） │
└────────────────────────────────────────────────┘
        ↓
┌─ 偶数轮：独立审查（subagent）─────────────────┐
│  读取本次修改的所有文件，逐条检查：             │
│  1. 根因修复验证：是否真正修了根因              │
│  2. 合宪性：P1GoServer + freelifeclient rules  │
│  3. 副作用：是否影响其他调用路径                │
│  4. 最小化原则：是否有不必要的改动              │
│  5. 编码规范：日志格式、命名、错误处理          │
│  → 输出结构化 counts + 问题列表                │
└────────────────────────────────────────────────┘
```

#### 双端编译验证（每轮修复后必须执行）

```bash
# 服务端
cd P1GoServer && make build && make test

# 客户端（二选一，按可用性）
# 方式 1：Unity MCP（优先）
#   - Stop Play 模式 → 等待重编译 → console-get-logs 检查编译错误
# 方式 2：编译错误日志
#   - 读取 Editor.log 检查 CS 错误
```

涉及客户端修改时：
- 修复前：Stop Play 模式（禁止 Play 模式下重编译）
- 修复后：等待 Unity 重编译 → `console-get-logs(logTypeFilter="Error")` 确认无新增编译错误
- 对比 `baseline_errors`：确认未引入新错误，已有错误是否减少

#### 审查结果格式

```
Critical: N  （根因未修复、引入新 bug、破坏核心功能）
High: N      （副作用风险、规范严重违规）
Medium: N    （可优化项）
问题列表：[每条含位置+描述+修改建议]
```

#### 收敛判断

- **Critical=0 且 High≤2** → 质量达标，退出循环，进入 3.4
- **有 Critical 或 High>2** → 根据问题列表逐条修复 → 重新审查
- **本轮问题总数 ≥ 上轮** → 质量未改善，回滚本轮修复至审查前状态（`git checkout`），退出循环并记录原因
- **超过 10 轮** → 强制退出，汇报剩余问题

#### 完整循环图

```
实施修复（奇数轮）
    ↓
双端编译验证 ──失败──→ 修复编译错误（重试≤3次）──仍失败──→ 回滚，退出
    ↓ 通过
[subagent] 审查修复质量（偶数轮）→ 输出 counts
    ↓
Critical=0 && High≤2? ──是──→ 通过，进入 3.4
    ↓ 否
问题总数减少? ──否──→ 回滚本轮，退出循环
    ↓ 是
根据问题列表修复 → 重新编译验证 → 重新审查（最多 10 轮）
```

### 3.4 补充测试

参照项目测试规范（如有）：

1. **复现测试**：编写能复现原始 bug 的测试用例（修复前应失败）
2. **修复验证测试**：确认修复后测试通过
3. **边界测试**：覆盖相关边界条件
4. **回归保护**：确保已有测试不受影响

### 3.5 游戏内实测（Unity MCP 模拟真人操作）

对于客户端或需要运行时验证的 bug，修复后必须通过 Unity MCP 模拟真人操作进行验证。

#### MCP 工具速查

| 用途 | 工具 | 说明 |
|------|------|------|
| Editor 状态 | `editor-application-get-state` | 检查 IsPlaying、IsCompiling |
| Play/Stop | `editor-application-set-state` | 控制 Play 模式 |
| Game View 截图 | `screenshot-game-view` | 截取游戏画面（含 UI Toolkit） |
| Scene View 截图 | `screenshot-scene-view` | 截取场景编辑器画面 |
| 控制台日志 | `console-get-logs` | 读取 Error/Warning 日志 |
| 查找 GameObject | `gameobject-find` | 按名称查找（**无法找到 UI Toolkit 元素**） |
| 读取组件数据 | `gameobject-component-get` | 读取指定组件属性 |
| 执行 C# 代码 | `script-execute` | 执行任意 C# 代码读写运行时状态 |
| 场景数据 | `scene-get-data` | 查看场景层级结构 |

#### 关键技术约束

- **UI Toolkit**：登录界面、HUD 等使用 UI Toolkit，`gameobject-find` **无法找到**这些元素，必须用 `script-execute` + `UIDocument.rootVisualElement.Q()` 查找和操作
- **UI Toolkit 按钮点击**：使用 `ClickEvent.GetPooled()` + `SendEvent()` 触发（见下方案例）
- **Game View 截图失败**：首次截图可能因窗口未打开失败，需先用 `script-execute` 聚焦 Game View
- **script-execute 返回空值**：Play 模式刚激活时执行脚本常返回空，需重试（最多 3 次，间隔 3s）
- **禁止 Play 模式下重编译**：修改脚本前必须先 `editor-application-set-state(isPlaying=false)`
- **直接引用类型**：`script-execute` 中直接 `using` 引用类型，**不要用 `Type.GetType()` 反射**

---

#### 准备阶段

1. **检查 Unity 状态**：`editor-application-get-state` 确认 Editor 在线且未编译
2. **确认是否在游戏中**：`screenshot-game-view` 截图判断当前画面状态
3. **登录游戏**：未在游戏中则调用 `/unity-login` 进入；需要重新登录则 `/unity-login relogin`
4. **查找测试方案**（按优先级搜索）：
   1. 在整个 `docs/` 目录中搜索该功能对应的文档，读取其中的"真人测试方式"/"验收测试"/"MCP 测试"章节
   2. 若未找到，则根据 bug 的触发路径和代码逻辑，在对应设计文档目录下创建测试方案文档（命名：`<功能模块名>_test.md`），供后续复用

---

#### 模拟真人操作验证（循环执行，直到通过）

5. **执行测试步骤**：使用 Unity MCP 工具模拟真人操作（点击 UI、移动角色、触发交互等）
6. **截图取证**：每个关键步骤 `screenshot-game-view` 截图
7. **读取运行时状态**：`script-execute` 读取相关 Manager/系统内部数据，验证状态正确性
8. **检查日志**：`console-get-logs(logTypeFilter="Error", lastMinutes=2)` 检查新错误
9. **判定结果**：
   - **通过** → 记录验证结果，进入 3.7
   - **失败** → 自动进入修复-重测循环

---

#### 修复-重测循环（自动执行，无需用户确认）

若测试未通过：
1. 分析失败原因（截图 + 日志 + 运行时状态）
2. **先退出 Play 模式**（`editor-application-set-state(isPlaying=false)`）
3. 定位并修复代码
4. 等待编译完成（`console-get-logs` 确认无编译错误）
5. 重新进入 Play 模式 + `/unity-login` 登录
6. 从步骤 5 重新执行测试
7. **持续循环直到测试全部通过**

> 循环上限：连续失败 5 次后暂停，向用户汇报当前状态和已尝试的修复方案，请求指导。

**边界验证**：核心流程通过后，额外测试相关边界场景（切场景、传送、死亡复活等）

---

#### P3→P4 门禁：MCP Marker 验证（强制）

> **IMPORTANT：此门禁在 P3 结束、进入 P4 之前必须通过。未通过则禁止进入 P4。**

当本次修复涉及客户端 `.cs` 文件（非 codegen 路径）时，P3 结束前必须验证 MCP marker 存在且有效：

```bash
python3 .claude/hooks/mcp_verify_lib.py validate "$CLAUDE_SESSION_ID"
```

| 验证结果 | 处理 |
|----------|------|
| `VALID` | 通过，进入 P4 |
| `INVALID: marker not found` | 尚未执行 MCP 视觉验证。**必须回到"模拟真人操作验证"步骤**，通过 MCP 截图/脚本执行完成验证 |
| `INVALID: expired` | Marker 已过期（>30 分钟）。重新执行 MCP 截图刷新 marker |
| `INVALID: session mismatch` | 其他 session 的 marker。重新执行 MCP 截图 |

**跳过条件**（任一满足则跳过此门禁）：
- 修复仅涉及服务端 `.go` 文件（无客户端变更）
- 所有 `.cs` 变更均在 codegen 路径下（`Proto/`, `Config/Gen/`, `Managers/Net/Proto/`）
- `--mode acceptance` 模式（验收场景，MCP 验证由上游负责）

**禁止绕过**：不得通过任何方式手动创建或伪造 marker 文件。marker 只能由 MCP 工具调用后自动生成（PostToolUse hook 或 mcp_call.py 内置写入）。

---

#### MCP 模拟测试案例库

以下案例展示常见系统/模块的 MCP 模拟真人测试方法，实际使用时根据 bug 所在模块选择对应案例并按需调整。

##### 案例 1：NPC 系统测试（AI 行为、状态、交互）

```csharp
// 读取场景中所有 NPC 状态
using UnityEngine;
public class Script
{
    public static object Main()
    {
        var npcMgr = Object.FindObjectOfType<FL.Gameplay.NpcManager>();
        if (npcMgr == null) return "NpcManager not found";
        var sb = new System.Text.StringBuilder();
        // 遍历场景中的 NPC，读取关键状态
        var npcs = Object.FindObjectsOfType<FL.Gameplay.NpcController>();
        sb.AppendLine($"NPC count: {npcs.Length}");
        foreach (var npc in npcs)
        {
            sb.AppendLine($"  [{npc.name}] pos={npc.transform.position}");
        }
        return sb.ToString();
    }
}
```

```csharp
// 模拟玩家接近 NPC 并触发交互
using UnityEngine;
public class Script
{
    public static object Main()
    {
        // 找到目标 NPC
        var npcs = Object.FindObjectsOfType<FL.Gameplay.NpcController>();
        if (npcs.Length == 0) return "No NPC found";
        var target = npcs[0];
        // 将玩家传送到 NPC 附近（测试用）
        var player = Object.FindObjectOfType<FL.Gameplay.PlayerController>();
        if (player == null) return "Player not found";
        var npcPos = target.transform.position;
        player.transform.position = npcPos + new Vector3(2f, 0f, 0f);
        return $"Player moved to {player.transform.position}, near NPC [{target.name}] at {npcPos}";
    }
}
```

> **验证要点**：截图确认 NPC 可见 → 读取 NPC 状态数据 → 模拟接近/交互 → 截图确认交互结果 → 检查日志无报错

##### 案例 2：UI 系统测试（UI Toolkit 面板、按钮、数据显示）

```csharp
// 查找并读取 UI Toolkit 面板状态
using UnityEngine;
using UnityEngine.UIElements;
public class Script
{
    public static object Main()
    {
        var sb = new System.Text.StringBuilder();
        var docs = Object.FindObjectsOfType<UIDocument>();
        sb.AppendLine($"UIDocument count: {docs.Length}");
        foreach (var doc in docs)
        {
            if (doc.rootVisualElement == null) continue;
            sb.AppendLine($"  [{doc.name}] display={doc.rootVisualElement.style.display}");
            // 列出一级子元素
            for (int i = 0; i < doc.rootVisualElement.childCount && i < 10; i++)
            {
                var child = doc.rootVisualElement[i];
                sb.AppendLine($"    child[{i}]: name={child.name} type={child.GetType().Name} visible={child.resolvedStyle.display}");
            }
        }
        return sb.ToString();
    }
}
```

```csharp
// 点击 UI Toolkit 按钮（通用模板）
using UnityEngine;
using UnityEngine.UIElements;
public class Script
{
    public static object Main()
    {
        string panelName = "目标面板名";   // 替换为实际面板名
        string buttonName = "目标按钮名"; // 替换为实际按钮名
        var docs = Object.FindObjectsOfType<UIDocument>();
        foreach (var doc in docs)
        {
            if (doc.rootVisualElement == null) continue;
            var panel = doc.rootVisualElement.Q(panelName);
            if (panel == null) continue;
            var btn = panel.Q<Button>(buttonName);
            if (btn == null) return $"Button '{buttonName}' not found in '{panelName}'";
            using (var evt = ClickEvent.GetPooled())
            {
                evt.target = btn;
                btn.SendEvent(evt);
            }
            return $"Clicked '{buttonName}' in '{panelName}'";
        }
        return $"Panel '{panelName}' not found";
    }
}
```

> **验证要点**：截图确认 UI 面板已打开 → 读取面板元素状态 → 点击按钮 → 截图确认 UI 响应正确 → 检查日志无报错

##### 案例 3：场景/地图系统测试（场景切换、传送、加载）

```csharp
// 读取当前场景状态
using UnityEngine;
public class Script
{
    public static object Main()
    {
        var sb = new System.Text.StringBuilder();
        try
        {
            bool inTown = FL.Gameplay.Manager.SceneManager.IsInTown;
            var uType = FL.Gameplay.Manager.SceneManager.UniverseType;
            sb.AppendLine($"IsInTown={inTown} UniverseType={uType}");
        }
        catch (System.Exception ex) { sb.AppendLine($"SceneManager error: {ex.Message}"); }
        // 已加载的 Unity 场景
        for (int i = 0; i < UnityEngine.SceneManagement.SceneManager.sceneCount; i++)
        {
            var scene = UnityEngine.SceneManagement.SceneManager.GetSceneAt(i);
            sb.AppendLine($"  Scene[{i}]: {scene.name} loaded={scene.isLoaded}");
        }
        return sb.ToString();
    }
}
```

```csharp
// 模拟进入小镇场景
using UnityEngine;
using FL.NetModule;
public class Script
{
    public static object Main()
    {
        var req = new EnterTowmReq();
        NetCmd.StartEnterTown(req);
        return "EnterTown requested, wait 15-20s for scene load";
    }
}
```

> **验证要点**：读取当前场景 → 触发场景切换 → 等待 15-20s → 读取新场景状态 → 截图确认场景画面 → 检查日志无报错

##### 案例 4：玩家移动/输入系统测试

```csharp
// 读取玩家位置和移动状态
using UnityEngine;
public class Script
{
    public static object Main()
    {
        var player = Object.FindObjectOfType<FL.Gameplay.PlayerController>();
        if (player == null) return "PlayerController not found";
        var sb = new System.Text.StringBuilder();
        sb.AppendLine($"Position: {player.transform.position}");
        sb.AppendLine($"Rotation: {player.transform.eulerAngles}");
        // 读取 Rigidbody 速度（如有）
        var rb = player.GetComponent<Rigidbody>();
        if (rb != null) sb.AppendLine($"Velocity: {rb.linearVelocity} speed={rb.linearVelocity.magnitude:F2}");
        return sb.ToString();
    }
}
```

```csharp
// 模拟玩家传送到指定坐标（调试用）
using UnityEngine;
public class Script
{
    public static object Main()
    {
        var player = Object.FindObjectOfType<FL.Gameplay.PlayerController>();
        if (player == null) return "PlayerController not found";
        var targetPos = new Vector3(100f, 0f, 200f); // 替换为目标坐标
        player.transform.position = targetPos;
        return $"Player teleported to {targetPos}";
    }
}
```

> **验证要点**：读取初始位置 → 执行移动/传送 → 读取新位置确认变化 → 截图确认画面 → 检查日志无报错

##### 案例 5：网络/协议系统测试

```csharp
// 读取网络连接状态
using UnityEngine;
public class Script
{
    public static object Main()
    {
        var sb = new System.Text.StringBuilder();
        try
        {
            var netMgr = FL.Gameplay.Manager.NetManager.Instance;
            if (netMgr == null) return "NetManager.Instance is null";
            sb.AppendLine($"NetManager exists, type={netMgr.GetType().Name}");
        }
        catch (System.Exception ex) { sb.AppendLine($"NetManager error: {ex.Message}"); }
        return sb.ToString();
    }
}
```

> **验证要点**：检查网络连接状态 → 触发业务操作（如发送请求） → 等待响应 → 读取结果状态 → 检查日志中的协议错误

##### 案例 6：聚焦 Game View 窗口（截图失败时使用）

```csharp
// 首次截图失败时，先聚焦 Game View 窗口再重试
using UnityEngine;
public class Script
{
    public static object Main()
    {
        var gameViewType = System.Type.GetType("UnityEditor.GameView,UnityEditor");
        if (gameViewType != null)
            UnityEditor.EditorWindow.GetWindow(gameViewType, false, "Game", true);
        return "Game View focused";
    }
}
```

> 注意：这是唯一允许使用 `Type.GetType()` 的场景（Editor 类型不在 Assembly-CSharp 中）。

---

#### MCP 不可用时的恢复流程

**禁止因 MCP 不可用而跳过测试**。必须先尝试恢复连接：

1. **检测 MCP 状态**：`python3 scripts/mcp_call.py list-tools`，若返回 "Response data is null" 说明断连
2. **重启 MCP**：`powershell.exe -File scripts/unity-restart.ps1 restart-mcp`，等待 10s
3. **重试检测**：再次 `python3 scripts/mcp_call.py list-tools`
4. **仍然失败**：`powershell.exe -File scripts/unity-restart.ps1 restart-all`（重启 Unity + MCP）
5. **连续 3 次重启仍失败** → 向用户汇报 MCP 恢复失败，请求手动干预，**不要直接跳过测试让用户去测**

> 教训：MCP 断连是常见问题（Unity 长时间运行、编译后断连等），恢复通常只需重启 MCP Server。
> 直接跳过测试丢给用户是不可接受的——用户使用 `/dev-debug` 就是期望全程自动。

#### 跳过条件

- 纯服务端逻辑 bug（无客户端表现）→ 跳过，走单元测试验证
- Unity Editor 未安装或项目不涉及客户端 → 跳过

### 3.6 交付前 MCP 全方位验收（强制执行，不可跳过）

在宣布修复完成前，必须通过 Unity MCP **模拟真人全流程复现** bug 并确认已修复。**数据正确 ≠ bug 已修复**——script-execute 读到的数值可能正确，但实际游戏体验可能仍然异常。

#### 3.6.1 设计验收方案

根据 bug 的具体表现和触发条件，设计覆盖以下维度的验收方案：

| 维度 | 说明 | 示例 |
|------|------|------|
| **复现路径** | 模拟用户触发 bug 的完整操作链 | 登录→进入大世界→走到NPC密集区→靠近NPC |
| **状态读取** | script-execute 读取修复相关的运行时数据 | 读取 NPC PartList 长度、面部部件 active 状态 |
| **视觉截图** | 截图确认画面符合预期 | 正面/侧面截图看 NPC 穿着和头部 |
| **边界条件** | 测试 bug 相关的极端/临界场景 | 多距离（1m/5m/20m）、多样本（≥3个NPC）、快速切换 |
| **副作用排查** | 验证修复未破坏相邻功能 | NPC 动画正常、移动正常、不卡顿 |

#### 3.6.2 执行验收

使用 Unity MCP 工具链全自动执行验收方案：

1. **环境准备**：确认 Play 模式 + 已登录 + 在正确场景
2. **场景布置**：传送玩家到目标位置、GM 生成/召唤测试对象
3. **操作模拟**：移动玩家、改变距离、触发交互、切换状态
4. **多维采集**：每个关键步骤同时采集截图 + 运行时数据 + 日志
5. **结果判定**：截图 + 数据 + 日志三者一致才算通过

#### 3.6.3 验收清单

**通用项（每次必检）：**

| 检查项 | 方法 | 通过标准 |
|--------|------|----------|
| 编译通过 | 服务端 `make build` + 客户端 `console-get-logs(Error)` | 零编译错误 |
| 无新增运行时错误 | 对比 `baseline_errors` | 新增错误数 = 0 |
| 原始 bug 不再复现 | 按用户描述的触发路径操作 | bug 现象消失 |
| 副作用排查 | 修复涉及模块的基本功能验证 | 无回归 |

**客户端表现项（涉及视觉/交互时必检）：**

| 检查项 | 方法 | 通过标准 |
|--------|------|----------|
| MCP 截图确认 | Camera.main 截图 → Read 查看 | 画面符合预期 |
| 运行时状态一致 | script-execute 读取关键状态 | 数据与截图表现一致 |
| 边界条件覆盖 | 针对 bug 特征设计的边界测试 | 所有边界场景通过 |

#### 3.6.4 未通过处理

- 任一检查项未通过 → 分析原因 → 回到 3.3 修复-审查循环
- 全部通过 → 进入 3.7

### 3.7 输出修复摘要

```
Bug 修复摘要：
- 根因：[root cause]
- 修复方案：[approach]
- 修改文件：
  * file1 — [改动描述]
  * file2 — [改动描述]
- 新增测试：
  * test_file — TestXxx [测试描述]
- 构建验证：通过/失败
- 测试验证：通过/失败
- 游戏内实测：通过/失败/待测（附截图或日志）
- 视觉验收：通过/不适用（附截图路径）
- MCP 测试方案：已有（路径）/ 新建（路径）/ 无（纯服务端）
```

### 3.8 自动提交修复

修复验证全部通过后，自动提交变更到 Git：

1. 通过 Skill 工具调用 `git:commit`，commit 消息格式：`fix(<模块>): <bug 一句话描述>`
2. Skill 不可用时直接执行 `git add` + `git commit`
3. **不自动 push**——仅本地提交，push 由用户决定

**自动进入 Phase 4。**
