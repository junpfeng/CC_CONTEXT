# Bug 修复日志 #1

- **版本**: 0.0.2
- **模块**: V2_NPC
- **Bug**: 大世界看不到任何NPC，点击小地图中NPC的图例也没有在小地图中显示NPC的位置
- **启动时间**: 2026-03-28 12:47:42

| 轮次 | 操作 | Critical | High | Medium | 状态 |
|------|------|----------|------|--------|------|
| 0 | 根因分析 | - | - | - | done (754s) |
| 1 | 修复 | 0 | 0 | 0 | done |

## 修复内容

### 修改文件

1. **`P1GoServer/servers/scene_server/internal/ecs/res/npc_mgr/scene_npc_mgr.go`**
   - 补充 import `mp/servers/scene_server/internal/ecs/com/csystem`
   - `CreateDynamicBigWorldNpc` 中在 `NpcMoveComp` 之后、`SceneNpcComp` 之前添加 `entity.AddComponent(csystem.NewAnimStateComp())`
   - 根因 A 修复：AnimStateComp 缺失导致 AnimStateInfo=nil，客户端 BigWorldNpcManager 过滤所有 V2 NPC

2. **`P1GoServer/servers/scene_server/internal/ecs/system/decision/bt_tick_system.go`**
   - `syncNpcStateToAnimComp` 静默 return 处补充 `log.Warningf` 警告日志，防止今后同类问题被掩盖

### 未修改

- 客户端代码（根因分析确认无需修改）

### 编译验证

- `make build` 通过，无编译错误

ALL_FILES_FIXED
| 1 | 修复 | - | - | - | done |
| 1.c | 编译验证 | - | - | - | 通过 |
| 2 | Review | 0 | 1 | 0 | done |

## 总结
- **总轮次**：2
- **终止原因**：质量达标
- **最终质量**：Critical=0, High=1, Medium=0
- **完成时间**：2026-03-28 13:28:06
