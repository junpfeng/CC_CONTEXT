# 召唤轮盘 (Summon Wheel) 技术设计

## 1. 需求回顾

参考 `requirements.json`：REQ-001~005，纯客户端功能，不涉及服务端改动。

## 2. 架构设计

### 2.1 系统边界

仅涉及 `freelifeclient`。新增独立的 SummonWheelPanel，不修改现有 PoseWheel/PhoneMyCarPanel。

### 2.2 输入事件流

```
键盘 O → PlayerControls.inputactions (OpenSummonWheelPanel action)
       → InputManager 注册 performed 回调
       → InputEvent.SendEvent(InputEventId.OpenSummonWheelPanel)
       → HudInGamePanel / HudDefaultPanel 订阅该事件
       → UIManager.Open<SummonWheelPanel>()
```

### 2.3 InputMode 与光标管理

轮盘打开/关闭时需要切换输入模式和光标状态（参考 PoseWheel 模式）：

```
OnShow:
  CursorManager.ShowCursor()
  InputManager.EnterMode<UIMode>()  // 复用通用 UIMode，屏蔽玩家移动/攻击

OnHide:
  CursorManager.HideCursor()
  InputManager.ExitCurrentMode()

O 键生效范围：UIOperation / Vehicle / PhotoMode action maps（与 PoseWheel X 键一致）
```

### 2.4 扇区选择流

```
鼠标移动 → CheckMousePosition()
         → Atan2 计算角度 → 360°/N 分扇区
         → OnSlotSelected(index) → 高亮反馈
鼠标点击 → ExecuteSlotAction(index)
         → index=0: SummonDog 逻辑
         → index=1: 关闭轮盘 + 打开 PhoneMyCarPanel
```

## 3. 详细设计

### 3.1 新增文件

| 文件 | 路径 | 说明 |
|------|------|------|
| SummonWheelPanel.cs | `Assets/Scripts/Gameplay/Modules/UI/Pages/Panels/` | 面板逻辑 |
| SummonWheelView.cs | `Assets/Scripts/Gameplay/Modules/UI/Pages/Views/` | View 绑定 |
| SummonWheel.uxml | `Assets/PackResources/UI/Group_Mobile/SummonWheel/` | Mobile 布局 |
| SummonWheel.uxml | `Assets/PackResources/UI/Group_PC/SummonWheel/` | PC 布局 |

### 3.2 修改文件

| 文件 | 修改内容 |
|------|---------|
| `Assets/Scripts/Gameplay/Modules/UI/Pages/Config/UIPanelEnum.cs` | 添加 `SummonWheel` 枚举值（业务层 PanelEnum 注册点） |
| `Assets/PackResources/UI/PanelSettings/UIConfig.json` | 添加 SummonWheel 配置条目 |
| `Assets/Scripts/Gameplay/Managers/Input/PlayerControls.inputactions` | 添加 OpenSummonWheelPanel action + O 键绑定 |
| `Assets/Scripts/Gameplay/Managers/Input/InputEventId.cs` | 添加 `OpenSummonWheelPanel` 常量 |
| `Assets/Scripts/Gameplay/Managers/Input/InputManager.cs` | 注册 UIOperation/Vehicle/PhotoMode 的 performed 回调发送事件 |
| `Assets/Scripts/Gameplay/Managers/Input/Callback/UIOperationCallback.cs` | 添加 `OnOpenSummonWheelPanel` 方法 |
| `Assets/Scripts/Gameplay/Managers/Input/Callback/VehicleCallback.cs` | 添加 `OnOpenSummonWheelPanel` 方法 |
| `Assets/Scripts/Gameplay/Managers/Input/InputMode/InputModes.cs` | EnableInputAction 新 action |
| `Assets/Scripts/Gameplay/Modules/UI/Pages/Panels/HudInGamePanel.cs` | 订阅 OpenSummonWheelPanel 事件 |
| `Assets/Scripts/Gameplay/Modules/UI/Pages/Panels/HudDefaultPanel.cs` | 订阅 OpenSummonWheelPanel 事件 |
| `Assets/Scripts/Gameplay/Managers/Input/PlayerControls.cs` | 自动生成文件，需手动添加对应代码或通过 Unity Editor 重新生成 |

### 3.3 SummonWheelPanel 核心结构

