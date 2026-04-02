# 已修复 Bug 记录 - V2_NPC（0.0.2）

## 2026-03-28
- [x] 大世界看不到任何NPC，点击小地图中NPC的图例也没有在小地图中显示NPC的位置
  - **根因**：`CreateDynamicBigWorldNpc` 创建实体时漏挂 `AnimStateComp`，导致 V2 管线动画状态永不推送，客户端以 `ServerAnimStateData==null` 过滤所有 BigWorld NPC，实体字典始终为空
  - **修复**：
    - `P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/scene_npc_mgr.go`：`CreateDynamicBigWorldNpc` 中补加 `entity.AddComponent(csystem.NewAnimStateComp())`
    - 客户端无需修改，服务端修复后小地图图例自动恢复（根因 B 是根因 A 的传导结果）
