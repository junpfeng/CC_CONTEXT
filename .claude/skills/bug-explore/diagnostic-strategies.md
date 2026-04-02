# 诊断策略表

根据 bug 描述中的关键词选择诊断动作。可同时命中多条策略。

## 如何新增策略

在下方表格末尾（"无明显关键词" 行之前）添加新行即可。格式：

```
| **关键词1 / 关键词2** | ① 动作1 ② 动作2 ③ 动作3 | 使用的工具 | 0 | 0 |
```

每条策略建议 2-3 个诊断动作，按信息价值从高到低排列。上限 25 条（满时替换有效率最低的一条）。

## 进化规则

- `命中次数`：Phase 1 匹配到该策略时 +1
- `有效次数`：该策略采集的证据被 dev-debug 修复过程引用时 +1
- 命中 ≥5 且有效率 <20% → 标记低效 → 下次自反馈替换或删除
- 详见 `metrics-schema.md`

---

| 关键词 | 诊断动作 | 工具 | 命中 | 有效 |
|--------|----------|------|------|------|
| **NPC / 怪物 / 路人 / 行人** | ① Game View 截图 ② 打开小地图 + 开启 NPC 图例 Toggle 后截图 ③ 读取 NPC Manager 运行时数据（NPC 数量、状态分布） | MCP screenshot + script-execute | 0 | 0 |
| **小地图 / 地图 / 图例 / 标记** | ① 打开 MapPanel ② 逐个 Toggle 图例类型并截图 ③ 读取 MapManager 状态 | MCP script-execute + screenshot | 0 | 0 |
| **车 / 交通 / 载具 / 红绿灯** | ① Game View 截图 ② 读取 TrafficManager 运行时数据（车辆数、信号灯状态） ③ 服务端 vehicle spawn 日志 | MCP script-execute + Grep srv_log | 0 | 0 |
| **动画 / 动作 / 播放 / 卡住 / 抽搐 / 滑步** | ① Game View 截图 ② 等 2s 再截第二张（对比两帧变化） ③ 读取 Animator/Animancer 当前 State + 层权重 | MCP screenshot ×2 + script-execute | 0 | 0 |
| **UI / 面板 / 按钮 / 界面 / 弹窗** | ① Game View 截图（含 UI 层） ② 用 script-execute 遍历当前打开的 UIPanel 列表 ③ 检查 UIManager 面板栈 | MCP screenshot + script-execute | 0 | 0 |
| **移动 / 寻路 / 走不动 / 穿墙 / 卡墙** | ① Game View 截图 ② 读取玩家/NPC 的 Position + NavAgent 状态 ③ 读取 pathfinding 最近错误 | MCP script-execute + screenshot | 0 | 0 |
| **崩溃 / 闪退 / 报错 / Exception** | ① Unity Console 最近 30 条 Error ② 服务端最近 50 行 ERROR 日志 ③ Editor.log 尾部 100 行 | MCP console-get-logs + Grep + Read | 0 | 0 |
| **卡顿 / 掉帧 / 性能 / 发热** | ① 读取 FPS + 内存 + SetPass Calls ② 服务端 pprof goroutine 概览 ③ 5s 后再读一次 FPS（对比趋势） | MCP script-execute ×2 + curl pprof | 0 | 0 |
| **数据 / 存档 / 丢失 / 回档** | ① 服务端最近 ERROR 日志 ② 读取当前登录角色 ID 后查 MongoDB ③ Redis 缓存状态 | Grep srv_log + Bash db_query | 0 | 0 |
| **网络 / 断线 / 延迟 / 同步** | ① Unity Console 网络相关日志（grep "disconnect\|timeout\|reconnect"） ② 服务端 gateway 日志 ③ 读取 NetManager 连接状态 | MCP console-get-logs + Grep + script-execute | 0 | 0 |
| **声音 / 音效 / 音乐** | ① 读取 AudioManager 当前播放列表 ② 检查音量设置 ③ 服务端无关，跳过 | MCP script-execute | 0 | 0 |
| **数值 / 属性 / 配置 / 伤害 / 经验 / 掉落** | ① 读取相关配置表（Excel MCP `excel_read_sheet`） ② 服务端对应 handler 日志（grep ERROR + 模块名） ③ 运行时读取实体属性值（script-execute） | MCP excel_read + Grep + script-execute | 0 | 0 |
| **登录 / 账号 / 卡登录 / 连不上 / 进不去** | ① 服务端 gateway 日志（grep "login\|auth\|connect"） ② Unity Console 网络相关日志 ③ 读取 NetManager 连接状态和登录阶段 | Grep srv_log + MCP console-get-logs + script-execute | 0 | 0 |
| **无明显关键词** | ① Game View 截图 ② Unity Console 最近 10 条 Error ③ 服务端最近 20 行 ERROR | MCP screenshot + console-get-logs + Grep | 0 | 0 |
