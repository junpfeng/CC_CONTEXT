# Vehicle_Call 修复记录

## 叫车面板不出现且角色卡死

**日期**: 2026-04-01

**根因**: `PhoneDailingPanel.CheckCanCallCar()` 成功路径中，三个异步操作通过 `.Forget()` 并发执行导致竞态：
1. `UIManager.Open<VehicleCallPanel>().Forget()` — 打开叫车面板（异步网络请求）
2. `UIManager.Close(PanelEnum.PhoneDailing).Forget()` — 关闭拨号面板 → 触发 OnClose → TryClosePhone
3. `MuiTool.Phone.TryClosePhone().Forget()` — 关闭手机

`TryClosePhone` 退出 PhoneMode + 隐藏光标 + 进入 DisableAllMode 动画，与 `VehicleCallPanel.Open` 重入 PhoneMode + 显示光标竞态，导致输入模式栈不一致，面板不可见但 PhoneMode 锁定移动。

**修复方案**: `PhoneDailingPanel.cs`
- 新增 `_skipClosePhone` 标志，成功路径设置后跳过 OnClose 中的 `CloseDailingAndPhone()`
- 新增 `OpenVehicleCallAfterPhoneClose()` 方法，顺序执行 `await TryClosePhone()` → `await UIManager.Open<VehicleCallPanel>()`
- 确保手机完全关闭（动画完成、输入模式恢复）后再打开叫车面板

**验证**: MCP 运行时验证
- 触发叫车流程 → PhoneOpen=False → VehicleCallPanel 打开 → 模式栈 [DefaultMode, PhoneMode]
- 关闭叫车面板 → 模式栈 [DefaultMode] → 移动恢复正常
