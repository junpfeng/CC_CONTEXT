# 召唤轮盘 (Summon Wheel) 设计审查报告

**审查日期**: 2026-03-31
**审查文件**: `docs/version/0.0.3/summon_wheel/design.md`
**结论**: **PASS (有条件)**  -- 需修复 1 个 HIGH 问题，其余为改进建议

---

## 严重问题（必须修改）

### [HIGH-1] 缺少 InputMode 和光标管理设计

**问题**: 设计文档未提及 SummonWheel 打开时的 InputMode 切换和光标显示。现有 PoseWheelPanel 在 `OnShow` 中调用 `CursorManager.ShowCursor()` + `InputManager.EnterMode<PoseWheelUiMode>()`，在 `OnHide` 中恢复。SummonWheel 作为同类轮盘交互（鼠标选择扇区），必须有相同的输入模式管理，否则：
- 轮盘打开后鼠标不可见，无法选择扇区
- 其他输入（移动、攻击）未禁用，操作冲突

**改进建议**:
1. 在设计中明确：新增 `SummonWheelUiMode : InputMode`（或复用 `PoseWheelUiMode`），在 `OnShow`/`OnHide` 中切换
2. `InputModes.cs` 中添加对应 Mode，`Configure()` 中 `DisableAll()` + `EnableInputAction(_input.UIOperation.OpenSummonWheelPanel)` + `EnableInputActionMap(_input.Cursor)`
3. `OnShow` 中 `CursorManager.ShowCursor()`，`OnHide` 中 `CursorManager.HideCursor()`

---

## 建议改进（推荐修改）

### [MEDIUM-1] PanelEnum 修改路径矛盾

**问题**: 设计 3.2 修改文件列出两个 PanelEnum 文件：
- `CodeTemplates/PanelEnum.cs`（模板）
- `Assets/Scripts/3rd/RUI/Runtime/AutoGen/PanelEnum.cs`（自动生成）

但实际项目中，UI 逻辑使用的是 `Assets/Scripts/Gameplay/Modules/UI/Pages/Config/UIPanelEnum.cs`（namespace `FL.Framework.UI`），而 `RUI/AutoGen/PanelEnum.cs` 是另一个 namespace `RUI` 的独立枚举（内容仅有 Test2Panel/TestPanel）。设计应该修改的是 `UIPanelEnum.cs`，而非 `RUI/AutoGen/PanelEnum.cs`。

**改进建议**: 将目标文件更正为 `Assets/Scripts/Gameplay/Modules/UI/Pages/Config/UIPanelEnum.cs`，在末尾添加 `SummonWheel, // All`。

### [MEDIUM-2] SummonWheelView 硬编码 slot1/slot2 字段，与"数据驱动"设计矛盾

**问题**: 设计 3.3 SummonWheelPanel 声称"槽位数据驱动，后续扩展只需加数据"，但 3.4 SummonWheelView 硬编码了 `slot1Button`/`slot2Button`/`slot1Icon`/`slot2Icon`/`slot1Label`/`slot2Label`。如果后续扩展到 3+ 槽位，View 和 UXML 都需要大改。

**改进建议**: 参考 PoseWheelPanel 的做法（12 个 button 数组 + Widget），改为在 UXML 中用 `ScrollView` 或固定容器 + 动态创建子元素的方式。或者如果确认短期内只有 2 个槽位，就在设计文档中明确声明"V1 硬编码 2 槽位，后续扩展需重构 View/UXML"，不要同时声称"数据驱动"又硬编码。

### [MEDIUM-3] 缺少 OnClose/OnClear 生命周期设计

**问题**: 设计 3.3 仅展示了字段定义和初始化方法，未展示 `OnClose()`/`OnClear()` 中的清理逻辑。根据项目规范（lesson-008），override 生命周期方法必须调用 base，且需要：
- 取消事件订阅（按钮 onClick）
- Cancel + Dispose CancellationTokenSource
- 清空槽位列表

