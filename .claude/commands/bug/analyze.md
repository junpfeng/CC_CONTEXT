---
description: 分析 auto-work 产出中遗漏/缺陷的根因，定位流程断点并输出修复方案+工作流优化建议
argument-hint: <version_id> <feature_name> <bug描述>
---

## 参数解析

用户传入的完整参数：`$ARGUMENTS`

**解析规则：**

参数格式：`<version_id> <feature_name> <bug描述（剩余部分）>`

1. **第一个词**：`version_id`（版本号，如 `0.0.3`）
2. **第二个词**：`feature_name`（功能名称，对应 `docs/version/{version_id}/{feature_name}/` 目录）
3. **剩余部分**：bug 描述（现象、预期行为等自然语言描述）

**验证：**
- 如果参数不足 3 部分，使用 AskUserQuestion 让用户补充
- 确认 `docs/version/{version_id}/{feature_name}/` 目录存在，不存在则报错

解析完成后，设定以下变量：
- `VERSION_ID` = 版本 ID
- `FEATURE_NAME` = 功能名称
- `FEATURE_DIR` = `docs/version/{VERSION_ID}/{FEATURE_NAME}`
- `BUG_DESC` = bug 描述

---

## 分析流程

这是一个**单次分析任务**，在当前会话中完成，不启动外部脚本。

### 第一步：收集证据（全量阅读 auto-work 产出物）

按顺序读取 `{FEATURE_DIR}/` 下的所有产出文件：

1. **`idea.md`** — 原始需求输入
2. **`feature.json`**（或旧版 `feature.md`）— 结构化需求文档
3. **`plan.json`**（或旧版 `plan.md`）— 技术方案
4. **`plan/`** 子目录下的所有文件（.json 或旧版 .md）
5. **`tasks/README.md`** + 所有 `tasks/task-*.md` — 任务拆分
6. **`auto-work-log.md`** — 全流程日志（阶段耗时、状态）
7. **`plan-iteration-log.md`** + **`plan-review-report.md`** — Plan 迭代过程
8. **`develop-iteration-log.md`** + **`develop-review-report.md`** — 开发迭代过程
9. **`develop-log.md`** — 开发详细记录

> 文件可能不全（旧版 auto-work 产出物没有 tasks/ 目录），读取时跳过不存在的文件即可。

### 第二步：定位 bug 在代码中的位置

根据 bug 描述，搜索相关代码：
- 使用 Grep/Glob 搜索相关类名、方法名、配置键
- 阅读涉及的代码文件，确认 bug 的具体表现
- 确定 bug 影响的范围（哪些文件、哪些流程）

### 第三步：全链路断点分析

逐层对比，定位 bug 是在 auto-work 哪个环节丢失或出错的：

| 检查项 | 问题 |
|--------|------|
| **idea → feature** | feature.json 是否完整覆盖了 idea.md 中的这个需求点？ |
| **feature → plan** | plan.json 是否为这个需求点设计了技术方案？plan/ 子文件中是否有对应设计？ |
| **plan → tasks** | 任务拆分是否包含了实现这个功能的任务？是否有遗漏？ |
| **tasks → code** | 对应任务的代码是否被正确实现？还是实现了但有 bug？ |
| **review** | develop-review-report.md 是否发现了这个问题？如果发现了，为什么没修好？ |
| **收敛** | 开发迭代是否因为 "稳定不变" 或 "达到上限" 而终止？是否带着未解决的问题结束？ |

### 第四步：归因分类

将 bug 归因到以下类别之一（可多选）：

| 归因类别 | 说明 | 典型表现 |
|----------|------|----------|
| **需求遗漏** | feature.json 没有覆盖 idea.md 中的需求点 | idea 提了但 feature 没写 |
| **方案遗漏** | plan 没有为 feature 中的需求设计方案 | feature 写了但 plan 没设计 |
| **任务遗漏** | 任务拆分时遗漏了 plan 中的某个模块 | plan 设计了但没拆成 task |
| **实现缺陷** | 任务正确拆分但代码实现有 bug | task 有但代码写错了 |
| **Review 盲区** | Review 没有发现已存在的问题 | 代码有问题但 review 没报 |
| **收敛失败** | Review 发现了但修不好，迭代终止 | review 报了但修复轮次耗尽 |
| **编译驱动偏移** | 为了通过编译而删除/注释了功能代码 | 编译报错时简单删掉了功能代码 |
| **上下文丢失** | 跨进程传递时关键信息丢失 | plan 写了但 task 的 prompt 没带上 |

### 第五步：输出分析报告

将分析结果写入 `docs/bugs/{VERSION_ID}/{FEATURE_NAME}/` 目录（不存在则创建），文件名为 bug 的简短标识（英文，如 `missing-reload-anim.md`）。

报告格式：

```markdown
# Bug 分析：{bug 简短标题}

## Bug 描述
{用户提供的 bug 描述，补充复现步骤和现象}

## 代码定位
- **涉及文件**：列出 bug 相关的代码文件和行号
- **当前行为**：代码实际做了什么
- **预期行为**：代码应该做什么

## 全链路断点分析

### idea.md → feature.json
- 是否覆盖：是/否
- 原文摘录：{从 idea.md 摘录相关需求}
- feature.json 对应内容：{摘录或"未找到对应内容"}

### feature.json → plan.json
- 是否覆盖：是/否
- feature 需求：{摘录}
- plan 设计：{摘录或"未找到对应设计"}

### plan.json → tasks/
- 是否覆盖：是/否
- plan 设计点：{摘录}
- 对应任务：{task-NN 或"无对应任务"}

### tasks/ → 代码实现
- 是否实现：是/否/部分
- 任务要求：{摘录}
- 实际代码：{描述实际实现情况}

### Review 检出
- 是否被 Review 发现：是/否
- Review 原文：{摘录或"未提及"}
- 修复结果：{已修复/未修复/修错了}

## 归因结论

**主要原因**：{归因类别} — {一句话解释}

**根因链**：
{从源头到表现的完整因果链}
例如：idea.md 提到了 X 功能 → feature.json 将其概括为 Y（丢失了细节 Z）→ plan 基于不完整的 feature 设计 → 最终代码缺少 Z

## 修复方案

### 代码修复
{具体需要修改哪些文件、怎么改、改完后预期效果}

### 工作流优化建议
{针对归因类别，给出 auto-work 流程改进建议}

格式：
- **问题**：{哪个环节出了什么问题}
- **建议**：{具体怎么改 auto-work 流程/prompt/脚本}
- **改哪里**：{涉及的脚本文件或 prompt 位置}
```

### 第六步：追加到版本 bug 清单

检查 `docs/bugs/{VERSION_ID}/{FEATURE_NAME}/{FEATURE_NAME}.md` 是否存在：
- 如果存在，将这个 bug 追加到清单中（格式与现有 bug 条目一致）
- 如果不存在，创建新文件，标题为 `# {FEATURE_NAME} 未修复 bug`

每条 bug 格式：
```markdown
- [ ] {bug 简短描述}
  - **现象**：{具体表现}
  - **归因**：{归因类别}
  - **分析报告**：[详细分析]({分析报告相对路径})
```

---

## 注意事项

- 这是**分析任务**，不修改代码，只产出分析报告
- 分析必须基于实际文件内容，不要推测不存在的文件内容
- 对比时要引用原文，不要泛泛而谈
- 工作流优化建议要具体可执行，指出改哪个脚本的哪段 prompt
- 如果产出物文件缺失（如旧版没有 tasks/），在报告中标注"该阶段产出物缺失，无法分析"
