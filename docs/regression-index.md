# 回归检测索引

push hook 在推送前读取本文件，匹配变更文件路径，检查关联 feature 的验收状态。

## 使用方式

1. push hook 通过 `git diff --name-only` 获取变更文件列表
2. 逐行匹配下方"共享模块 → Feature 映射"表的模块路径模式
3. 命中的 feature → 检查其 `docs/version/*/{{feature}}/acceptance-report.md` 是否存在 FAIL/UNRESOLVED
4. 有风险 → 输出 WARNING（不阻塞推送）

## 共享模块 → Feature 映射

| 模块路径模式 | 关联 Feature | 关键验收项 |
|-------------|-------------|-----------|
| freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Npc/ | V2_NPC | NPC 生成/同步/动画 |
| freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Animation/ | V2_NPC, animal_system | 动画状态机/层管理 |
| freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Traffic/ | traffic_system | 交通车辆行驶/避让 |
| freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Animal/ | animal_system | 动物生成/喂食 |
| P1GoServer/servers/scene_server/internal/npc/ | V2_NPC | NPC 服务端逻辑 |
| P1GoServer/servers/scene_server/internal/big_world/ | V2_NPC, traffic_system, animal_system | 大世界场景管理 |
| old_proto/ | (ALL) | 协议兼容性 |
| freelifeclient/Assets/Scripts/Gameplay/Config/Gen/ | (ALL) | 配置表生成代码 |

> 此表由开发过程中持续维护。新 feature 完成验收后，将其依赖的共享模块添加到此表。
> auto-work / dev-workflow 的 P7 经验沉淀阶段应检查是否需要更新此索引。
