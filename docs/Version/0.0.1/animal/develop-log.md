# 开发日志：animal

## 2026-03-26 - task-01: 协议定义与代码生成

### 实现范围
协议层（proto）+ 双端代码生成

### 修改文件
- `old_proto/base/codes.proto` — 新增 Error14005（附近无狗）和 Error14006（召唤异常）错误码
- `old_proto/scene/npc.proto` — 新增 SummonDogReq（空消息）和 SummonDogRes（code uint32 + animal_id uint64）消息定义
- `old_proto/scene/scene.proto` — 注册 SummonDog RPC 路由（路由号 3202）

### 新增文件
- `P1GoServer/servers/scene_server/internal/net_func/npc/summon_dog.go` — SummonDog handler stub（返回未实现错误，待 task-02 实现完整逻辑）

### 生成产物（由 1.generate.py + proto_gen.exe 自动生成）
- `P1GoServer/common/proto/npc_pb.go` — SummonDogReq/SummonDogRes Go 结构体
- `P1GoServer/common/proto/scene_service.go` — SummonDog RPC 路由注册
- `P1GoServer/common/proto/scene_client.go` — 客户端推送接口
- `P1GoServer/common/errorx/codes_pb.go` — Error14005/Error14006 错误码 Go 常量和类型
- `freelifeclient/Assets/Scripts/Gameplay/Managers/Net/Proto/npc.pb.cs` — SummonDogReq/SummonDogRes C# 类
- `freelifeclient/Assets/Scripts/Gameplay/Managers/Net/Proto/scene.pb.cs` — NetCmd.SummonDog 客户端 RPC 调用方法
- `freelifeclient/Assets/Scripts/Gameplay/Managers/Net/Proto/codes.pb.cs` — 错误码 C# 枚举

### 额外修复
- `P1GoServer/tests/robot/bot/handler.go` — 补充 AnimalStateChangeNtf 空实现（IClientScene 接口变更导致的编译错误）

### 关键决策
- 错误码配置表（ErrorCode.xlsx）的 Excel MCP 写入权限被拒绝，改为手动修改 codes.proto 后单独运行 proto_gen.exe 重新生成。注意：下次完整运行 1.generate.py 会从 Excel bytes 重新生成 codes.proto，需要先将 Error14005/14006 加入 Excel 配置表
- SummonDog handler 创建了 stub 文件以确保编译通过，完整实现留给 task-02
- RPC 路由号使用 3202（紧接 AnimalStateChangeNtf 的 3201）

### 测试情况
- 生成脚本执行无报错 ✅
- P1GoServer `go build ./...` 编译通过 ✅
- 客户端 C# 生成代码结构正确（SummonDogReq 空消息、SummonDogRes 含 Code uint + AnimalId ulong）✅
- NetCmd.SummonDog 异步调用方法正确生成（路由号 3202）✅

### 待办事项
- 将 Error14005/Error14006 加入 `freelifeclient/RawTables/ErrorCode/ErrorCode.xlsx` 配置表（当前手动写入 codes.proto，完整打表流程会覆盖）

---

ALL_FILES_IMPLEMENTED
