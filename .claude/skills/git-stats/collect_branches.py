#!/usr/bin/env python3
"""收集指定 Git 仓库各分支的提交统计（仅统计有活跃提交的分支）。

用法: python collect_branches.py --repo-dir /path/to/repo --since 2026-03-01 --output /tmp/repo_branches.txt

输出格式（每行）:
  branch_name|email|date|added|deleted
"""
import argparse, os, subprocess, sys, io

if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8", "utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")


def run(cmd, cwd):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.stdout.strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-dir", required=True)
    parser.add_argument("--since", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    cwd = args.repo_dir

    # 1. 获取所有远程分支及最后提交日期，过滤掉无活跃提交的分支
    ref_lines = run(
        ["git", "for-each-ref", "--sort=-committerdate",
         "--format=%(refname:short)|%(committerdate:short)", "refs/remotes/origin/"],
        cwd
    ).splitlines()

    active_branches = []
    for line in ref_lines:
        if "|" not in line:
            continue
        branch, date = line.rsplit("|", 1)
        if date >= args.since:
            # 去掉 origin/ 前缀
            short = branch.replace("origin/", "", 1)
            active_branches.append((short, branch))

    print(f"  {os.path.basename(cwd)}: {len(active_branches)} active branches (of {len(ref_lines)} total)")

    # 2. 对每个活跃分支，收集 numstat 数据
    results = []
    for short, full_branch in active_branches:
        log_out = run(
            ["git", "log", f"--since={args.since}", "--no-merges",
             "--pretty=format:COMMIT|%ae|%ad", "--date=short", "--numstat", full_branch],
            cwd
        )
        if not log_out or "COMMIT|" not in log_out:
            continue

        current_email = None
        current_date = None
        for line in log_out.splitlines():
            line = line.strip()
            if line.startswith("COMMIT|"):
                parts = line.split("|")
                if len(parts) >= 3:
                    current_email = parts[1]
                    current_date = parts[2]
            elif current_email and "\t" in line:
                parts = line.split("\t", 2)
                if len(parts) == 3:
                    a, d, fp = parts
                    try:
                        added = int(a) if a != "-" else 0
                        deleted = int(d) if d != "-" else 0
                        results.append(f"{short}|{current_email}|{current_date}|{added}|{deleted}")
                    except ValueError:
                        pass

    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        f.write("\n".join(results) + "\n" if results else "")

    print(f"  {os.path.basename(cwd)}: {len(results)} file-change records written")


if __name__ == "__main__":
    main()
