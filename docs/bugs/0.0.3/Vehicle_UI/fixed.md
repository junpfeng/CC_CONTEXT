# Vehicle_UI 修复记录

## BUG-001: 征用汽车后驾驶操作面板按钮位置不正确

### 根因
`VehicleControlWidget` 和 `VehicleMotorControlWidget` 在 `ControlPanel.OnCreate()` 中被添加到 `_view.contentGroup`（半屏宽度 ~1099px），但两个 widget 的 USS 按钮位置（如 `right:28px~382px`, `left:120px~360px`）是为全屏宽度（~2078px）设计的。

ControlPanel 的布局设计：左半屏 `gp-camera`（相机操控区域），右半屏 `safeArea/contentGroup`（步行按钮区域）。步行模式的按钮适配了半屏宽度，但车辆控制 widget 的按钮没有，导致所有按钮被压缩到半屏空间中。

### 诊断数据
- 运行时 contentGroup 宽度: 1099px（约半屏）
- 运行时 canvas-control 宽度: 2337px（全屏）
- 设备: iPhone Simulator 2532x1170, SafePadding=130

### 修复方案
将车辆控制 widget 从 `contentGroup` 移至其祖父元素 `canvas-control`（全屏宽度），并设置 `position: absolute` + `width/height: 100%`，使 widget 覆盖全屏。

### 修改文件
- `freelifeclient/Assets/Scripts/Gameplay/Modules/UI/Pages/Panels/ControlPanel.cs`
  - 行 67-80: 将 `_vehicleControlWidget` 和 `_vehicleMotorControlWidget` 的父容器从 `_view.contentGroup` 改为 `_view.contentGroup.parent.parent`（canvas-control 层），并添加 `position: absolute` + 全屏尺寸

### 验证
- 编译通过（零 C# 错误）
- 运行时需在大世界场景征用汽车验证按钮布局
