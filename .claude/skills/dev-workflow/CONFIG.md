# 配置工程规范

本文档包含配置工程的目录结构、打表工具使用方法、部署流程和常见问题排查。

---

## 文档概述

| 内容 | 使用时机 |
|------|----------|
| 目录结构与文件分类 | Phase 2 配置设计 |
| 打表工具使用 | Phase 4 实现、配置修改后部署 |
| JSON 配置直通文件 | AI 决策、行为树等 JSON 配置修改 |
| 常见问题排查 | Phase 5 构建测试、运行时问题定位 |

### 相关文档

| 文档 | 用途 |
|------|------|
| `PROTO.md` | 协议工程修改规范 |
| `DB.md` | 数据库架构和存储限制 |
| `NPC.md` | NPC 系统架构（涉及 AI Decision JSON 配置）|

---

# 第一部分：工程结构

## 1. 工程位置

| 工程 | 路径 | 说明 |
|------|------|------|
| 配置工程（源） | `config/RawTables/` | Excel 配置表 + JSON 配置 |
| 打表工具 | `config/RawTables/_tool/` | 生成器、脚本、staging 目录 |
| Go 代码产物 | `P1GoServer/common/config/` | 生成的 `cfg_*.go` 加载器 |
| 服务器运行时配置 | `server_old/bin/config/` | 服务器实际读取的 `.bytes` 和 `.json` |

## 2. 目录结构

```
config/RawTables/
├── _tool/                    # 打表工具（详见第二部分）
├── Json/                     # JSON 直通配置（不经过 config_gen 转换）
│   ├── Server/               # 服务端专用
│   │   ├── ai_decision/      # NPC AI 决策状态机
│   │   ├── behavior_trees/   # 行为树定义（由 BT 系统加载，非此工程管理）
│   │   ├── physics/          # 物理配置
│   │   └── ...
│   ├── Client/               # 客户端专用
│   └── Global/               # 客户端和服务端共享
├── TownNpc/                  # NPC 配置表（Excel）
├── TownTask/                 # 任务配置表
├── Data_Item/                # 物品数据
├── *.xlsx                    # 根级 Excel 配置表
└── config_gen.exe            # Windows 版打表工具（PE32+）
```

## 3. 文件分类

### 3.1 Excel 配置表（需打表生成）

| 来源 | 工具 | 产物 |
|------|------|------|
| `RawTables/*.xlsx` | config_gen | `.bytes`（二进制数据）+ `cfg_*.go`（Go 加载器）|
| `RawTables/*/​*.xlsx` | config_gen | 同上 |

**特点**：Excel 由策划编辑 → config_gen 读取 Excel → 生成 .bytes + .go/.rs/.cs 代码

### 3.2 JSON 直通配置（不需打表生成）

| 来源 | 部署方式 | 说明 |
|------|----------|------|
| `Json/Server/*.json` | 打表脚本直接复制 | 不经过 config_gen 转换 |
| `Json/Global/*.json` | 打表脚本直接复制 | 客户端和服务端共用 |

**特点**：JSON 由程序员或策划手动编辑 → 打表脚本原样复制到目标目录

### 3.3 产物文件（自动生成，不要手动编辑）

| 文件 | 路径 | 说明 |
|------|------|------|
| `cfg_*.go` | `P1GoServer/common/config/` | Go 配置加载代码 |
| `cfg_*.bytes` | `server_old/bin/config/` | 二进制配置数据 |
| `cfg_*.rs` | `server_old/common/src/m_config/` | Rust 配置加载代码（遗留）|

---

# 第二部分：打表工具

## 4. 工具清单

### 4.1 核心工具

| 工具 | 平台 | 路径 | 用途 |
|------|------|------|------|
| `config_gen` | Linux (ELF) | `_tool/config_gen` | 读取 Excel → 生成 .bytes + 代码 |
| `config_gen.exe` | Windows (PE32+) | `RawTables/config_gen.exe` | 同上（Windows 版）|

### 4.2 生成脚本

| 脚本 | 平台 | 配置文件 | 用途 |
|------|------|----------|------|
| **`3.generate_server.py`** | **Linux** | `dir_file_server` | **服务端打表（推荐）** |
| `2.generate_server.py` | Windows | `dir_file_server` | 服务端打表 |
| `1.generate.py` | Windows | `dir_file` | 全量打表（客户端+服务端）|

