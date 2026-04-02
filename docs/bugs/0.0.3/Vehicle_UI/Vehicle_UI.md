# Vehicle_UI Bug 追踪

## Bug 列表

- [x] **BUG-001**: 征用汽车后驾驶操作面板按钮位置不正确，靠得太近
  - 现象：VehicleControlWidget 的按钮全部挤在屏幕右半部分小区域，间距极窄
  - 根因：Widget 被放在 ControlPanel 的 contentGroup（半屏宽 ~1099px）内，但 CSS 按钮位置为全屏宽度（~2078px）设计
  - 影响：所有 Mobile 平台驾驶汽车时
  - 发现日期：2026-03-30