参考 SummonDogPanel.cs 和 PoseWheelPanel.cs 已有完整的 OnClose/OnClear 实现。

**改进建议**: 在设计中补充 OnClose/OnClear 的清理逻辑骨架，特别是 `_summonDogCts` 的生命周期管理。

### [MEDIUM-4] UIConfig.json 配置缺少关键字段

**问题**: 设计 3.6 的 UIConfig.json 配置仅列出基础字段。需要确认 `group`/`level`/`showMode` 的值是否正确。现有 PoseWheel 的配置值应作为参考（同为轮盘类 UI，可能需要相同的 showMode 以确保互斥关闭逻辑正确）。

**改进建议**: 读取现有 UIConfig.json 中 PoseWheel 的配置，确保 SummonWheel 的 group/level/showMode 与之匹配或有明确的设计意图说明。

### [MEDIUM-5] 快捷键 O 冲突检查不完整

**问题**: 设计提到绑定键盘 O，但未说明在哪些 InputActionMap 中注册。设计 3.2 列出 UIOperation/Vehicle/PhotoMode 三个 action map，但未说明为何需要在 Vehicle 和 PhotoMode 中也注册（驾驶中/拍照中是否允许打开召唤轮盘？），以及是否需要在其他 map（如 Building）中注册。

**改进建议**: 明确在哪些游戏状态下允许打开召唤轮盘，并仅在对应的 action map 中注册。如果驾驶中不需要，则不应在 Vehicle map 中注册。

### [LOW-1] 测试用例缺少冷却和错误码场景

**问题**: TC 列表缺少以下场景的测试：
- 2 秒冷却期内重复点击召唤狗（REQ-003 验收标准 2）
- 召唤狗失败（错误码 14005）的 UI 反馈
- 轮盘打开时按 O 关闭（toggle 行为）

**改进建议**: 补充 TC-005（冷却测试）和 TC-006（失败处理测试）。

### [LOW-2] 设计未提及与 PoseWheel 中已有召唤狗入口的关系

**问题**: PoseWheelPanel.cs 中已有 `_summonDogCts`/`summonDogButton` 相关逻辑。idea.md 提到"从 PoseWheel 移除现有的召唤狗按钮（可后续单独做）"，但 design.md 完全未提及。两个入口同时存在可能导致用户困惑，且共享冷却状态未设计。

**改进建议**: 在设计中明确说明："V1 不移除 PoseWheel 中的召唤狗入口，两个入口独立冷却计时，后续版本移除 PoseWheel 入口"。

---

## 确认无问题的部分

1. **架构一致性**: 遵循项目 Panel-View-Widget 模式，与 PoseWheel 同级独立实现，不引入新抽象，符合 YAGNI
2. **需求覆盖**: REQ-001~005 均有对应设计，纯客户端无服务端改动，范围清晰
3. **网络逻辑复用**: 正确复用 `NetCmd.SummonDog` 和 `PhoneMyCarPanel`，不重复实现
4. **文件路径**: 新增文件路径与现有轮盘面板一致
5. **InputSystem 注册**: action 定义格式正确，O 键未被占用
6. **错误处理**: 覆盖了冷却、网络失败（14005）、PhoneMyCarPanel 打开失败三种异常
7. **UXML 结构**: 参考 PoseWheel 风格，使用 MButton + VisualElement 布局合理

---

## 审查总结

| 级别 | 数量 | 说明 |
|------|------|------|
| CRITICAL | 0 | - |
| HIGH | 1 | InputMode/光标管理缺失 |
| MEDIUM | 5 | PanelEnum路径、View硬编码、生命周期清理、UIConfig、按键作用域 |
| LOW | 2 | 测试用例补充、PoseWheel入口关系 |

**结论: PASS (有条件)** -- 修复 HIGH-1（InputMode + 光标管理）后可进入开发。MEDIUM 问题建议在实现阶段一并处理。
