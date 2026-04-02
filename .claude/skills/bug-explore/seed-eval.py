#!/usr/bin/env python3
"""
从 docs/bugs/ 历史 bug 记录中提取种子数据，模拟策略匹配，写入 metrics.jsonl。

用于 bootstrap 进化循环——让 evolve.py 有数据可分析。

用法:
  python3 .claude/skills/bug-explore/seed-eval.py [--dry-run]

逻辑:
  1. 扫描 docs/bugs/{version}/{module}/ 下的 bug 描述文件
  2. 从描述中提取关键词，模拟 diagnostic-strategies.md 的匹配
  3. 从 fixed.md / fix-log.md 判断修复结果
  4. 写入 metrics.jsonl（标记 variant="seed-eval"）
"""

import json
import re
import sys
from pathlib import Path
from datetime import datetime, timezone

SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent.parent
BUGS_DIR = PROJECT_ROOT / "docs" / "bugs"
METRICS_FILE = PROJECT_ROOT / "docs" / "skills" / "bug-explore-metrics.jsonl"
STRATEGIES_FILE = SCRIPT_DIR / "diagnostic-strategies.md"


def load_strategy_keywords():
    """从 diagnostic-strategies.md 提取所有策略关键词"""
    if not STRATEGIES_FILE.exists():
        return []
    content = STRATEGIES_FILE.read_text(encoding="utf-8")
    keywords = []
    for line in content.split("\n"):
        if line.startswith("|") and "**" in line:
            # 提取 **关键词** 部分
            match = re.search(r'\*\*(.+?)\*\*', line)
            if match:
                kw_str = match.group(1).replace("⚠️ ", "")
                # 每个 / 分隔的都是一个关键词
                kws = [k.strip() for k in kw_str.split("/")]
                keywords.append({"raw": kw_str, "parts": kws})
    return keywords


def match_strategies(text, all_strategies):
    """模拟 Phase 1 策略匹配"""
    matched = []
    for s in all_strategies:
        for kw in s["parts"]:
            if kw.lower() in text.lower():
                matched.append(s["raw"])
                break
    return matched


def scan_bug_files():
    """扫描所有 bug 描述文件，提取 bug 记录"""
    bugs = []
    if not BUGS_DIR.exists():
        return bugs

    for version_dir in sorted(BUGS_DIR.iterdir()):
        if not version_dir.is_dir() or version_dir.name.startswith("."):
            continue
        version = version_dir.name

        for module_dir in sorted(version_dir.iterdir()):
            if not module_dir.is_dir():
                continue
            module = module_dir.name

            # 收集 bug 描述文本
            description_text = ""

            # 读取模块级 tracker 文件
            tracker = module_dir / f"{module}.md"
            if tracker.exists():
                description_text += tracker.read_text(encoding="utf-8")

            # 读取子目录中的 bug 描述
            for sub in sorted(module_dir.iterdir()):
                if sub.is_dir():
                    for f in sub.iterdir():
                        if f.suffix == ".md" and "fix-review" not in f.name and "fix-log" not in f.name:
                            description_text += "\n" + f.read_text(encoding="utf-8")
                elif sub.suffix == ".md" and sub.name != f"{module}.md":
                    if "fix-review" not in sub.name and "fix-log" not in sub.name and "batch-fix" not in sub.name:
                        description_text += "\n" + sub.read_text(encoding="utf-8")

            if not description_text.strip():
                continue

            # 判断修复结果
            fixed_file = module_dir / "fixed.md"
            has_fix = fixed_file.exists() and fixed_file.stat().st_size > 10
            # 也检查子目录中的 fix-log
            if not has_fix:
                for sub in module_dir.rglob("fix-log.md"):
                    if sub.stat().st_size > 10:
                        has_fix = True
                        break

            # 统计 bug 数量（通过 [x] 和 [ ] 标记）
            fixed_count = len(re.findall(r'\[x\]', description_text, re.IGNORECASE))
            unfixed_count = len(re.findall(r'\[ \]', description_text))

            bugs.append({
                "version": version,
                "module": module,
                "description": description_text[:3000],  # 截断
                "has_fix": has_fix,
                "fixed_count": fixed_count,
                "unfixed_count": unfixed_count,
            })

    return bugs


def main():
    dry_run = "--dry-run" in sys.argv

    strategies = load_strategy_keywords()
    bugs = scan_bug_files()

    if not bugs:
        print(json.dumps({"error": "No bug records found", "bugs_dir": str(BUGS_DIR)}, ensure_ascii=False))
        return 1

    records = []
    for bug in bugs:
        matched = match_strategies(bug["description"], strategies)

        # 模拟指标
        record = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "version": bug["version"],
            "module": bug["module"],
            "fix_result": "success" if bug["has_fix"] else "failed",
            "failure_reason": None if bug["has_fix"] else "root_cause_unknown",
            "harness_gap": None,
            "strategies_matched": matched,
            "phase1_actions": len(matched) * 3,  # 估算：每策略约 3 个动作
            "phase1_rounds": 1,
            "phase1_actions_cited": len(matched) * 2 if bug["has_fix"] else 0,  # 估算
            "phase2_rounds": 2,  # 估算
            "phase2_early_exit": False,
            "phase4_retries": 0,
            "variant": "seed-eval",
        }
        records.append(record)

    result = {
        "bugs_scanned": len(bugs),
        "records_generated": len(records),
        "strategies_available": len(strategies),
        "dry_run": dry_run,
    }

    if not dry_run:
        METRICS_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(METRICS_FILE, "a", encoding="utf-8") as f:
            for r in records:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
        result["written_to"] = str(METRICS_FILE)

    # 输出摘要
    for r in records:
        result.setdefault("records", []).append({
            "version": r["version"],
            "module": r["module"],
            "fix_result": r["fix_result"],
            "strategies_matched": r["strategies_matched"],
            "phase1_actions": r["phase1_actions"],
            "phase1_actions_cited": r["phase1_actions_cited"],
        })

    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
