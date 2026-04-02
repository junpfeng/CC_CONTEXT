# Memory 知识管理

<!-- 命令说明：管理项目知识记忆，分模块记录在 .claude/memory/ 目录中 -->
<!-- 用法：/memory [save|search|list|forget] -->
<!-- 触发条件：用户说"记住这个"、"保存知识"、"记录一下"、"你还记得...吗"、"忘掉..." -->

管理项目持久化知识。知识按模块分文件存储在 `.claude/memory/` 目录，通过 `MEMORY.md` 索引。

## 知识存储位置

```
.claude/memory/
├── MEMORY.md                    # 索引文件（必须保持更新）
├── client-comp-system.md        # 客户端组件系统
├── weapon-system.md             # 武器系统
├── config-pipeline.md           # 配置表管线
├── reference_proto_codegen.md   # Proto 代码生成
└── ...                          # 按需新增
```

## 操作指令

### /memory save — 保存新知识

1. **确定模块归属**：判断知识属于哪个模块（如武器系统、网络协议、UI 框架等）
2. **检查是否已有对应文件**：`Glob(".claude/memory/*.md")` 查找相关文件
3. **写入规则**：
   - 已有对应模块文件 → **追加到该文件**对应章节
   - 没有对应模块文件 → **新建文件**，文件名用 `kebab-case`（如 `vehicle-physics.md`）
   - **绝不把不同模块的知识塞进同一个文件**
4. **更新索引**：在 `MEMORY.md` 中添加/更新条目
5. **向用户确认**：显示保存的文件路径和内容摘要

**文件格式**：

```markdown
---
name: 模块名称
description: 一句话描述模块范围（用于未来检索判断相关性）
type: reference | feedback | project | user
---

## 主题一

具体知识内容...

## 主题二

具体知识内容...
```

**type 说明**：

| type | 用途 | 示例 |
|------|------|------|
| `reference` | 技术知识、工具用法、架构细节 | Proto 编码规则、配置表流程 |
| `feedback` | 用户纠正的行为偏好 | "不要自动 push"、"注释用中文" |
| `project` | 项目进展、排期、决策 | "3/5 后冻结合并"、"auth 重写是合规驱动" |
| `user` | 用户角色、偏好、技能背景 | "资深后端、前端新手" |

### /memory search — 搜索知识

1. 先读 `MEMORY.md` 索引，判断哪些文件可能相关
2. 对可能相关的文件用 `Grep` 搜索关键词
3. 读取匹配的文件，提取相关内容
4. 向用户展示结果

### /memory list — 列出所有知识模块

1. 读取 `MEMORY.md`，展示所有模块及描述

### /memory forget — 删除知识

1. 搜索匹配的知识条目
2. 向用户确认要删除的内容
3. 从文件中移除对应段落（如果文件只剩空壳，删除整个文件）
4. 更新 `MEMORY.md` 索引

## 自动触发规则

以下场景**无需用户显式调用 /memory**，应主动保存：

- 用户说"记住..."、"以后都这样做"、"下次注意..." → 立即保存为 `feedback` 类型
- 排查问题后发现了非显而易见的知识（如编码规则、隐藏的依赖关系） → 询问用户是否保存
- 用户纠正了你的错误做法 → 保存为 `feedback`，包含 **Why** 和 **How to apply**

## 模块划分原则

- **按系统/领域划分**，不按时间或会话划分
- 一个模块文件对应一个技术系统或知识域
- 单个文件不超过 200 行，超出则拆分为子模块
- 文件名反映内容：`weapon-system.md`、`proto-codegen.md`、`ui-panel-patterns.md`

**常见模块参考**：

| 文件名 | 内容范围 |
|--------|----------|
| `weapon-system.md` | 武器初始化、开火、弹药、换弹 |
| `vehicle-physics.md` | 载具物理、输入、网络同步 |
| `proto-codegen.md` | Proto 工具、编码规则、手动修改要点 |
| `config-pipeline.md` | 配置表工具链、表结构 |
| `client-comp-system.md` | Entity 组件、命名空间、编译问题 |
| `network-patterns.md` | HTTP/Socket 分层、Result 处理、Push Handler |
| `scene-lifecycle.md` | 场景加载、状态机、进出场景流程 |
| `user-preferences.md` | 用户工作偏好和反馈 |

## 禁止存储的内容

- 代码片段（代码在仓库里，不需要记忆）
- git 历史（用 git log 查）
- 具体文件路径列表（用 Glob/Grep 查）
- 当前会话的临时上下文（用 Task 工具跟踪）
- CLAUDE.md 中已有的信息（不重复）