### 4.3 配置文件

| 文件 | 用途 | 需要修改的场景 |
|------|------|----------------|
| `dir_file_server` | Linux 部署路径配置 | 路径变更时 |
| `dir_file` | Windows 部署路径配置 | Windows 开发时 |
| `dir_file.example` | 路径配置模板 | 新环境首次配置时 |

## 5. 部署路径配置（dir_file_server）

当前 Linux 环境配置：

```
TARGET_SERVER_CODE  = /home/miaoriofeng/workspace/server/server_old/common/src/m_config
TARGET_SERVER_BYTES = /home/miaoriofeng/workspace/server/server_old/bin/config
TARGET_GO_CODE      = /home/miaoriofeng/workspace/server/P1GoServer/common/config
```

对应关系：

```
config_gen 输出          →  部署目标
─────────────────────────────────────────
_tool/code/go/cfg_*.go   →  TARGET_GO_CODE (P1GoServer/common/config/)
_tool/config/server/*.bytes → TARGET_SERVER_BYTES (server_old/bin/config/)
Json/Server/**/*.json    →  TARGET_SERVER_BYTES (server_old/bin/config/)
Json/Global/**/*.json    →  TARGET_SERVER_BYTES (server_old/bin/config/)
```

---

# 第三部分：使用方法

## 6. 修改 Excel 配置后打表

```bash
# 1. 编辑 Excel 文件（策划或程序）
#    例：修改 RawTables/TownNpc/npc.xlsx

# 2. 进入工具目录
cd /home/miaoriofeng/workspace/server/config/RawTables/_tool

# 3. 运行打表（Linux）
echo "" | python3 3.generate_server.py
# 脚本末尾有 input() 等待输入，用 echo "" 管道跳过

# 4. 验证产物
ls -la /home/miaoriofeng/workspace/server/P1GoServer/common/config/cfg_townnpc.go
ls -la /home/miaoriofeng/workspace/server/server_old/bin/config/cfg_townnpc.bytes

# 5. 重新构建服务器
cd /home/miaoriofeng/workspace/server/P1GoServer && make build
```

## 7. 修改 JSON 配置后部署

JSON 直通文件（如 AI 决策配置）不经过 config_gen 转换，但仍需运行打表脚本来复制到服务器运行时目录。

```bash
# 1. 编辑 JSON 文件
#    例：修改 config/RawTables/Json/Server/ai_decision/CustomerNpc_State.json

# 2. 运行打表脚本（会同时复制 JSON 到 server_old/bin/config/）
cd /home/miaoriofeng/workspace/server/config/RawTables/_tool
echo "" | python3 3.generate_server.py

# 3. 验证部署
ls -la /home/miaoriofeng/workspace/server/server_old/bin/config/ai_decision/
```

**注意**：不要手动 `cp` 文件到 `server_old/bin/config/`，始终使用打表脚本部署。

## 8. 打表脚本完整流程

`3.generate_server.py` 按顺序执行以下步骤：

```
1. 读取 dir_file_server（获取部署路径）
2. 清理 staging 目录（_tool/code/、_tool/config/）
3. 执行 ./config_gen（Excel → .bytes + .go/.rs/.cs）
4. 复制 Rust 代码 → TARGET_SERVER_CODE
5. 复制 Go 代码 → TARGET_GO_CODE
6. 复制 Json/Server/ + Json/Global/ → staging（config/server/）
7. 后处理：process_ids.py + replace_gamplay_flag.py
8. 复制 staging → TARGET_SERVER_BYTES
```

如果某个步骤失败（如权限问题），后续步骤不会执行。

---

# 第四部分：服务器配置加载

## 9. 服务器如何加载配置

### 9.1 cfg_dir 配置

服务器通过 `P1GoServer/bin/config.toml` 中的 `cfg_dir` 指定运行时配置目录：

```toml
[global]
# cfg_dir= "config"  # 原来的配置
cfg_dir= "../../server_old/bin/config"
```

**路径解析**：`P1GoServer/bin/` + `../../server_old/bin/config` = `server_old/bin/config/`

### 9.2 两种加载方式

| 类型 | 加载方式 | 示例 |
|------|----------|------|
| .bytes 配置 | `config.NewConfigLoader().LoadAll(cfg_dir)` | cfg_*.bytes → cfg_*.go 加载器 |
| JSON 配置 | 各系统自行读取子目录 | `ai_decision/*.json` → gss_brain config |

