# 工作空间跨工程闭环 Review

> 审查日期: 2026-03-12

## 依赖拓扑

```
old_proto (协议源)
  ├──[生成 C#]──→ freelifeclient/Assets/Scripts/Gameplay/Managers/Net/Proto/  (23 个 .pb.cs)
  ├──[生成 Go] ──→ P1GoServer/common/proto/、common/db_data/、common/errorx/、servers/*/
  └──[submodule]──→ P1GoServer/resources/proto/

freelifeclient/RawTables/_tool (打表)
  ├──[客户端代码]──→ freelifeclient/Assets/Scripts/Gameplay/Config/Gen/
  ├──[客户端数据]──→ freelifeclient/Assets/PackResources/Config/Data/
  ├──[Go 代码]  ──→ P1GoServer/common/config/
  └──[Go 数据]  ──→ P1GoServer/bin/config/

freelifeclient (运行时)
  └──[网络连接]──→ P1GoServer (通过 appConfig.json 多环境配置)
```

## 闭环检查

### 1. 协议流 (old_proto → 客户端 + 服务器)

| 检查项 | 状态 | 说明 |
|--------|------|------|
| Proto → C# 客户端 | ✅ | `_tool_new/dir_file` → `freelifeclient/.../Proto/`，23 个文件最新 |
| Proto → Go 服务器 | ✅ | 7 个 TARGET_GO_* 路径覆盖 proto/db/service/cache 等 |
| submodule 同步 | ⚠️ | P1GoServer/resources/proto 是 old_proto 的 submodule，需手动 `git submodule update` |
| 错误码特殊流 | ✅ | Excel → cfg_errorcode.bytes → codes.proto → codes_pb.go → errorx/ |

### 2. 配置流 (RawTables → 客户端 + 服务器)

| 检查项 | 状态 | 说明 |
|--------|------|------|
| → 客户端 C# 代码 | ✅ | `../../Assets/Scripts/Gameplay/Config/Gen` 路径存在 |
| → 客户端二进制 | ✅ | `../../Assets/PackResources/Config/Data` 路径存在 |
| → Go 配置代码 | ✅ | `../../P1GoServer/common/config` 路径存在 |
| → Go 配置数据 | ✅ | `../../P1GoServer/bin/config` 路径存在（本次修复） |
| TARGET_SERVER_CODE | 🗑️ | 旧 Rust 路径，目标不存在，脚本自动跳过，无影响 |

### 3. 编译流

| 检查项 | 状态 | 说明 |
|--------|------|------|
| P1GoServer `make build` | ✅ | 构建 16 个微服务，依赖 common/config + common/proto 均由工具生成 |
| freelifeclient Unity 编译 | ✅ | 依赖 Config/Gen + Proto/ 均由工具生成 |

### 4. 起服流

| 检查项 | 状态 | 说明 |
|--------|------|------|
| 服务器运行时配置 | ✅ | P1GoServer/bin/config/ 包含 JSON/bytes 数据文件 |
| 客户端连接配置 | ✅ | appConfig.json 含 4 个环境地址，运行时按环境切换 |

## 发现的问题

### [已修复] TARGET_SERVER_BYTES 路径错误
- **文件**: `freelifeclient/RawTables/_tool/dir_file`
- **原值**: `Y:/dev/config`（网络驱动器，不存在）
- **修复**: `../../P1GoServer/bin/config`（与顶层 RawTables 一致）

### [已修复] old_proto/_tool_new/dir_file 缺失
- 原本只有 `dir_file.example`，无实际 `dir_file`
- 已从 example 创建，并删除了死掉的 `TARGET_SERVER_CODE`（旧 Rust 路径）
- 保留 3 个有效路径：TARGET_CLIENT_CODE、TARGET_CLIENT_DATA_CODE、TARGET_GO_CODE

### [已修复] CLAUDE.md 打表路径描述不准确
- 原描述"客户端路径为绝对路径，因机器而异"，实际 dir_file 中全部为相对路径
- 输出目标列使用了 `{客户端工程}` 占位符，已改为与 dir_file 一致的相对路径
- 补充说明路径相对于 `_tool/` 目录
