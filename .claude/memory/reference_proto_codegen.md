---
name: Proto 代码生成工具
description: 自定义 protobuf 代码生成工具的位置、用法、配置和编码规则
type: reference
---

## 工具位置

`old_proto/_tool_new/` 目录下：
- `proto_gen.exe` / `proto_gen` — 核心生成器（读取 .proto 文件，输出 Go/C# 代码）
- `1.generate.py` — Python 包装脚本，调用 proto_gen 后将生成文件复制到目标目录
- `generate.exe` — PyInstaller 打包的 1.generate.py
- `dir_file` — 输出路径配置（需手动创建，参考 `dir_file.example`）

## 源 Proto 文件

源文件在 `old_proto/` 子目录下（如 `old_proto/scene/scene.proto`、`old_proto/base/base.proto`）。
`P1GoServer/resources/proto/` 是 git submodule 但**未参与构建**（历史遗留，禁止修改）。

修改协议时，**只改 `old_proto/`**，然后运行 `1.generate.py` 自动分发到各工程。

## 生成输出

生成器先输出到 `old_proto/_tool_new/` 下的临时目录，再由 Python 脚本复制到目标：
- C# 代码 → `freelifeclient/Assets/Scripts/Gameplay/Managers/Net/Proto/`
- Go Proto → `P1GoServer/common/proto/`
- Logic 服务 → `P1GoServer/servers/logic_server/internal/service/`
- Scene 网络函数 → `P1GoServer/servers/scene_server/internal/net_func/`
- Scene 服务 → `P1GoServer/servers/scene_server/internal/service/`

## Tag 编码规则（自定义格式，非标准 protobuf）

本项目使用自定义的 proto 编码，tag 格式为 3 字节：

| Wire Type | Tag 格式 | 示例 |
|-----------|----------|------|
| varint (int32, bool, enum) | `0x01_XX_01` | field 9 bool → tag = 0x010901 = 67841 |
| message (嵌套消息) | `0x10_XX_04` | field 1 message → tag = 0x100104 |
| repeated message | `0x41_XX_04` | field 1 repeated msg → tag = 0x410104 |

其中 XX = field number。

## 手动修改生成代码的要点

如果不运行工具而是手动修改 `*_pb.go` / `*.pb.cs`，需同步修改以下方法：
- **Go**: struct 字段、String()、Equal()、Unmarshal()（case tag）、Size()、Marshal()
- **C#**: 字段声明、CloneFrom()、Unmarshal(byte[])、Unmarshal(byte*)、Size()、MarshalTo()、Clear()
