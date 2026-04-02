# knowledge/ 索引

> 工作空间中各工程相关的领域知识统一管理入口，按需加载。

## 使用说明

- 每个文件对应一类知识领域，按工程或主题组织
- Skill（如 dev-debug、dev-workflow）在执行过程中根据上下文按需读取
- 新增文件后在下方索引表中登记，便于检索

## 索引

| 文件 | 摘要 | 关键词 |
|------|------|--------|
| [`p1goserver-gateway.md`](p1goserver-gateway.md) | Gateway 网关服务：架构设计、消息路由、连接管理、事件系统 | Go, Gateway, 网关, 消息转发, 连接管理 |
| [`p1goserver-protocol.md`](p1goserver-protocol.md) | 协议解析与处理：帧格式、序列化、路由分发、代码生成、请求响应流程 | Go, 协议, TCP, 二进制, varint, RPC |
| [`p1goserver-login.md`](p1goserver-login.md) | 登录服务：认证流程、Token 机制、网关分配、安全机制、数据存储 | Go, 登录, Token, Firebase, TapTap, OAuth |
| [`p1goserver-npc-framework.md`](p1goserver-npc-framework.md) | NPC AI 框架：V1（GSS 决策+行为树）+ V2 BigWorld（正交维度 Pipeline+Spawner+四维度 Handler） | Go, NPC, AI, 行为树, GSS, V2Pipeline, BigWorld, 感知, 日程 |
| [`freelifeclient-npc.md`](freelifeclient-npc.md) | 客户端 NPC 系统：TownNpc/SakuraNpc/BigWorldNpc 生命周期、状态机、组件、对象池、LOD、断线重连 | Unity, NPC, FSM, BigWorld, 对象池, LOD, Animancer |
| [`client-vehicle.md`](client-vehicle.md) | 客户端载具系统：实体架构、多类型物理控制、玩家交互、AI 驾驶、网络同步、视觉特效 | Unity, 载具, 物理, AI, 座位, WheelCollider |
| [`server-vehicle.md`](server-vehicle.md) | 服务器载具系统：ECS 数据结构、网络协议、权限模型、交通载具管理、持久化与商业 | Go, 载具, ECS, 座位, 网络同步, 商店 |
| [`error-patterns.md`](error-patterns.md) | 错误模式库：已知典型错误的症状→根因→解法，由 dev-debug Phase 4 渐进积累 | 调试, 错误模式, bug, EP |
| [`debug-guide.md`](debug-guide.md) | 调试指南：客户端日志系统（MLog、CrashSight、CLS、TapSDK）路径与采集方式 | 调试, 日志, MLog, 崩溃, CLS |
| [`bigworld-traffic.md`](bigworld-traffic.md) | 大世界交通系统：路网图索引、A*寻路、车辆生成、自主巡航、信号灯/人格/变道框架 | 交通, GTA5, A*, 路网, 寻路, 车辆生成, Miami |
