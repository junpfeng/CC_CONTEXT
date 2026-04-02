---
name: 客户端小地图 NPC 图例
status: discarded
---

## 范围
- 新增: freelifeclient/Assets/Scripts/Gameplay/Modules/UI/Managers/Map/TagInfo/MapBigWorldNpcLegend.cs — 继承 MapLegendBase，大世界 NPC 图例数据类。统一人形图标（icon_npc_common），浅蓝色 #87CEEB，edgeDisplay=0（不显示边缘指示器）
- 修改: freelifeclient/Assets/Scripts/Gameplay/Modules/UI/Managers/Map/TagInfo/MapLegendControl.cs — 新增 BigWorldNpcLegendTypeId=127 常量；新增 ToggleShowAllBigWorldNpc() 方法（Toggle on 遍历 DataManager.Npcs 添加图例 / Toggle off 清除）；订阅 NPC 创建/销毁事件自动增删图例（OnClose 中取消订阅）；OnOpen 时检查 CitySceneInfo.IsBigWorld，非大世界场景隐藏按钮

## 验证标准
- Unity 编译无 CS 错误
- MapBigWorldNpcLegend 正确继承 MapLegendBase
- Toggle on/off 功能逻辑完整
- 事件订阅/取消成对出现（防泄漏）
- 非大世界场景按钮不显示
- 日志无 $"" 插值（lesson-003）
- 新建 .cs 文件有 using UnityEngine

## 依赖
- 无（客户端可独立编译）
