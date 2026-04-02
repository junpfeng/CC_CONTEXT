#!/usr/bin/env python3
"""
bug-explore A/B 变体选择器

扫描变体文件，机械随机选择执行版本。

用法:
  python3 select-variant.py

输出 JSON:
  {"variant": "main", "skill_file": "SKILL.md"}
  或
  {"variant": "aggressive-collection", "skill_file": "SKILL.variant-aggressive-collection.md"}
"""

import glob
import json
import random
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent


def main():
    # 扫描变体文件
    variants = list(SCRIPT_DIR.glob("SKILL.variant-*.md"))

    if not variants:
        result = {"variant": "main", "skill_file": "SKILL.md"}
    else:
        # 50/50 随机选择主版本或变体（只支持 1 个活跃变体）
        variant_file = variants[0]  # 安全约束：同时最多 1 个
        variant_name = variant_file.stem.replace("SKILL.variant-", "")

        if random.random() < 0.5:
            result = {"variant": "main", "skill_file": "SKILL.md"}
        else:
            result = {"variant": variant_name, "skill_file": variant_file.name}

    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
