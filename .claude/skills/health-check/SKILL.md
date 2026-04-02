---
name: health-check
description: 工作空间健康检查：服务端口、配置文件、Go编译、MCP连通性、Unity编译错误。失败项自动修复后报告。
---

# Workspace Health Check

运行 `scripts/health-check.sh` 执行全量健康检查，解析输出并处理失败项。

## 执行流程

1. **运行检查脚本**：
   ```bash
   bash "$CLAUDE_PROJECT_DIR/scripts/health-check.sh"
   ```
   脚本输出格式为 `[PASS]`/`[FAIL]`/`[WARN]` 前缀的检查项。

2. **解析结果**：逐行读取输出，统计 PASS/FAIL/WARN 数量。

3. **自动修复 FAIL 项**（按类型）：

   | 失败类型 | 修复动作 |
   |---------|---------|
   | 服务未运行 | `powershell -File scripts/server.ps1 start <服务名>` |
   | 配置文件缺失 | 检查是否有模板/备份可恢复，无法恢复则报告 |
   | Go 编译失败 | 读取错误输出，定位源文件，尝试修复编译错误 |
   | MCP 不可达 | `powershell -File scripts/unity-restart.ps1` 重启 Unity MCP |
   | Unity 编译错误 | 调用 `/debug-unity` skill 处理 |

4. **修复后复检**：对修复过的项重新运行对应检查，确认修复成功。

5. **输出报告**：汇总所有检查项最终状态，格式：
   ```
   === Health Check Report ===
   [PASS] 项目名 — 描述
   [FAIL] 项目名 — 描述（修复失败原因）
   Total: X pass, Y fail, Z warn
   ```

## 注意事项

- 自动修复最多尝试 1 次，避免循环
- Go 编译检查使用 `make build`（不是 `go build ./...`）
- Unity 编译错误只关注 `Assets/` 下的真实源文件，忽略 MCP 临时脚本
- MCP 连通性通过 `scripts/mcp_call.py` ping 测试，端口 8080
