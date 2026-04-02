---
name: 服务端召唤逻辑
status: pending
---

## 范围
- 新增: P1GoServer/servers/scene_server/internal/net_func/npc/summon_dog.go — SummonDog RPC handler，包含：
  - 服务端 2s 冷却（复用 animal_feed cooldown 模式，sync.Mutex + map[uint64]int64）
  - 玩家 BehaviorState 前置检查（Dead/InVehicle 等不可交互状态返回 Error14006）
  - 获取玩家 Transform，遍历场景 NPC 筛选 ExtType=Animal && AnimalType=Dog
  - XZ 平面距离平方排序，取 ≤50m 最近可用狗（FollowTargetID==0 或 ==当前玩家）
  - 短路优化：已跟随的狗是最近狗时直接返回成功
  - 清除旧狗跟随（遍历查找 FollowTargetID==playerEntityId 的狗，清零 + SetSync）
  - 设置新狗 FollowTargetID + BehaviorState=Follow + SetSync
  - 玩家离线时清理 cooldown map 条目
  - 常量：summonDogMaxDistSq=2500.0, summonDogCooldownSec=2

## 验证标准
- `go build ./...` 在 P1GoServer 目录编译通过
- handler 函数签名与生成的 service 路由匹配
- 参考 animal_feed.go 确认模式一致（错误处理、日志、cooldown）

## 依赖
- 依赖 task-01（需要生成的 proto 消息定义和 service 路由）