```csharp
public class SummonWheelPanel : UIPanel
{
    public override PanelEnum Name => PanelEnum.SummonWheel;
    protected override Type ViewType => typeof(SummonWheelView);

    // 槽位数据驱动
    private struct SlotData
    {
        public string name;        // 显示名称
        public string iconName;    // 图标元素名称
        public Action callback;    // 点击回调
    }

    private List<SlotData> _slots;
    private List<MButton> _slotButtons;
    private int _curSlotIndex = -1;

    // 召唤狗冷却
    private const float SummonDogCooldown = 2f;
    private float _summonDogCooldownEndTime;
    private CancellationTokenSource _summonDogCts;

    // 初始化槽位数据（数据驱动，后续扩展只需在此添加）
    private void InitSlotData()
    {
        _slots = new List<SlotData>
        {
            new SlotData { name = "召唤狗", iconName = "summonDogIcon", callback = OnSummonDogClicked },
            new SlotData { name = "叫车", iconName = "phoneCarIcon", callback = OnPhoneMyCarClicked }
        };
    }

    // 动态绑定 UXML 按钮到槽位数据
    private void InitSlotButtons()
    {
        // 从 View 的 root 按 "btn-slot{i+1}" 模式查询按钮
        // 数量由 _slots.Count 决定，非硬编码
    }

    // 角度选择（动态 360°/N）
    private void CheckMousePosition(Vector2 pos) { /* Atan2 算法 */ }

    // 召唤狗：2s冷却 + NetCmd.SummonDog
    private void OnSummonDogClicked() { ... }

    // 叫车：关闭轮盘 + 打开 PhoneMyCarPanel
    private void OnPhoneMyCarClicked() { ... }

    // 生命周期清理
    protected override void OnClose()
    {
        _summonDogCts?.Cancel();
        _summonDogCts?.Dispose();
        _summonDogCts = null;
        // 退订所有按钮事件
        base.OnClose();
    }
}
```

### 3.4 SummonWheelView 结构

```csharp
public class SummonWheelView : UIView
{
    public VisualElement summonWheelCanvas;
    public MButton closeButton;
    // 按钮由 Panel 通过 root.Q<MButton>("btn-slot{N}") 动态查询
    // View 只持有容器和关闭按钮，保持数据驱动一致性
}
```

### 3.5 UXML 布局

参考 PoseWheel.uxml 结构，简化为2个扇区：

```xml
<ui:UXML xmlns:ui="UnityEngine.UIElements" mui="FL.Framework.UI">
    <ui:VisualElement name="canvas-summonWheel" picking-mode="Ignore">
        <FL.Framework.UI.MButton name="btn-close" />
        <ui:VisualElement name="centerCon">
            <ui:VisualElement name="border" />
            <FL.Framework.UI.MButton name="btn-slot1" selected="false">
                <ui:VisualElement name="slot1Icon" />
                <FL.Framework.UI.MLabelPro name="txt-slot1" value="召唤狗" />
            </FL.Framework.UI.MButton>
            <FL.Framework.UI.MButton name="btn-slot2" selected="false">
                <ui:VisualElement name="slot2Icon" />
                <FL.Framework.UI.MLabelPro name="txt-slot2" value="叫车" />
            </FL.Framework.UI.MButton>
        </ui:VisualElement>
    </ui:VisualElement>
</ui:UXML>
```

### 3.6 UIConfig.json 条目

```json
{
    "name": "SummonWheel",
    "panels": [
        {
            "name": "SummonWheel",
            "group": 1,
            "level": 0,
            "showMode": 0,
            "effects": [],
            "folder": "SummonWheel"
        }
    ],
    "widgets": []
}
```

### 3.7 InputSystem 注册

PlayerControls.inputactions 中在 UIOperation/Vehicle/PhotoMode action maps 添加：
```json
{
    "name": "OpenSummonWheelPanel",
    "type": "Button",
    "id": "<new-guid>",
    "expectedControlType": "",
    "processors": "",
    "interactions": "",
    "initialStateCheck": false
}
```

绑定：`"path": "<Keyboard>/o"`, `"action": "OpenSummonWheelPanel"`

InputEventId.cs：`public const string OpenSummonWheelPanel = "OpenSummonWheelPanel";`

## 4. 错误处理

- 召唤狗失败（错误码14005=附近没狗）：显示失败提示，不关闭轮盘
- 召唤狗冷却中：忽略点击
- PhoneMyCarPanel 打开失败：日志记录，不影响轮盘

## 5. 验收测试方案

[TC-001] 快捷键打开/关闭轮盘
前置条件：已登录游戏，在 HUD 界面
操作步骤：
  1. [MCP script-execute] 模拟按键 O
  2. [验证] screenshot-game-view 确认轮盘显示，2个扇区可见
  3. [MCP script-execute] 再次按 O 或点击关闭
  4. [验证] screenshot-game-view 确认轮盘关闭

[TC-002] 召唤狗扇区
前置条件：轮盘已打开
操作步骤：
  1. [MCP script-execute] 模拟点击召唤狗扇区
  2. [验证] console-get-logs 确认 SummonDogReq 已发送
  3. [验证] screenshot-game-view 确认轮盘关闭（成功时）

[TC-003] 叫车扇区
前置条件：轮盘已打开
操作步骤：
  1. [MCP script-execute] 模拟点击叫车扇区
  2. [验证] screenshot-game-view 确认召唤轮盘关闭且 PhoneMyCarPanel 打开

[TC-004] 编译验证
操作步骤：
  1. [MCP console-get-logs] 确认无 CS 编译错误
