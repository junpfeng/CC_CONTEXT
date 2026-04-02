---
name: Summon Wheel Design Review
description: 召唤轮盘UI设计审查（2026-03-31），HIGH：缺InputMode/光标管理；MEDIUM：PanelEnum路径错误、View硬编码与数据驱动矛盾
type: project
---

召唤轮盘设计审查，纯客户端UI功能，PASS有条件。

**Why:** 轮盘UI必须有InputMode切换+光标管理，否则鼠标不可见无法选择扇区，这是所有现有轮盘的共同模式。

**How to apply:** 审查轮盘类UI设计时，检查InputMode/光标管理是标配项。PanelEnum注册时注意项目有两个PanelEnum文件（RUI/AutoGen vs Gameplay/Config/UIPanelEnum），正确目标是后者。
