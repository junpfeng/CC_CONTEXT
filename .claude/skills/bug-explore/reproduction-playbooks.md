# 主动复现策略与诊断脚本规范

## 前置条件：确认已登录

执行任何主动操作前，先通过 `/unity-login` skill 确认已登录进游戏。未登录则先完成登录流程，再继续采集和复现。

## 玩家角色控制

通过 MCP script-execute 操控玩家角色，C# 模板见 `csharp-templates.md`。

## GM 指令系统

通过客户端 `NetCmd.GmOperate` 发送 GM 指令。格式：`/ke* gm <command> <params>`

**可用 GM 指令**：运行时从源码获取最新列表，不维护静态表。

```bash
# 查看所有已注册的 GM 指令
grep -rn 'case "' --include='*.go' P1GoServer/servers/scene_server/internal/net_func/gm/ | sed 's/.*case "//;s/".*//'
```

**常用指令速查**（可能过时，以 grep 结果为准）：
- `teleport <x> <y> <z>` — 传送
- `bigworld_npc_spawn <count>` / `bigworld_npc_clear` / `bigworld_npc_info <cfgId>` — NPC 调试
- `set_time <params>` — 游戏时间
- `jump_to_task` — 任务跳转

**如果缺少需要的 GM 指令**：直接在 `P1GoServer/servers/scene_server/internal/net_func/gm/` 下新增 handler，在 `gm.go` switch 中注册，编译后重启服务端生效。

## 主动复现策略表

根据 bug 类型组合操作序列来精准复现：

| Bug 类型 | 复现操作序列 |
|----------|-------------|
| **NPC 不出现/消失** | ① 传送到 NPC 密集区 ② `bigworld_npc_spawn 10` 强制生成 ③ 截图 ④ 等 30s 再截图对比 ⑤ `bigworld_npc_info` 查状态 |
| **NPC 行为异常（原地踏步/不动）** | ① 传送到目标 NPC 附近 ② 截图 ③ 等 5s 截图对比 ④ 读取 NPC State + AnimState ⑤ `bigworld_npc_info <cfgId>` |
| **动画卡住/错乱** | ① 截图 ② 等 3s 截图 ③ 读取 Animancer 所有层的 State + Weight ④ 读取 FSM 当前状态 |
| **交通/车辆问题** | ① 传送到有车路段 ② 截图 ③ 读取 TrafficManager 车辆列表 ④ 等 10s 截图对比（车是否在动） |
| **位置/碰撞问题** | ① 读取玩家位置 ② 传送到 bug 位置附近 ③ 模拟移动操作 ④ 连续 3 次读取位置确认是否卡住 |
| **任务/剧情问题** | ① `jump_to_task` 跳到对应阶段 ② 执行触发操作 ③ 截图 + 读日志 |
| **性能问题** | ① 读 FPS ② 传送到不同区域各读一次 ③ `bigworld_npc_spawn 50` 加压 ④ 再读 FPS 对比 |
| **时间相关** | ① `set_time` 切换到 bug 发生的时间段 ② 观察并截图 |

## 复合诊断脚本编写原则

脚本模板中的 API 路径随版本频繁变化，**编写前必须 grep 确认当前类名和方法签名**，禁止凭记忆硬编码。

**编写流程**：
1. 从 bug 描述确定诊断目标（如"读取 NPC 数量"）
2. `grep -rn "关键类名或方法名" --include="*.cs"` 确认当前 API 路径
3. 基于 grep 结果编写 script-execute 脚本，引用确认后的类名和方法签名
4. FPS / 内存等 Unity 固定 API 无需 grep：`1f / Time.unscaledDeltaTime`、`Profiler.GetTotalAllocatedMemoryLong() / 1048576`

**多帧对比采样**（动画/移动类 bug）：
先截图 → 等 2-3s → 再截图，两张图展示给用户对比。如果两帧画面完全相同，说明目标卡住/冻结。
