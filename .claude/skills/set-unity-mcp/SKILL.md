---
name: set-unity-mcp
description: 安装配置 Coplaydev Unity MCP 插件，让 Claude Code 通过 MCP 协议直接操作 Unity Editor（资源管理、场景控制、脚本编辑、Editor 自动化）。
---

你是一名 Unity MCP 配置专家。按 Phase 1-5 有序推进，每个关键节点暂停等待用户确认后再继续。

> **Coplaydev Unity MCP** (`com.coplaydev.unity-mcp`) — AI 助手与 Unity Editor 的 MCP 桥接层
> - GitHub: https://github.com/CoplayDev/unity-mcp
> - Docs: https://docs.coplay.dev/coplay-mcp/claude-code-guide

---

## Phase 1: 定位 Unity 项目

1. 搜索 `Packages/manifest.json` 定位 Unity 项目根目录
2. 若存在多个 Unity 项目，询问用户选择哪一个
3. 与用户确认项目路径后再继续

## Phase 2: 检查前置依赖

检查 `uv` 包管理器（uvx stdio 模式需要）：

1. 检测是否已安装：
   ```bash
   C:/Users/admin/.local/bin/uv.exe --version 2>&1
   ```
2. 未找到则安装：
   ```bash
   powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
   ```
   安装路径：`C:\Users\admin\.local\bin\`（含 `uv.exe`、`uvx.exe`、`uvw.exe`）
3. 验证安装成功
4. 提醒用户：`C:\Users\admin\.local\bin` 需加入系统 PATH（添加后重启终端）

## Phase 3: 安装或更新 Unity 包

1. 读取 `Packages/manifest.json`
2. 检查 `com.coplaydev.unity-mcp` 是否已存在

### Case A: 全新安装

在 `dependencies` 中添加：
```json
"com.coplaydev.unity-mcp": "https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#main"
```
- `#main` 稳定版，`#beta` 最新功能
- 备选：OpenUPM (`openupm add com.coplaydev.unity-mcp`) 或 Unity Asset Store

### Case B: 已安装 — 版本检查与更新

1. 读取 `Packages/packages-lock.json`，提取 `com.coplaydev.unity-mcp` 的 `hash` 值
2. 查询 GitHub API 获取最新 commit hash：
   ```bash
   curl -s https://api.github.com/repos/CoplayDev/unity-mcp/commits/main | grep -m1 '"sha"'
   ```
3. 对比 hash：
   - **相同** → 提示已是最新版本，跳过
   - **不同** → 提示用户"发现新版本，是否更新？"
4. 用户确认后，删除 `packages-lock.json` 中对应条目，提示重启 Unity 或点击 Resolve
5. 如需切换分支（main ↔ beta），同步更新 `manifest.json` URL 并清除 lock

## Phase 4: 配置 MCP Server

1. 查找或创建 Unity 项目根目录的 `.mcp.json`
2. 检查 `unityMCP` 是否已配置且正确 — 是则跳过
3. 端口冲突检测：
   ```bash
   netstat -ano | grep 8080
   ```
   若被占用则使用备选端口（如 8090），并告知用户在 Unity MCP 面板中匹配
4. 已有其他 server 时合并写入，不覆盖

### Mode A: HTTP（推荐）

```json
{
  "mcpServers": {
    "unityMCP": {
      "type": "http",
      "url": "http://localhost:8090/mcp"
    }
  }
}
```
需要 Unity Editor 运行且 MCP Server 已启动。

### Mode B: uvx stdio（独立运行）

**Windows:**
```json
{
  "mcpServers": {
    "unityMCP": {
      "command": "C:/Users/admin/.local/bin/uvx.exe",
      "args": ["--from", "mcpforunityserver", "mcp-for-unity", "--transport", "stdio"]
    }
  }
}
```

**Claude Code CLI（备选）:**
```bash
claude mcp add --scope user --transport stdio coplay-mcp \
  --env MCP_TOOL_TIMEOUT=720000 \
  -- uvx --python ">=3.11" coplay-mcp-server@latest
```

## Phase 5: 验证与用户指引

1. 回读 `.mcp.json` 和 `Packages/manifest.json` 确认配置正确
2. 输出用户操作清单：

```
## Unity Editor 中需要手动完成的步骤

1. 打开/重启 Unity Editor — 自动下载并导入 com.coplaydev.unity-mcp 包
2. 菜单 Window > MCP for Unity — 打开 MCP 控制面板
3. 点击 Start Server — 启动 HTTP 服务
4. 确认状态显示 🟢 "Connected ✓"
5. 在项目目录下重启 Claude Code 以加载新的 MCP 配置
```

3. 若 Phase 2 中新安装了 uv，提醒 PATH 配置

---

## Troubleshooting

| 问题 | 排查方法 |
|------|----------|
| Unity 包导入失败 | 检查网络；尝试 `#beta` 分支；备选 OpenUPM |
| MCP Server 无法连接 | 确认 Unity 已开且 Server 已启动；检查端口占用 `netstat -ano \| findstr 8080`；检查防火墙 |
| uvx 命令找不到 | 使用完整路径 `C:/Users/admin/.local/bin/uvx.exe`；或加入 PATH 后重启终端 |
| 多 Unity 实例 | 用 `unity_instances` 资源查看实例列表；`set_active_instance` 切换（格式 `Name@hash`） |

## Notes

- HTTP 模式下 Unity Editor 必须保持运行
- Roslyn 代码验证（可选）：在 MCP 面板点击 "Install Roslyn DLLs"
