---
name: 协议定义与代码生成
status: pending
---

## 范围
- 修改: old_proto/base/codes.proto — 在 enum Codes 中新增 Error14005=14005（附近无狗）和 Error14006=14006（召唤异常）
- 修改: old_proto/scene/npc.proto — 新增 SummonDogReq（空消息）和 SummonDogRes（code uint32 + animal_id uint64）消息定义
- 修改: old_proto/scene/scene.proto — 注册 SummonDog RPC 路由
- 运行: old_proto/_tool_new/1.generate.py — 生成双端代码（服务端 proto Go 文件 + 客户端 C# 文件 + 错误码 + service 路由）

## 验证标准
- 生成脚本执行无报错
- P1GoServer `go build ./...` 编译通过（新生成的 proto Go 代码无语法错误）
- 客户端生成的 C# 代码无编译错误（通过 Unity MCP console-get-logs 检查）
- SummonDogReq/SummonDogRes 在生成产物中存在且字段正确

## 依赖
- 无
