---
name: Client BigWorldNpcManager 管理器
status: completed
---

## 范围
- 新增: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Managers/BigWorldNpcManager.cs — 大世界 NPC 生命周期 + 对象池管理器，继承 BaseManager。核心职责：
  - **对象池管理**：OnInit 中 async UniTask 预热（YooAsset 异步加载 prefab → 同步 Instantiate pool_size=20 入池），_isReady 标记 + _pendingSpawnQueue 处理竞态
  - **Spawn/Despawn**：接收 NpcDataUpdate 协议驱动 NPC 创建/更新/销毁。分帧 despawn（每帧最多 5 个）
  - **双阶段对象池策略**：回收 OnClear() 释放资源（Cancel Token、解除事件、停动画、Clear SnapshotQueue）；取出 ResetForPool() 初始化状态（FSM ForceState Idle、清零速度、重建 CancellationTokenSource）
  - **LOD 管理**：FULL(<50m) / REDUCED(50-150m) / MINIMAL(>150m) 三档，驱动动画更新频率和插值窗口
  - **断线重连**：pendingValidation 标记 → is_all=true 全量 diff → 超时 5s 清除。正常 despawn 在 pending 窗口内直接执行
  - **场景切换清理**：OnClear() 遍历 entityDict 所有 NPC 执行 Controller.OnClear() → 清空对象池 Destroy → 重置内部状态

## 验证标准
- Unity 编译无 CS 错误
- OnInit/OnClear 配对完整：事件订阅在 OnClear 中全部解除
- 对象池 ResetForPool() 覆盖所有状态字段（FSM/速度/Token/SnapshotQueue）
- EntityId 使用 ulong 类型（非 int）
- 预热期间（_isReady=false）收到的 NPC 生成消息排入 _pendingSpawnQueue，不丢弃
- 不引用 S1Town 命名空间

## 依赖
- 依赖 task-05（Controller 基础框架）
- 依赖 task-06（FSM ForceState 接口用于 ResetForPool）
