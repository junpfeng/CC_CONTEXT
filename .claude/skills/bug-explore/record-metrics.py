#!/usr/bin/env python3
"""
bug-explore 指标写入脚本

将一次 bug-explore 的指标追加到 metrics.jsonl，替代 AI 手拼 JSON。

用法:
  python3 record-metrics.py \
    --fix-result success \
    --version 0.0.3 \
    --module BigWorld_NPC \
    --strategies-matched "NPC / 怪物 / 路人 / 行人" "动画 / 动作 / 播放 / 卡住 / 抽搐 / 滑步" \
    --phase1-actions 8 \
    --phase1-rounds 2 \
    --phase1-actions-cited 5 \
    --phase2-rounds 2 \
    --phase4-retries 0 \
    [--phase2-early-exit] \
    [--failure-reason root_cause_unknown] \
    [--harness-gap "缺少NPC状态采集策略"] \
    [--variant main] \
    [--dry-run]

输出写入的 JSON 到 stdout。
"""

import argparse
import json
import sys
import os
from pathlib import Path
from datetime import datetime, timezone

SCRIPT_DIR = Path(__file__).parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent.parent
METRICS_FILE = PROJECT_ROOT / "docs" / "skills" / "bug-explore-metrics.jsonl"


def main():
    parser = argparse.ArgumentParser(description="Record bug-explore metrics")
    parser.add_argument("--fix-result", required=True, choices=["success", "failed", "not_a_bug"])
    parser.add_argument("--version", required=True, help="Game version (e.g. 0.0.3)")
    parser.add_argument("--module", required=True, help="Bug module name (e.g. BigWorld_NPC)")
    parser.add_argument("--strategies-matched", nargs="*", default=[], help="Matched strategy keywords")
    parser.add_argument("--phase1-actions", type=int, default=0)
    parser.add_argument("--phase1-rounds", type=int, default=1)
    parser.add_argument("--phase1-actions-cited", type=int, default=0)
    parser.add_argument("--phase2-rounds", type=int, default=0)
    parser.add_argument("--phase2-early-exit", action="store_true")
    parser.add_argument("--phase4-retries", type=int, default=0)
    parser.add_argument("--failure-reason", default=None, help="root_cause_unknown|fix_regression|compile_error")
    parser.add_argument("--harness-gap", default=None, help="Harness gap description")
    parser.add_argument("--variant", default="main", help="SKILL variant used")
    parser.add_argument("--dry-run", action="store_true", help="Print but don't write")

    args = parser.parse_args()

    record = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "version": args.version,
        "module": args.module,
        "fix_result": args.fix_result,
        "failure_reason": args.failure_reason,
        "harness_gap": args.harness_gap,
        "strategies_matched": args.strategies_matched,
        "phase1_actions": args.phase1_actions,
        "phase1_rounds": args.phase1_rounds,
        "phase1_actions_cited": args.phase1_actions_cited,
        "phase2_rounds": args.phase2_rounds,
        "phase2_early_exit": args.phase2_early_exit,
        "phase4_retries": args.phase4_retries,
        "variant": args.variant,
    }

    json_line = json.dumps(record, ensure_ascii=False)

    if args.dry_run:
        print(json_line)
        return 0

    # 确保目录存在
    METRICS_FILE.parent.mkdir(parents=True, exist_ok=True)

    with open(METRICS_FILE, "a", encoding="utf-8") as f:
        f.write(json_line + "\n")

    # 写入完成标记，供 delivery-quality-check.sh Stop hook 验证 Phase 4 步骤完成度
    import tempfile
    marker = os.path.join(tempfile.gettempdir(), ".bug_explore_metrics_recorded")
    with open(marker, "w") as mf:
        mf.write(str(int(datetime.now(timezone.utc).timestamp())))

    print(json_line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
