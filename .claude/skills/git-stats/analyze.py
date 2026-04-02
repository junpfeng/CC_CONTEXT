#!/usr/bin/env python3
"""Git 多维度提交排行榜分析脚本。

用法: python analyze.py --days N --workspace /path/to/workspace --repos repo1,repo2,repo3
      --data-dir /tmp/gitstats  --output /path/to/report.md

数据文件约定（由调用方提前生成）:
  <data-dir>/<repo>_numstat.txt  — git log --numstat 输出
  <data-dir>/<repo>_hours.txt   — git log --date=format:"%Y-%m-%d %H" 输出
"""

import argparse, os, sys, io
from collections import defaultdict
from datetime import datetime, timedelta

# Windows GBK stdout 兼容
if sys.stdout.encoding and sys.stdout.encoding.lower() not in ("utf-8", "utf8"):
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

# 生成代码目录 — 不计入个人代码量排行
GEN_PATTERNS = [
    "common/proto/",
    "internal/service/",  # *_service.go
    "Managers/Net/Proto/",
    "Config/Gen/",
]

def is_generated(filepath):
    return any(p in filepath for p in GEN_PATTERNS)

def fmt(n):
    """千分位格式化整数"""
    if n < 0:
        return "-" + fmt(-n)
    return f"{n:,}"

def truncate_path(repo, path, maxlen=75):
    prefix = f"[{repo}] "
    full = prefix + path
    if len(full) <= maxlen:
        return full
    fname = os.path.basename(path)
    remain = maxlen - len(prefix) - len(fname) - 5
    if remain > 10:
        return prefix + path[:remain] + "/.../" + fname
    return prefix + ".../" + fname

