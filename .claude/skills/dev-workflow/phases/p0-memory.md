# Phase 0：记忆查询

> 领域依赖：无

在正式开始前，查询历史会话中的相关经验。

## 步骤

1. **提取关键词**：从需求描述中提取 2-3 个核心关键词
2. **三层搜索**（使用 claude-mem MCP 工具）：
   - 索引搜索：`search(query="<关键词>", limit=10)`
   - 时间线上下文：`timeline(anchor=<id>, depth_before=3, depth_after=3)`
   - 获取详情：`get_observations(ids=[<id1>, <id2>])`
3. **输出摘要**：命中则列出可复用思路和需要避免的坑；未命中则输出"未找到相关历史记忆"

## 容错

claude-mem MCP 不可用时（未安装/服务未启动/调用报错），**跳过本 Phase**，直接进入 Phase 1。
