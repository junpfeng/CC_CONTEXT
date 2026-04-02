---
name: clone-workspace
description: 快速在新目录下复刻整个工作空间（git clone + svn checkout + 辅助文件复制）。
argument-hint: "<目标路径> [--no-client] [--no-svn] [--branch <分支名>]"
---

你是一名工作空间复刻助手，负责在指定目录下重建完整的 P1 工作空间。

**原则：三个工程（P1GoServer、old_proto、freelifeclient）必须通过版本控制拉取，其余辅助文件直接从当前工作空间复制。**

## 参数解析

从 $ARGUMENTS 中解析：
- **目标路径**（必填）：新工作空间的根目录路径
- **--no-client**（可选）：跳过 freelifeclient（git + svn 均跳过）
- **--no-svn**（可选）：仅跳过 SVN checkout（仍会 git clone freelifeclient）
- **--branch <分支名>**（可选）：指定 freelifeclient 的 git 分支（默认 master）

> 如果用户未提供目标路径，提示用户输入。
> `--no-client` 隐含 `--no-svn`。

## 工程清单（版本控制拉取）

### Git 工程

| 工程 | 远端 | 默认分支 | 协议 |
|------|------|----------|------|
| P1GoServer | `miao@git2.miao.one:P1/P1GoServer.git` | master | SSH |
| old_proto | `miao@git2.miao.one:clients/old_proto.git` | master | SSH |
| freelifeclient | `https://git2.miao.one/clients/freelifeclient` | master | HTTPS |

> **注意**：freelifeclient 使用 HTTPS，clone 时依赖 git credential helper 提供凭据。如果凭据缺失，clone 会报错（不会卡住等待输入）。失败后前台重试，让用户交互输入凭据。

### SVN 资源（freelifeclient 内）

freelifeclient 同时受 Git 和 SVN 双重管理：
- **Git** 管理代码（Scripts、Scenes、Prefabs 等）
- **SVN** 管理美术/配置资源（RawTables 等大文件）

| SVN 远端 | 说明 |
|----------|------|
| `svn://svn.miao.one/Art/Version_Plan_B_NPC` | checkout 到 `freelifeclient/` |

> 操作顺序：先 git clone → 再 svn checkout --force 同目录。
> SVN 会写入 `.svn/` 并补充 Git 未跟踪的文件（RawTables/ 等），不会删除 `.git/`。

## 辅助内容（从当前工作空间复制）

| 来源 | 说明 |
|------|------|
| `CLAUDE.md` | 工作空间根文档 |
| `.mcp.json` | MCP 配置 |
| `.claude/` | Claude Code 配置、skills、rules、templates |
| `docs/` | 设计文档、经验总结 |
| `scripts/` | 工具脚本 |
| `CC_CONTEXT/` | Claude Code 文档模板（如存在） |

**复制时排除**：
- `.claude/` 内：`settings.local.json`、`__pycache__/`
- `scripts/` 内：`tmp_*`、`_tmp_*`、`*.png`、`__pycache__/`

**不复制的顶层项**：`distillation/`、`BehaviorDesignerPro/`、`ClaudeCodeDocs/`、`logs/`、`run/`、`exports/`、`pngs/`、`*.7z`、`*.mp4`、`*.stackdump`、`.codebuddy/`

## 工作流程

### 1. 前置检查与准备

1. 确定当前工作空间绝对路径 `$SRC`（Claude Code 的 primary working directory），**禁止硬编码**
2. 目标路径已存在且非空 → **警告用户并询问**
3. 工具可用性：`git`、`svn`（如需 SVN）
4. SSH 连通性：`ssh -o ConnectTimeout=5 -T git2.miao.one 2>&1`
5. SVN 连通性（如需）：`svn info svn://svn.miao.one/Art --non-interactive 2>&1`

### 2. 创建目标目录

```bash
mkdir -p <目标路径>
```

### 3. 并行执行：Git Clone + 辅助文件复制

以下两组操作互相独立，**并行执行**：

#### 3a. Git Clone

三个工程各自 `run_in_background` 并行执行（`--no-client` 时跳过 freelifeclient）：
```bash
git clone miao@git2.miao.one:P1/P1GoServer.git <目标路径>/P1GoServer
git clone miao@git2.miao.one:clients/old_proto.git <目标路径>/old_proto
git clone https://git2.miao.one/clients/freelifeclient <目标路径>/freelifeclient
```
> 如指定 `--branch`，freelifeclient 加 `-b <分支名>`。
> 网络失败时自动重试一次。HTTPS clone 凭据失败时前台重试（让用户交互输入）。

#### 3b. 复制辅助文件

从 `$SRC` 复制到目标路径，用 tar 管道排除不需要的文件（Windows Git Bash 无 rsync）：

```bash
# 单文件
cp "$SRC/CLAUDE.md" <目标路径>/
cp "$SRC/.mcp.json" <目标路径>/

# .claude（排除 settings.local.json 和 __pycache__）
tar -cf - -C "$SRC" --exclude='settings.local.json' --exclude='__pycache__' .claude \
  | tar -xf - -C <目标路径>

# docs
tar -cf - -C "$SRC" docs | tar -xf - -C <目标路径>

# CC_CONTEXT（仅当存在时）
[ -d "$SRC/CC_CONTEXT" ] && (tar -cf - -C "$SRC" CC_CONTEXT | tar -xf - -C <目标路径>)

# scripts（排除临时文件和图片）
tar -cf - -C "$SRC" \
  --exclude='tmp_*' --exclude='_tmp_*' --exclude='*.png' --exclude='__pycache__' \
  scripts | tar -xf - -C <目标路径>
```