### 9.3 AI 决策配置加载链

```
P1GoServer/bin/config.toml
  └── cfg_dir = "../../server_old/bin/config"
        └── ai_decision/
              └── CustomerNpc_State.json
                    ↑
                    │ aidecisionConfig.Init(cfg.Global.ConfigDir)
                    │   → CfgMgr.Parse(configDir + "/ai_decision")
                    │
                    └── initialize.go 启动时加载
```

---

# 第五部分：常见问题

## 10. 权限问题

### 10.1 症状

```
PermissionError: [Errno 1] Operation not permitted: 'code/client/CfgXxx.cs'
```

### 10.2 原因

staging 目录或目标目录中的文件被 root 拥有（通常因为之前用 sudo 运行过脚本）。

### 10.3 修复

```bash
# 修复 staging 目录权限
sudo chown -R $(whoami):$(whoami) /home/miaoriofeng/workspace/server/config/RawTables/_tool/code/
sudo chown -R $(whoami):$(whoami) /home/miaoriofeng/workspace/server/config/RawTables/_tool/config/

# 修复目标目录权限
sudo chown -R $(whoami):$(whoami) /home/miaoriofeng/workspace/server/server_old/bin/config/
sudo chown -R $(whoami):$(whoami) /home/miaoriofeng/workspace/server/server_old/common/src/m_config/
sudo chown -R $(whoami):$(whoami) /home/miaoriofeng/workspace/server/P1GoServer/common/config/
```

### 10.4 预防

永远不要用 `sudo` 运行打表脚本。如果遇到权限问题，先修复文件属主再运行。

## 11. 配置源与运行时不同步

### 11.1 症状

修改了 `config/RawTables/Json/Server/` 下的 JSON 文件，但服务器行为未变化。

### 11.2 原因

服务器从 `server_old/bin/config/` 读取配置，不是从 `config/RawTables/` 读取。

### 11.3 修复

运行打表脚本将修改后的文件部署到运行时目录：

```bash
cd /home/miaoriofeng/workspace/server/config/RawTables/_tool
echo "" | python3 3.generate_server.py
```

### 11.4 验证

```bash
# 对比源文件和部署文件的时间戳或内容
diff config/RawTables/Json/Server/ai_decision/CustomerNpc_State.json \
     server_old/bin/config/ai_decision/CustomerNpc_State.json
```

## 12. 打表脚本中途失败

### 12.1 症状

脚本输出 `config generate finish` 后在 Copy 阶段报错。

### 12.2 原因

通常是目标目录权限问题（见第 10 节）。

### 12.3 影响

脚本按顺序执行：Rust 代码 → Go 代码 → Server 配置。如果 Go 代码复制失败，Server 配置也不会复制。

### 12.4 修复

修复权限后重新运行整个脚本。

---

# 第六部分：关键路径速查

## 13. 常用路径对照表

| 用途 | 源路径（编辑） | 运行时路径（服务器读取） |
|------|----------------|--------------------------|
| NPC 配置表 | `RawTables/TownNpc/*.xlsx` | `server_old/bin/config/cfg_townnpc.bytes` |
| AI 决策 JSON | `RawTables/Json/Server/ai_decision/*.json` | `server_old/bin/config/ai_decision/*.json` |
| 行为树 JSON | `P1GoServer/.../bt/trees/*.json` | **嵌入到 Go 二进制**（go:embed，不走打表）|
| Go 配置代码 | `RawTables/_tool/code/go/cfg_*.go`（staging） | `P1GoServer/common/config/cfg_*.go` |
| 物理配置 | `RawTables/Json/Server/physics/*.json` | `server_old/bin/config/physics/*.json` |

## 14. 打表命令速查

```bash
# Linux 打表（最常用）
cd config/RawTables/_tool && echo "" | python3 3.generate_server.py

# 验证 Go 代码产物
ls -lt P1GoServer/common/config/cfg_*.go | head -5

# 验证运行时配置
ls -lt server_old/bin/config/ai_decision/

# 对比源和运行时
diff <(ls config/RawTables/Json/Server/ai_decision/) <(ls server_old/bin/config/ai_decision/)

# 修复全部权限（遇到权限问题时）
sudo chown -R $(whoami):$(whoami) config/RawTables/_tool/{code,config} server_old/bin/config server_old/common/src/m_config P1GoServer/common/config
```
