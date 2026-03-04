# 协议工程

游戏客户端-服务器通信协议定义（Protocol Buffers 3）。

## 目录结构

```
proto/
  old_proto/          # 协议定义根目录
    module.proto      # 模块枚举定义
    base/             # 基础类型
    cache/            # 缓存服务协议
    chat/             # 聊天服务协议
    db/               # 数据库服务协议
    gateway/          # 网关协议
    logic/            # 核心逻辑协议
    login/            # 登录协议
    manager/          # 场景管理协议
    match/            # 匹配协议
    scene/            # 场景服务协议
    ...               # 其余按服务模块划分
    proto-gen.exe     # 协议代码生成工具（Windows）
```

## 协议命名规范

- 文件名：`<模块名>.proto` 或 `<模块名>_server.proto`（服务端内部）/ `<模块名>_internal_server.proto`（内部 RPC）
- 消息命名：大驼峰（PascalCase）
- 字段命名：小写下划线（snake_case）

## 宪法

1. `proto/old_proto/` 是 git submodule（对应 `P1GoServer/resources/proto/`），修改需在子模块仓库操作
2. 修改 proto 文件后需重新生成 Go 代码（在 P1GoServer 中执行 `make orm`）
3. 新增协议需同时更新 `module.proto` 中的模块注册
4. 客户端和服务端共用同一份协议定义，变更需双端协调
