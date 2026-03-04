# 武器轮盘业务逻辑实现 — 任务清单

## 业务工程 (P1GoServer/)

### EquipComp 增强
- [ ] [TASK-001] EquipComp 新增 NowWeaponBackpackIndex 字段 + 更新构造函数
- [ ] [TASK-002] 实现 SetWeapon / RemoveWeapon / GetActiveWeapon 方法

### onChooseCommonWheelSlot 核心逻辑
- [ ] [TASK-003] 实现属性操作辅助函数（getWeaponAttribute / setWeaponAttribute）
- [ ] [TASK-004] 实现子弹回收逻辑（onTriggerUnloadWeapon + onWeaponUnloadRecycleBullet + syncWeaponAttributesToBackpack）
- [ ] [TASK-005] 实现 EquipItem 分支
- [ ] [TASK-006] 实现 UnEquipCurItem 分支
- [ ] [TASK-007] 实现 AddonToCurItem 分支

### Handler 改造
- [ ] [TASK-008] AddItemToCommonWheel handler：添加自动选中
- [ ] [TASK-009] AddItemCollectToCommonWheel handler：添加自动选中
- [ ] [TASK-010] RemoveItemFromCommonWheel handler：添加武器卸下逻辑

## 任务依赖

```
TASK-001 → TASK-002 → TASK-005, TASK-006
TASK-003 → TASK-004 → TASK-005, TASK-006, TASK-007
TASK-005, TASK-006, TASK-007 → TASK-008, TASK-009, TASK-010
```

串行执行顺序：001 → 002 → 003 → 004 → 005 → 006 → 007 → 008 → 009 → 010