### 4. P1GoServer submodule 初始化

**前置条件**：P1GoServer clone 成功。失败则跳过。

```bash
cd <目标路径>/P1GoServer && git submodule update --init --recursive
```

> 初始化 `resources/proto/` submodule（历史遗留，只读不编辑）。

### 5. SVN Checkout（可选）

**前置条件**：freelifeclient git clone 成功，且未指定 `--no-client` 和 `--no-svn`。任一不满足则跳过。

```bash
cd <目标路径>/freelifeclient
svn checkout svn://svn.miao.one/Art/Version_Plan_B_NPC . --force --non-interactive
```

> `--force` 在已有文件的目录中 checkout，SVN 补充 Git 未跟踪的大文件。
> 网络失败时自动重试一次。

### 6. 创建辅助空目录

```bash
mkdir -p <目标路径>/{logs,run,exports}
```

### 6.5. 路径修正（关键步骤）

复制的 `scripts/` 和其他辅助文件中可能包含源工作空间的**硬编码绝对路径**，必须替换为目标路径。

1. 确定源路径 `$SRC`（步骤 1 中已记录）和目标路径 `$DST`
2. 扫描并替换 `scripts/` 下所有文件中的绝对路径引用：

```bash
# 正斜杠版本（Python/CS 脚本常用）
SRC_FWD=$(echo "$SRC" | sed 's|\\|/|g')
DST_FWD=$(echo "$DST" | sed 's|\\|/|g')

# 扫描 scripts/ 下所有文本文件，替换源路径为目标路径
grep -rl "$SRC_FWD" <目标路径>/scripts/ | while read f; do
  sed -i "s|$SRC_FWD|$DST_FWD|g" "$f"
done

# 反斜杠版本（PowerShell 脚本常用）
SRC_BACK=$(echo "$SRC" | sed 's|/|\\|g')
DST_BACK=$(echo "$DST" | sed 's|/|\\|g')

grep -rl "$SRC_BACK" <目标路径>/scripts/ | while read f; do
  sed -i "s|${SRC_BACK//\\/\\\\}|${DST_BACK//\\/\\\\}|g" "$f"
done
```

3. 验证无残留：`grep -r "$SRC_FWD" <目标路径>/scripts/` 应返回空

> **注意**：`CLAUDE.md`、`docs/`、`.claude/` 中通常使用相对路径，一般不需要替换。如发现残留，同样修正。

### 7. 验证

| 组件 | 验证方式 |
|------|----------|
| P1GoServer | `git -C <path> log --oneline -1` + `go.mod` 存在 |
| old_proto | `git -C <path> log --oneline -1` + .proto 文件数 ≥ 43 |
| freelifeclient (git) | `git -C <path> log --oneline -1` + Assets/ 存在 |
| freelifeclient (svn) | `svn info <path>` 确认工作副本有效 |
| .claude | `skills/`、`rules/` 目录存在 |
| 子工程 rules | `P1GoServer/.claude/rules/constitution.md` 和 `freelifeclient/.claude/rules/constitution.md` 存在 |
| scripts | `server.ps1`、`claude-git.sh` 存在 |
| scripts 路径 | `grep -r "$SRC_FWD" <目标路径>/scripts/` 返回空（无残留源路径） |
| docs | `README.md` 存在 |

> 跳过的组件在验证中也跳过，不报失败。
> 子工程 rules 缺失时自动创建（参考 `P1GoServer/.claude/rules/constitution.md` 的格式）。

### 8. 结果汇总

输出表格：

| 组件 | 来源 | 状态 | 详情 |
|------|------|------|------|
| P1GoServer | git clone (SSH) | 成功/失败 | commit hash / branch |
| old_proto | git clone (SSH) | 成功/失败 | commit hash |
| freelifeclient (git) | git clone (HTTPS) | 成功/失败/跳过 | commit hash / branch |
| freelifeclient (svn) | svn checkout | 成功/失败/跳过 | revision |
| .claude | 复制 | 成功/失败 | skills/rules 数量 |
| docs | 复制 | 成功/失败 | 文件数 |
| scripts | 复制 | 成功/失败 | 文件数 |

最后输出新工作空间完整路径和使用提示。

## 执行原则

- **三个工程必须通过 git clone / svn checkout 拉取**，禁止复制
- **其余辅助文件直接从当前工作空间复制**
- 三个 clone 均可 `run_in_background` 并行；HTTPS 凭据失败时前台重试
- 辅助文件复制与 git clone 并行执行（互不依赖）
- git clone 和 svn checkout 失败时均自动重试一次
- `--no-client` 隐含 `--no-svn`
- SVN checkout 必须在 git clone 完成之后执行（顺序依赖）
- 当前工作空间路径在步骤 1 确定，后续禁止硬编码
- **复制辅助文件后必须执行路径修正**（步骤 6.5），将源工作空间绝对路径替换为目标路径，并验证无残留
- 某步骤的前置条件不满足时跳过该步骤，不中断整体流程
- 所有步骤独立执行，失败不中断后续，最后统一汇报
- 整个过程无需用户确认（除目标路径已存在的情况外）
