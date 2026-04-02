# Phase 1：需求解析与验证

> 领域依赖：无

## 1.1 读取需求文档

Read 用户指定的需求文档，提取：功能概述、验收标准、依赖关系、涉及工程、优先级。

**idea.md schema 检查**：如果需求文档是 `idea.md`（由 `/new-feature` 生成），验证必需章节：
- `## 核心需求` — 缺失则 warn 并尝试从全文提取
- `## 确认方案` — 缺失则 warn（"方案未经用户确认，将在 P2 自主设计"），流程不阻塞

## 1.2 需求分类

分析需求内容，判断是否需要技术调研：

| 分类 | 触发条件 | 后续动作 |
|------|----------|----------|
| **research** | 全新系统设计、需技术选型、涉及不熟悉领域 | 执行 1.3 调研 |
| **direct** | Bug 修复、已有系统扩展、需求明确且有参考实现 | 跳过 1.3 |

**上游快速通道**：如果 idea.md 包含 `## 确认方案` 章节（由 `/new-feature` Step 3 写入，方案已经人工确认），直接分类为 `direct`，跳过 1.3 调研。

## 1.3 多轮调研（仅 research 类）

交替执行调研→审查循环，直到收敛（借鉴 auto-work research-loop）：

1. **调研轮**（subagent）：搜索 `docs/` 知识库 + 查阅代码对标实现 + WebSearch 业界方案
2. **审查轮**（主 agent 或 subagent）：检查调研结论的完整性、可行性、是否有遗漏方案
3. **收敛条件**：审查无 critical/important 问题 → 结束。**最多 6 轮**（3 次调研+3 次审查）。**早退**：连续 2 轮审查无 critical/important → 提前退出整个调研循环（不继续消耗剩余轮次）
4. 主 agent 提取最终结论写入 requirements.json 的 `research_conclusion` 字段
5. 调研未收敛 → 标记 `research_conclusion: "调研未完全收敛，待确认项：[...]"` 并继续

## 1.4 工程定位与依赖检查

1. 验证涉及的子工程目录和 CLAUDE.md 存在
2. 检查前置条件：协议编译环境、配置生成工具、DB 连接、测试环境

## 1.5 结构化需求输出

输出 JSON 格式的 `requirements.json`，保存到设计文档目录：

```jsonc
{
  "name": "功能名称",
  "overview": "一句话概述",
  "classification": "research|direct",
  "research_conclusion": "调研结论（research 类才有）",
  "requirements": [
    {
      "id": "REQ-001",
      "title": "需求标题",
      "description": "详细描述",
      "priority": "P0|P1|P2",
      "side": "client|server|both",
      "acceptance_criteria": ["验收条件1", "验收条件2"]
    }
  ],
  "technical_constraints": [
    { "category": "性能|网络|架构|资源", "description": "约束描述" }
  ],
  "projects": ["P1GoServer", "freelifeclient"],
  "dependencies": ["依赖项"],
  "risks": ["风险点"]
}
```

**每个 requirement 必须有 acceptance_criteria，禁止留空。**

更新 progress.json 标记 P1 completed（含 design_doc_dir 路径），更新 heartbeat.json，自动进入 Phase 2。
