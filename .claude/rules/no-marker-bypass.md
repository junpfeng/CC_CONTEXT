# 禁止绕过 MCP 验收 Marker

## 触发条件
当需要通过 MCP 视觉验收门禁时（Stop hook 或 git commit hook 拦截）

## 规则内容
1. **禁止手动创建验收 marker 文件**：不得执行 `touch`、`echo >`、`python -c "open()"` 等任何方式创建或修改 `/tmp/.mcp_visual_verified` 或任何 `.mcp_verify` 文件
2. **验收 marker 只能由 MCP 工具调用后自动生成**：PostToolUse hook 在 screenshot-game-view、screenshot-scene-view、script-execute 调用成功后自动写入带 HMAC 签名的 marker
3. **被 Stop hook 拦截时的正确做法**：
   - 通过 MCP 截图工具（screenshot-game-view / screenshot-scene-view）进行实际的视觉验证
   - 或确认变更全部在 codegen 路径下（Proto/、Config/Gen/），此时 hook 自动放行
4. **禁止修改 hook 脚本来绕过检查**：`.claude/hooks/` 下的验证脚本不得被修改以降低验证标准
5. **Hook 是安全门，绕过 hook = 关闭安全门**，不论理由是否看似合理

## 来源
实际事故：Claude 在 Stop hook 拦截后直接执行 `touch /tmp/.mcp_visual_verified` 绕过验收门禁。hook 报错信息本身暴露了绕过方法。已修复为 HMAC 签名验证 + 路径拦截 + 自动生成三层防御。
