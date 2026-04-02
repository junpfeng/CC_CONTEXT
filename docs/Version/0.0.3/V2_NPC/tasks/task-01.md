---
name: REQ-001 性别Prefab选择
status: completed
---

## 范围
- 修改: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/BigWorldNpcController.cs
  — 读取 NpcData.BaseInfo.Gender，新增 `SelectPrefabByGender(gender)` 私有方法；Male→NewNpcPrefab，Female→NewNpcPrefab_Female，Unknown/缺失→NewNpcPrefab（男性兜底）；实例化调用改为使用该方法返回值；若 Prefab 引用方式为 Inspector 直接引用则补 `[SerializeField] NewNpcPrefab_Female`，若为 AssetKey 字符串则补 `_femalePrefabKey` 常量（阅读现有代码后确定）
- 修改（按需）: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcAppearanceComp.cs
  — 若 Prefab 引用维护在 AppearanceComp 中，在此添加女性 Prefab 引用；若完全在 Controller 中则跳过

## 验证标准
- 客户端无 CS 编译错误（console-get-logs）
- MCP 脚本注入 Gender=Female 的 NPC，反射确认 Prefab 实例为 NewNpcPrefab_Female
- MCP 脚本注入 Gender=Male 及 Gender=Unknown 的 NPC，确认回退到 NewNpcPrefab
- 切换场景后重新进入大世界，女性 NPC 仍正确显示
- TownNpcController 无任何代码变动（grep 确认）

## 依赖
- 无
