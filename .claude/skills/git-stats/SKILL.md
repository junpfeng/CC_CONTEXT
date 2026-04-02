---
name: git-stats
description: Fetch 各工程最新代码，统计最近 N 天的提交改动，从多个维度生成排行榜。
argument-hint: "[天数，默认7] [工程名...]"
---

你是一名代码统计分析师，负责拉取工作空间各 Git 工程最新代码并生成多维度提交排行榜。

## 参数解析

从 $ARGUMENTS 中解析：
- **天数**（可选，默认 7）：统计最近 N 天的提交
- **工程名**（可选，多个用空格分隔）：只统计指定工程。无指定则统计**所有** Git 仓库

## 执行流程

> **关键**：禁止使用 subagent 分析数据。全部通过预置脚本 + 并行 Bash 完成。

### 步骤 0: 自动发现所有 Git 仓库

```bash
cd E:/workspace/PRJ/P1 && find . -maxdepth 3 -name ".git" -type d 2>/dev/null | sed 's|/\.git$||;s|^\./||' | sort
```

将发现的所有目录名作为 `REPOS` 列表。如用户指定了工程名则只用指定的。

### 步骤 1: Fetch（并行，带重试）

对每个工程**并行**执行 fetch，失败时自动重试，最多 5 次：

```bash
cd <工程目录> && for i in 1 2 3 4 5; do git fetch --all 2>&1 && break || echo "retry $i..."; sleep 2; done
```

### 步骤 2: 收集数据（并行）

设 `SINCE` = N 天前的日期，`DATA_DIR=/tmp/gitstats_$$`（用 PID 避免冲突）。

对每个工程执行（可用单个 for 循环，工程多时分批并行）：

**numstat + 时段数据**:
```bash
mkdir -p $DATA_DIR && cd <工程目录> && \
  git log --since="$SINCE" --all --no-merges \
    --pretty=format:"COMMIT|%H|%an|%ae|%ad|%s" --date=short --numstat > $DATA_DIR/<repo>_numstat.txt 2>/dev/null && \
  git log --since="$SINCE" --all --no-merges \
    --pretty=format:"<repo>|%an|%ad" --date=format:"%Y-%m-%d %H" > $DATA_DIR/<repo>_hours.txt 2>/dev/null
```

### 步骤 2.5: 收集三大工程分支数据（并行）

对 P1GoServer、freelifeclient、old_proto **并行**执行：

```bash
python3 .claude/skills/git-stats/collect_branches.py \
  --repo-dir E:/workspace/PRJ/P1/<repo> --since "$SINCE" --output $DATA_DIR/<repo>_branches.txt
```

脚本自动过滤无活跃提交的分支，仅处理有新提交的分支。

### 步骤 3: 执行分析脚本（单条命令）

```bash
python3 .claude/skills/git-stats/analyze.py \
  --days N \
  --workspace E:/workspace/PRJ/P1 \
  --repos <逗号分隔的所有工程名> \
  --branch-repos P1GoServer,freelifeclient,old_proto \
  --data-dir $DATA_DIR \
  --output E:/workspace/PRJ/P1/docs/git-stats/git-stats-YYYY-MM-DD.md
```

脚本内置邮箱去重 + 11 维度分析 + 三大工程分支统计，stdout 输出摘要。

### 步骤 4: 清理 & 输出

```bash
rm -rf $DATA_DIR
```

将脚本 stdout 的摘要直接展示给用户，包含报告文件路径。

## 11 个统计维度（按重要性排序，脚本内置）

1. **人员×工程分布矩阵**（邮箱去重，谁在哪干活）
2. 代码量排行（排除生成代码，实际产出）
3. 活跃天数排行（投入度）
4. 每日提交趋势（项目脉搏）
5. 工程贡献分布矩阵（跨端协作）
6. 热点文件 Top 15（风险/冲突热区）
7. 最大单次提交 Top 10（需关注的大改动）
8. 提交次数排行（参考，受个人习惯影响大）
9. 文件触及广度排行
10. 文件类型排行
11. 提交时段分布（小时柱状图）
