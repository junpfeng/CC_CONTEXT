# 已修复 Bug

## Bug #1: 召唤轮盘按钮点击无反应

**根因（多层）**:
1. `CursorManager.ShowCursor()`/`HideCursor()` 被注释掉 — 但实际上在 Mobile 平台是空操作，不是真正根因
2. 按钮设置了 `pickingMode = PickingMode.Ignore`，导致按钮背景区域不响应点击
3. 使用了从 PoseWheelPanel 复制的角度选择机制（onPointerDown → CheckMousePosition），不适用于 2 按钮直接点击场景
4. MButton 清除了 `clickable.activators`，不会从指针交互生成 ClickEvent，所以 onClick 无法通过正常点击触发

**修复方案**:
- 移除 `pickingMode = PickingMode.Ignore`（按钮恢复默认 Position，整个区域可点击）
- 移除角度计算逻辑（CheckMousePosition、OnSlotSelected、_curSlotIndex）
- 将 onPointerDown/onPointerUp 角度选择改为 `onPointerUp` 直接触发对应槽位回调
- 保留 CursorManager.ShowCursor()/HideCursor() 调用（Standalone 平台需要）

**修改文件**: `freelifeclient/Assets/Scripts/Gameplay/Modules/UI/Pages/Panels/SummonWheelPanel.cs`

**验证**: Unity 编译通过 + MCP 运行时验证：打开面板 → 模拟 PointerDown/PointerUp 点击 slot2 → SummonWheel 正确关闭（回调执行成功）→ 截图确认游戏回到 HUD