def parse_numstat(filepath, repo_name):
    """解析 git log --numstat 输出，返回 commits 列表"""
    commits = []
    current = None
    if not os.path.exists(filepath):
        return commits
    with open(filepath, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n\r")
            if line.startswith("COMMIT|"):
                if current:
                    commits.append(current)
                parts = line.split("|", 5)
                if len(parts) >= 6:
                    current = {
                        "hash": parts[1], "author": parts[2], "email": parts[3],
                        "date": parts[4], "subject": parts[5],
                        "repo": repo_name, "files": [],
                    }
                else:
                    current = None
            elif current and line and "\t" in line:
                parts = line.split("\t", 2)
                if len(parts) == 3:
                    add_s, del_s, fpath = parts
                    if add_s == "-" or del_s == "-":
                        current["files"].append({"path": fpath, "added": 0, "deleted": 0, "binary": True})
                    else:
                        try:
                            current["files"].append({
                                "path": fpath,
                                "added": int(add_s),
                                "deleted": int(del_s),
                                "binary": False,
                            })
                        except ValueError:
                            pass
    if current:
        commits.append(current)
    return commits

def parse_hours(filepath):
    """解析时段数据，返回 [(repo, author, date_str, hour_int), ...]"""
    records = []
    if not os.path.exists(filepath):
        return records
    with open(filepath, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split("|")
            if len(parts) >= 3:
                repo = parts[0]
                author = parts[1]
                datetime_str = parts[2].strip()
                dt_parts = datetime_str.split(" ")
                if len(dt_parts) == 2:
                    try:
                        hour = int(dt_parts[1])
                        records.append((repo, author, dt_parts[0], hour))
                    except ValueError:
                        pass
    return records

def ext_of(path):
    """清洗文件扩展名"""
    _, ext = os.path.splitext(path.strip().strip('"').strip("'"))
    ext = ext.lower().strip()
    return ext if ext else "(no ext)"

def merge_by_email(commits):
    """按邮箱去重，作者统一用邮箱显示。同名不同邮箱合并到提交最多的邮箱。"""
    email_names = defaultdict(lambda: defaultdict(int))
    for c in commits:
        email_names[c["email"]][c["author"]] += 1
    # 同名不同邮箱合并
    name_to_emails = defaultdict(list)
    for email in email_names:
        best = max(email_names[email].items(), key=lambda x: x[1])[0]
        name_to_emails[best].append(email)
    email_map = {}  # old_email -> canonical_email
    for name, emails in name_to_emails.items():
        if len(emails) > 1:
            primary = max(emails, key=lambda e: sum(email_names[e].values()))
            for e in emails:
                if e != primary:
                    email_map[e] = primary
    # 用邮箱作为显示名
    for c in commits:
        ce = email_map.get(c["email"], c["email"])
        c["author"] = ce  # 用邮箱作为作者标识
        c["email"] = ce
    # 返回去重后的邮箱集合
    unique_emails = set()
    for c in commits:
        unique_emails.add(c["email"])
    return unique_emails


def generate_branch_report(branch_data, days, date_from, date_to, output_path):
    """生成三大工程分支综合统计报告（独立文件），以邮箱为主维度"""
    lines = []
    w = lines.append

    repo_names = sorted(branch_data.keys())
    short = {"P1GoServer": "Server", "freelifeclient": "Client", "old_proto": "Proto"}

    w(f"# 分支综合统计 — 最近 {days} 天\n")
    w(f"> 统计范围：{date_from} ~ {date_to}")
    w(f"> 工程：{', '.join(repo_names)}\n")

    # ---- 预计算：email -> {branch -> {repo -> {added, deleted, dates}}} ----
    email_data = defaultdict(lambda: defaultdict(lambda: defaultdict(
        lambda: {"added": 0, "deleted": 0, "dates": set()})))
    all_branches = set()
    for repo, records in branch_data.items():
        for r in records:
            email_data[r["email"]][r["branch"]][repo]["added"] += r["added"]
            email_data[r["email"]][r["branch"]][repo]["deleted"] += r["deleted"]
            email_data[r["email"]][r["branch"]][repo]["dates"].add(r["date"])
            all_branches.add(r["branch"])

    # 每人总工作量
    email_totals = {}
    for email in email_data:
        total_added = 0
        total_deleted = 0
        active_branches = set()
        active_repos = set()
        active_dates = set()
        for b in email_data[email]:
            active_branches.add(b)
            for r in email_data[email][b]:
                d = email_data[email][b][r]
                total_added += d["added"]
                total_deleted += d["deleted"]
                active_repos.add(r)
                active_dates |= d["dates"]
        wl = total_added + int(total_deleted * 0.5)
        email_totals[email] = {
            "workload": wl, "added": total_added, "deleted": total_deleted,
            "branches": active_branches, "repos": active_repos, "dates": active_dates,
        }

    sorted_emails = sorted(email_totals.keys(), key=lambda e: -email_totals[e]["workload"])

    # ---- 1. 人员工作量总览 ----
    w("## 1. 人员工作量总览")
    w("| 排名 | 邮箱 | 工作量 | 新增 | 删除 | 活跃分支数 | 覆盖工程 | 活跃天数 |")
    w("|------|------|--------|------|------|-----------|----------|----------|")
    for i, email in enumerate(sorted_emails, 1):
        t = email_totals[email]
        repo_tags = "+".join(short.get(r, r[:6]) for r in sorted(t["repos"]))
        w(f"| {i} | {email} | {fmt(t['workload'])} | +{fmt(t['added'])} | -{fmt(t['deleted'])} | {len(t['branches'])} | {repo_tags} | {len(t['dates'])} |")
    w("")

    # ---- 2. 每人分支明细（Top 20 人，每人展示 Top 分支） ----
    w("## 2. 每人分支明细")
    w("> 按工作量排名，展示每人参与的各分支及各端贡献\n")
    for i, email in enumerate(sorted_emails[:20], 1):
        t = email_totals[email]
        w(f"### {i}. {email}")
        w(f"总工作量 {fmt(t['workload'])} | 新增 +{fmt(t['added'])} | 删除 -{fmt(t['deleted'])} | {len(t['branches'])} 分支 | {len(t['dates'])} 天\n")

        # 按分支工作量排序
        branch_wl = []
        for b in email_data[email]:
            ba, bd = 0, 0
            repos_in = []
            for r in repo_names:
                if r in email_data[email][b]:
                    d = email_data[email][b][r]
                    ba += d["added"]
                    bd += d["deleted"]
                    repos_in.append(r)
            branch_wl.append((ba + int(bd * 0.5), ba, bd, b, repos_in))
        branch_wl.sort(key=lambda x: -x[0])

        w("| 分支 | 工作量 | 新增 | 删除 | 工程 |")
        w("|------|--------|------|------|------|")
        for bwl, ba, bd, b, repos_in in branch_wl[:10]:
            tags = "+".join(short.get(r, r[:6]) for r in repos_in)
            w(f"| {b} | {fmt(bwl)} | +{fmt(ba)} | -{fmt(bd)} | {tags} |")
        if len(branch_wl) > 10:
            w(f"| *...及其他 {len(branch_wl) - 10} 个分支* | | | | |")
        w("")

    # ---- 3. 分支活跃度排行（辅助视图） ----
    w("## 3. 分支活跃度排行")
    # 按分支聚合
    br_stats = defaultdict(lambda: {"added": 0, "deleted": 0, "authors": set(), "dates": set(), "repos": set()})
    for repo, records in branch_data.items():
        for r in records:
            b = r["branch"]
            br_stats[b]["added"] += r["added"]
            br_stats[b]["deleted"] += r["deleted"]
            br_stats[b]["authors"].add(r["email"])
            br_stats[b]["dates"].add(r["date"])
            br_stats[b]["repos"].add(repo)

    sorted_branches = sorted(br_stats.keys(),
                             key=lambda b: -(br_stats[b]["added"] + int(br_stats[b]["deleted"] * 0.5)))

    w("| 排名 | 分支 | 工作量 | 新增 | 删除 | 覆盖工程 | 参与人数 | 活跃天数 |")
    w("|------|------|--------|------|------|----------|----------|----------|")
    for i, b in enumerate(sorted_branches[:40], 1):
        s = br_stats[b]
        wl = s["added"] + int(s["deleted"] * 0.5)
        tags = "+".join(short.get(r, r[:6]) for r in sorted(s["repos"]))
        w(f"| {i} | {b} | {fmt(wl)} | +{fmt(s['added'])} | -{fmt(s['deleted'])} | {tags} | {len(s['authors'])} | {len(s['dates'])} |")
    w(f"\n*共 {len(sorted_branches)} 个活跃分支*")
    w("")

    w("---")
    w(f"*报告自动生成于 {date_to}*")

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    multi_repo_br = sum(1 for b in br_stats if len(br_stats[b]["repos"]) >= 2)
    print(f"✅ 分支报告: {output_path}")
    print(f"   参与人数: {len(sorted_emails)} | 活跃分支: {len(sorted_branches)} | 跨工程分支: {multi_repo_br}")


def generate_report(commits, hour_records, days, repos, date_from, date_to, output_path, branch_data=None):
    """生成 Markdown 报告，维度按重要性排序"""
    if branch_data is None:
        branch_data = {}
    unique_emails = merge_by_email(commits)
    total_commits = len(commits)
    all_authors = sorted(set(c["author"] for c in commits))
    total_authors = len(all_authors)

    # ---- 预计算 ----
    author_commits = defaultdict(int)
    author_added = defaultdict(int)
    author_deleted = defaultdict(int)
    author_files = defaultdict(set)
    author_dates = defaultdict(set)
    author_repo = defaultdict(lambda: defaultdict(int))

    date_commits = defaultdict(int)
    date_added = defaultdict(int)
    date_deleted = defaultdict(int)
    date_authors = defaultdict(set)

    ext_added = defaultdict(int)
    ext_deleted = defaultdict(int)
    ext_files = defaultdict(set)

    file_touch_count = defaultdict(int)
    file_added = defaultdict(int)
    file_deleted = defaultdict(int)
    file_repo = {}

    commit_sizes = []

    for c in commits:
        a = c["author"]
        d = c["date"]
        r = c["repo"]
        author_commits[a] += 1
        author_dates[a].add(d)
        author_repo[a][r] += 1
        date_commits[d] += 1
        date_authors[d].add(a)

        c_added = 0
        c_deleted = 0
        for f in c["files"]:
            fp = f["path"]
            added = f["added"]
            deleted = f["deleted"]

            author_files[a].add(r + ":" + fp)

            e = ext_of(fp)
            ext_added[e] += added
            ext_deleted[e] += deleted
            ext_files[e].add(r + ":" + fp)

            key = r + ":" + fp
            file_touch_count[key] += 1
            file_added[key] += added
            file_deleted[key] += deleted
            file_repo[key] = r

            if not is_generated(fp):
                author_added[a] += added
                author_deleted[a] += deleted

            date_added[d] += added
            date_deleted[d] += deleted

            c_added += added
            c_deleted += deleted

        commit_sizes.append((c_added + c_deleted, c_added, c_deleted, a, d, c["subject"]))

    lines = []
    w = lines.append

    repos_str = ", ".join(repos)
    w(f"# Git 提交排行榜 — 最近 {days} 天\n")
    w(f"> 统计范围：{date_from} ~ {date_to}")
    w(f"> 工程：{repos_str}")
    w(f"> 总提交数：{total_commits} | 总作者数：{total_authors}（按邮箱去重）\n")

    # ============================================================
    # 维度按重要性排序：
    #   1 人员矩阵（谁在哪干活）  2 代码量（实际产出）
    #   3 活跃天数（投入度）       4 每日趋势（项目脉搏）
    #   5 工程贡献（跨端协作）     6 热点文件（风险热区）
    #   7 最大提交（需关注的大改动）8 提交量（习惯差异大，参考）
    #   9 文件广度  10 文件类型  11 时段分布
    # ============================================================

    # 1. 人员×工程分布矩阵
    w("## 1. 人员×工程分布矩阵（邮箱去重）")
    email_repo = defaultdict(lambda: defaultdict(int))
    for c in commits:
        email_repo[c["email"]][c["repo"]] += 1
    short_repos = [r[:12] for r in repos]
    w("| 邮箱 | 工作量 | 新增 | 删除 | " + " | ".join(short_repos) + " | 跨工程数 |")
    w("|------|--------|------|------|" + "|".join(["------" for _ in repos]) + "|----------|")
    erows = []
    for email in email_repo:
        total = sum(email_repo[email].values())
        added = author_added.get(email, 0)
        deleted = author_deleted.get(email, 0)
        # 工作量 = 新增行 + 0.5 * 删除行（删除也是工作，但权重略低）
        workload = added + int(deleted * 0.5)
        cells = []
        rc = 0
        for r in repos:
            c = email_repo[email].get(r, 0)
            cells.append(str(c) if c > 0 else "")
            if c > 0:
                rc += 1
        erows.append((total, rc, email, cells, workload, added, deleted))
    # 排序：工作量为主，跨工程数为辅
    erows.sort(key=lambda x: (-x[4], -x[1]))
    for total, rc, email, cells, workload, added, deleted in erows:
        w(f"| {email} | {fmt(workload)} | +{fmt(added)} | -{fmt(deleted)} | " + " | ".join(cells) + f" | {rc} |")
    w("")
    multi3 = [x for x in erows if x[1] >= 3]
    multi2 = [x for x in erows if x[1] == 2]
    single = [x for x in erows if x[1] == 1]
    w(f"**共 {len(erows)} 人** — 跨3+工程: {len(multi3)}人 | 跨2工程: {len(multi2)}人 | 仅1工程: {len(single)}人")
    w("")

    # 2. 代码量排行（排除生成代码）
    w("## 2. 代码量排行（排除生成代码）")
    w("| 排名 | 邮箱 | 新增行 | 删除行 | 净增行 | 新增/删除比 |")
    w("|------|------|--------|--------|--------|------------|")
    code_rank = sorted(all_authors, key=lambda a: -(author_added[a] - author_deleted[a]))
    for i, a in enumerate(code_rank, 1):
        ad = author_added[a]
        dl = author_deleted[a]
        net = ad - dl
        ratio = f"{ad/dl:.2f}" if dl > 0 else ("∞" if ad > 0 else "0")
        sign = "+" if net >= 0 else ""
        w(f"| {i} | {a} | {fmt(ad)} | {fmt(dl)} | {sign}{fmt(net)} | {ratio} |")
    w("")

    # 3. 活跃天数排行
    w("## 3. 活跃天数排行")
    w("| 排名 | 邮箱 | 活跃天数 | 活跃日期 |")
    w("|------|------|----------|----------|")
    for i, a in enumerate(sorted(all_authors, key=lambda a: (-len(author_dates[a]), a)), 1):
        dates_sorted = ", ".join(sorted(author_dates[a]))
        w(f"| {i} | {a} | {len(author_dates[a])} | {dates_sorted} |")
    w("")

    # 4. 每日提交趋势
    w("## 4. 每日提交趋势")
    w("| 日期 | 提交数 | 新增行 | 删除行 | 活跃人数 |")
    w("|------|--------|--------|--------|----------|")
    for d in sorted(date_commits.keys()):
        w(f"| {d} | {fmt(date_commits[d])} | {fmt(date_added[d])} | {fmt(date_deleted[d])} | {len(date_authors[d])} |")
    w("")

    # 5. 工程贡献分布
    w("## 5. 工程贡献分布")
    header = "| 邮箱 | " + " | ".join(repos) + " |"
    sep = "|------" + "|------------" * len(repos) + "|"
    w(header)
    w(sep)
    for a in sorted(all_authors, key=lambda a: -author_commits[a]):
        total_a = author_commits[a]
        cells = []
        for r in repos:
            cnt = author_repo[a].get(r, 0)
            pct = cnt / total_a * 100 if total_a else 0
            cells.append(f"{cnt} ({pct:.0f}%)")
        w(f"| {a} | " + " | ".join(cells) + " |")
    w("")

    # 6. 热点文件 Top 15
    w("## 6. 热点文件 Top 15")
    w("| 排名 | 文件路径 | 修改次数 | 新增行 | 删除行 |")
    w("|------|----------|----------|--------|--------|")
    hot_files = sorted(file_touch_count.items(), key=lambda x: -x[1])[:15]
    for i, (key, cnt) in enumerate(hot_files, 1):
        repo = file_repo[key]
        path = key.split(":", 1)[1] if ":" in key else key
        display = truncate_path(repo, path)
        w(f"| {i} | `{display}` | {fmt(cnt)} | {fmt(file_added[key])} | {fmt(file_deleted[key])} |")
    w("")

    # 7. 最大单次提交 Top 10
    w("## 7. 最大单次提交 Top 10")
    w("| 排名 | 邮箱 | 日期 | 提交信息 | 新增行 | 删除行 | 总改动 |")
    w("|------|------|------|----------|--------|--------|--------|")
    commit_sizes.sort(key=lambda x: -x[0])
    for i, (total, added, deleted, author, date, subject) in enumerate(commit_sizes[:10], 1):
        subj = subject[:60] + "..." if len(subject) > 60 else subject
        w(f"| {i} | {author} | {date} | {subj} | {fmt(added)} | {fmt(deleted)} | {fmt(total)} |")
    w("")

    # 8. 提交次数排行（参考，受个人习惯影响大）
    w("## 8. 提交次数排行")
    w("| 排名 | 邮箱 | 提交数 | 占比 |")
    w("|------|------|--------|------|")
    for i, (a, cnt) in enumerate(sorted(author_commits.items(), key=lambda x: -x[1]), 1):
        pct = cnt / total_commits * 100 if total_commits else 0
        w(f"| {i} | {a} | {fmt(cnt)} | {pct:.1f}% |")
    w("")

    # 9. 文件触及广度排行
    w("## 9. 文件触及广度排行")
    w("| 排名 | 邮箱 | 修改文件数 |")
    w("|------|------|----------|")
    for i, a in enumerate(sorted(all_authors, key=lambda a: -len(author_files[a])), 1):
        w(f"| {i} | {a} | {fmt(len(author_files[a]))} |")
    w("")

    # 10. 文件类型排行
    w("## 10. 文件类型排行")
    w("| 排名 | 文件类型 | 修改行数(新增+删除) | 文件数 |")
    w("|------|----------|-------------------|--------|")
    ext_total = {e: ext_added[e] + ext_deleted[e] for e in ext_added}
    for i, (e, total) in enumerate(sorted(ext_total.items(), key=lambda x: -x[1])[:20], 1):
        w(f"| {i} | {e} | {fmt(total)} | {fmt(len(ext_files[e]))} |")
    w("")

    # 11. 提交时段分布
    w("## 11. 提交时段分布")
    w("| 时段 | 提交数 | 占比 | 图示 |")
    w("|------|--------|------|------|")
    hour_counts = defaultdict(int)
    for _, _, _, hour in hour_records:
        hour_counts[hour] += 1
    max_hour_count = max(hour_counts.values()) if hour_counts else 1
    total_hour = sum(hour_counts.values()) or 1
    for h in range(24):
        cnt = hour_counts.get(h, 0)
        pct = cnt / total_hour * 100
        bars = int(cnt / max_hour_count * 20) if max_hour_count > 0 else 0
        w(f"| {h:02d}:00-{h:02d}:59 | {fmt(cnt)} | {pct:.1f}% | {'█' * bars} |")
    w("")

    # 分支统计单独输出到独立文件
    if branch_data:
        branch_output = output_path.replace(".md", "-branches.md")
        generate_branch_report(branch_data, days, date_from, date_to, branch_output)

    w("---")
    w(f"*报告自动生成于 {date_to}*")

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    # stdout 摘要
    print(f"✅ 报告已生成: {output_path}")
    print(f"   总提交: {total_commits} | 总作者: {total_authors}（邮箱去重）")
    print(f"   统计范围: {date_from} ~ {date_to}")

    print(f"   人员分布: 共{len(erows)}人 — 跨3+工程 {len(multi3)}人 | 跨2工程 {len(multi2)}人 | 仅1工程 {len(single)}人")

    top3_code = sorted(all_authors, key=lambda a: -(author_added[a] - author_deleted[a]))[:3]
    print(f"   代码净增 Top3: " + " > ".join(
        f"{a}({'+' if author_added[a]-author_deleted[a]>=0 else ''}{fmt(author_added[a]-author_deleted[a])})"
        for a in top3_code
    ))

    top3_days = sorted(all_authors, key=lambda a: -len(author_dates[a]))[:3]
    print(f"   活跃天数 Top3: " + " > ".join(f"{a}({len(author_dates[a])}d)" for a in top3_days))


def main():
    parser = argparse.ArgumentParser(description="Git 多维度提交排行榜")
    parser.add_argument("--days", type=int, default=7, help="统计最近 N 天")
    parser.add_argument("--workspace", required=True, help="工作空间根目录")
    parser.add_argument("--repos", required=True, help="逗号分隔的工程名")
    parser.add_argument("--data-dir", required=True, help="数据文件目录")
    parser.add_argument("--output", required=True, help="输出 Markdown 文件路径")
    parser.add_argument("--branch-repos", default="", help="需要分支统计的工程名（逗号分隔）")
    args = parser.parse_args()

    repos = [r.strip() for r in args.repos.split(",") if r.strip()]
    branch_repos = [r.strip() for r in args.branch_repos.split(",") if r.strip()]
    today = datetime.now().strftime("%Y-%m-%d")
    date_from = (datetime.now() - timedelta(days=args.days)).strftime("%Y-%m-%d")

    all_commits = []
    all_hours = []
    for repo in repos:
        numstat_file = os.path.join(args.data_dir, f"{repo}_numstat.txt")
        hours_file = os.path.join(args.data_dir, f"{repo}_hours.txt")
        all_commits.extend(parse_numstat(numstat_file, repo))
        all_hours.extend(parse_hours(hours_file))

    # 解析分支数据
    branch_data = {}  # repo -> [{branch, email, date, added, deleted}, ...]
    for repo in branch_repos:
        bfile = os.path.join(args.data_dir, f"{repo}_branches.txt")
        if os.path.exists(bfile):
            records = []
            with open(bfile, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    if not line or "|" not in line:
                        continue
                    parts = line.split("|")
                    if len(parts) >= 5:
                        try:
                            records.append({
                                "branch": parts[0], "email": parts[1], "date": parts[2],
                                "added": int(parts[3]), "deleted": int(parts[4]),
                            })
                        except ValueError:
                            pass
            if records:
                branch_data[repo] = records

    if not all_commits:
        print("⚠️ 无提交数据")
        sys.exit(0)

    generate_report(all_commits, all_hours, args.days, repos, date_from, today, args.output,
                    branch_data=branch_data)


if __name__ == "__main__":
    main()
