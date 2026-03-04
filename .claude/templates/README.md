# Claude Code 文档模板套件

本目录包含一套可复用的通用模板，用于在新项目中快速搭建 Claude Code 文档体系。

## 文件清单

| 文件 | 用途 |
|------|------|
| `CLAUDE.md.template` | 工作空间级 CLAUDE.md 模板（项目根目录） |
| `constitution.md.template` | 工作空间级宪法模板（`.claude/rules/constitution.md`） |
| `sub-project-CLAUDE.md.template` | 子工程 CLAUDE.md 模板（子工程根目录） |
| `sub-project-constitution.md.template` | 子工程宪法模板（子工程 `.claude/rules/constitution.md`） |

## 新项目搭建步骤

按以下顺序操作：

### 1. 初始化 `.claude` 目录结构

```bash
mkdir -p .claude/rules
mkdir -p .claude/skills
mkdir -p docs/{design,postmortem,knowledge,reference}
```

### 2. 复制并填写工作空间级文档

```bash
cp .claude/templates/CLAUDE.md.template ./CLAUDE.md
cp .claude/templates/constitution.md.template .claude/rules/constitution.md
```

打开 `CLAUDE.md` 和 `constitution.md`，搜索 `<!-- TODO -->` 并逐项填写。

### 3. 为每个子工程创建文档

```bash
# 以 server 子工程为例
mkdir -p server/.claude/rules
cp .claude/templates/sub-project-CLAUDE.md.template server/CLAUDE.md
cp .claude/templates/sub-project-constitution.md.template server/.claude/rules/constitution.md
```

打开子工程的 `CLAUDE.md` 和 `constitution.md`，搜索 `<!-- TODO -->` 并逐项填写。

### 4. 更新索引

- 在工作空间 `CLAUDE.md` 的 **项目目录结构** 表中添加子工程条目
- 在 `constitution.md` 的 **子工程索引** 表中添加对应条目
- 创建或更新 `.claude/INDEX.md`

## 占位符说明

所有模板中使用统一的 `<!-- TODO -->` 占位符格式，表示需要用户根据实际项目情况填写。

占位符中通常包含示例内容作为参考，填写完成后请删除 `<!-- TODO -->` 注释标记。

## 必选与可选说明

| 章节/文件 | 必选/可选 | 说明 |
|-----------|----------|------|
| `CLAUDE.md` 项目目录结构 | 必选 | 子工程索引，Claude Code 导航的核心入口 |
| `CLAUDE.md` 工作规范 | 必选 | 最小上下文原则等基础约定 |
| `constitution.md` 禁止操作 | 必选 | 自动生成区域、安全规则等不可违反的约束 |
| `constitution.md` 子工程索引 | 必选 | 与 CLAUDE.md 保持一致 |
| 子工程 `CLAUDE.md` | 按需 | 有独立构建系统的子工程才需要 |
| 子工程 `constitution.md` | 按需 | 有特定强制规则的子工程才需要 |
| `docs/` 各子目录 | 可选 | 按项目需要选择性创建 |
