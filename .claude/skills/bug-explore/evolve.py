#!/usr/bin/env python3
"""
bug-explore 诊断策略自动进化脚本

读取 metrics.jsonl，计算策略有效率，自动更新 diagnostic-strategies.md 中的计数和标记。
由 SKILL.md Step 5 调用，替代人工分析。

用法:
  python3 .claude/skills/bug-explore/evolve.py [--dry-run] [--apply]

输出 JSON 到 stdout:
{
  "strategies_updated": 3,
  "strategies_marked_ineffective": ["声音 / 音效 / 音乐"],
  "recommendations": ["新增策略: xxx", "替换低效策略: yyy → zzz"],
  "derived_metrics": { "diagnostic_hit_rate": 0.45, "fix_success_rate": 0.75, ... }
}
"""

import json
import re
import sys
import os
from pathlib import Path
from datetime import datetime

SCRIPT_DIR = Path(__file__).parent
STRATEGIES_FILE = SCRIPT_DIR / "diagnostic-strategies.md"
METRICS_SCHEMA = SCRIPT_DIR / "metrics-schema.md"

# metrics.jsonl 在 docs/skills/ 下
PROJECT_ROOT = SCRIPT_DIR.parent.parent.parent  # .claude/skills/bug-explore -> project root
METRICS_FILE = PROJECT_ROOT / "docs" / "skills" / "bug-explore-metrics.jsonl"
CHANGELOG_FILE = PROJECT_ROOT / "docs" / "skills" / "bug-explore-changelog.md"

# 阈值
MIN_HITS_FOR_EVAL = 5       # 最少命中次数才评估有效率
INEFFECTIVE_THRESHOLD = 0.2  # 有效率低于 20% 标记低效
MAX_STRATEGIES = 25          # 策略表上限
RECENT_N = 10                # 读取最近 N 条指标
AB_MIN_SAMPLES = 5           # A/B 每组最少样本数（降低以加速迭代）
AB_WIN_MARGIN = 0.05         # 变体综合得分需优于主版本 5% 才合并
AB_EARLY_STOP_N = 3          # 前 N 次若变体明显差（>15%），提前淘汰
AB_EARLY_STOP_MARGIN = 0.15  # 早停判定差距阈值
VARIANT_ALERT_THRESHOLD = 3  # 连续 N 次相同告警才创建变体

# 健康阈值
HEALTH_THRESHOLDS = {
    "diagnostic_hit_rate": 0.4,
    "fix_success_rate": 0.7,
    "avg_question_rounds": 2.5,
    "two_round_collection_ratio": 0.3,
}


def load_metrics(n=RECENT_N):
    """读取最近 N 条指标"""
    if not METRICS_FILE.exists():
        return []
    lines = METRICS_FILE.read_text(encoding="utf-8").strip().split("\n")
    records = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return records[-n:]


def compute_derived_metrics(records):
    """计算派生指标"""
    if not records:
        return {}

    total = len(records)
    success = sum(1 for r in records if r.get("fix_result") == "success")
    total_actions = sum(r.get("phase1_actions", 0) for r in records)
    cited_actions = sum(r.get("phase1_actions_cited", 0) for r in records)
    q_rounds = [r.get("phase2_rounds", 0) for r in records if r.get("phase2_rounds")]
    two_round = sum(1 for r in records if r.get("phase1_rounds", 1) >= 2)

    return {
        "diagnostic_hit_rate": cited_actions / total_actions if total_actions > 0 else 0,
        "fix_success_rate": success / total if total > 0 else 0,
        "avg_question_rounds": sum(q_rounds) / len(q_rounds) if q_rounds else 0,
        "two_round_collection_ratio": two_round / total if total > 0 else 0,
        "total_records": total,
    }


def check_health(derived):
    """对比健康阈值，返回不健康的指标"""
    alerts = []
    for key, threshold in HEALTH_THRESHOLDS.items():
        val = derived.get(key, 0)
        if key == "avg_question_rounds" or key == "two_round_collection_ratio":
            # 越低越好
            if val > threshold:
                alerts.append({"metric": key, "value": round(val, 3), "threshold": threshold, "direction": "too_high"})
        else:
            # 越高越好
            if val < threshold:
                alerts.append({"metric": key, "value": round(val, 3), "threshold": threshold, "direction": "too_low"})
    return alerts


def parse_strategies_table(content):
    """解析 diagnostic-strategies.md 表格，返回策略列表"""
    strategies = []
    lines = content.split("\n")
    in_table = False
    header_seen = 0

    for i, line in enumerate(lines):
        if line.startswith("| 关键词"):
            in_table = True
            header_seen = 0
            continue
        if in_table and line.startswith("|---"):
            header_seen += 1
            continue
        if in_table and line.startswith("|"):
            cols = [c.strip() for c in line.split("|")]
            # cols[0] is empty (before first |), cols[-1] is empty (after last |)
            cols = [c for c in cols if c != ""]
            if len(cols) >= 5:
                keyword = cols[0].replace("**", "")
                actions = cols[1]
                tools = cols[2]
                try:
                    hits = int(cols[3])
                except (ValueError, IndexError):
                    hits = 0
                try:
                    effective = int(cols[4])
                except (ValueError, IndexError):
                    effective = 0
                strategies.append({
                    "keyword": keyword,
                    "actions": actions,
                    "tools": tools,
                    "hits": hits,
                    "effective": effective,
                    "line_num": i,
                })
        elif in_table and not line.startswith("|"):
            in_table = False

    return strategies


def update_strategy_counts(content, records):
    """根据 metrics 记录更新策略表中的命中/有效计数"""
    strategies = parse_strategies_table(content)
    if not strategies:
        return content, []

    # 从 metrics 聚合每个策略的命中和有效
    strategy_deltas = {}
    for r in records:
        matched = r.get("strategies_matched", [])
        cited = r.get("phase1_actions_cited", 0)
        total = r.get("phase1_actions", 0)
        # 简化：如果有 cited，则所有 matched 策略都算有效
        has_citation = cited > 0 and r.get("fix_result") == "success"
        for kw in matched:
            if kw not in strategy_deltas:
                strategy_deltas[kw] = {"hits": 0, "effective": 0}
            strategy_deltas[kw]["hits"] += 1
            if has_citation:
                strategy_deltas[kw]["effective"] += 1

    # 注意：计数已经在每次 Phase 1 和 Step 4.5 中增量更新
    # 这里只做校验和标记，不重复累加

    return content, strategies


def find_ineffective_strategies(strategies):
    """找出低效策略"""
    ineffective = []
    for s in strategies:
        if s["hits"] >= MIN_HITS_FOR_EVAL:
            rate = s["effective"] / s["hits"] if s["hits"] > 0 else 0
            if rate < INEFFECTIVE_THRESHOLD:
                ineffective.append({
                    "keyword": s["keyword"],
                    "hits": s["hits"],
                    "effective": s["effective"],
                    "rate": round(rate, 3),
                })
    return ineffective


def find_harness_gaps(records):
    """从失败记录中提取重复的 harness_gap"""
    gaps = {}
    for r in records:
        gap = r.get("harness_gap")
        if gap:
            gaps[gap] = gaps.get(gap, 0) + 1
    # 返回出现 >=2 次的 gap
    return {k: v for k, v in gaps.items() if v >= 2}


def generate_recommendations(ineffective, harness_gaps, derived, alerts):
    """生成改进建议"""
    recs = []

    for s in ineffective:
        recs.append(f"标记低效策略: '{s['keyword']}' (命中{s['hits']}次, 有效率{s['rate']*100:.0f}%)")

    for gap, count in harness_gaps.items():
        recs.append(f"重复 harness 缺口 ({count}次): {gap}")

    for alert in alerts:
        if alert["direction"] == "too_low":
            recs.append(f"指标偏低: {alert['metric']}={alert['value']} (阈值{alert['threshold']})")
        else:
            recs.append(f"指标偏高: {alert['metric']}={alert['value']} (阈值{alert['threshold']})")

    return recs


def apply_ineffective_marks(content, ineffective_keywords):
    """在 diagnostic-strategies.md 中给低效策略加 ⚠️ 标记"""
    lines = content.split("\n")
    changes = []
    for i, line in enumerate(lines):
        if not line.startswith("|"):
            continue
        for kw in ineffective_keywords:
            clean_kw = kw.replace("⚠️ ", "")
            if clean_kw in line and "⚠️" not in line:
                lines[i] = line.replace(f"**{clean_kw}**", f"**⚠️ {clean_kw}**", 1)
                if lines[i] == line:
                    lines[i] = line.replace(f"| {clean_kw} |", f"| ⚠️ {clean_kw} |", 1)
                changes.append(f"标记低效: {clean_kw}")
    return "\n".join(lines), changes


def replace_ineffective_with_suggestions(content, ineffective, suggestions):
    """用候选策略替换已标记 ⚠️ 的低效策略（全自动替换）"""
    if not suggestions or not ineffective:
        return content, []

    lines = content.split("\n")
    changes = []
    replaced = 0

    for s in suggestions:
        if replaced >= 3:  # 单次最多替换 3 条
            break
        if s.get("tools") == "待定":  # 跳过需要手动设计的
            continue

        # 找一个已标记 ⚠️ 的行替换
        for i, line in enumerate(lines):
            if "⚠️" in line and line.startswith("|"):
                new_line = f"| **{s['keyword']}** | {s['actions']} | {s['tools']} | 0 | 0 |"
                old_kw = re.search(r'⚠️\s*(.+?)\*\*', line)
                old_name = old_kw.group(1).strip() if old_kw else "unknown"
                lines[i] = new_line
                changes.append(f"替换: '{old_name}' → '{s['keyword']}'")
                replaced += 1
                break

    return "\n".join(lines), changes


def _load_alert_history():
    """读取跨次累积的告警历史"""
    history_file = SCRIPT_DIR / ".alert-history.json"
    if history_file.exists():
        try:
            return json.loads(history_file.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            pass
    return {}


def _save_alert_history(history):
    """保存告警历史"""
    history_file = SCRIPT_DIR / ".alert-history.json"
    history_file.write_text(json.dumps(history, ensure_ascii=False, indent=2), encoding="utf-8")


def auto_create_variant(alerts, content):
    """当连续告警时自动创建 SKILL.md 变体"""
    # 检查是否已有活跃变体
    existing = list(SCRIPT_DIR.glob("SKILL.variant-*.md"))
    if existing:
        return None, "已有活跃变体，跳过"

    # 更新跨次累积的告警计数
    history = _load_alert_history()
    current_metrics = {a["metric"] for a in alerts}

    for metric in current_metrics:
        history[metric] = history.get(metric, 0) + 1
    # 不在本次告警中的指标重置为 0（不再连续）
    for metric in list(history.keys()):
        if metric not in current_metrics:
            history[metric] = 0
    _save_alert_history(history)

    if not alerts:
        return None, "无告警"

    # 找连续告警次数最高的指标
    top_metric = max(current_metrics, key=lambda m: history.get(m, 0))
    consecutive = history.get(top_metric, 0)

    if consecutive < VARIANT_ALERT_THRESHOLD:
        return None, f"告警连续次数不足 ({top_metric}={consecutive}/{VARIANT_ALERT_THRESHOLD})"

    # 根据告警类型生成变体
    VARIANT_TEMPLATES = {
        "diagnostic_hit_rate": {
            "name": "aggressive-collection",
            "description": "增加采集预算从12到18，提升诊断命中率",
            "patch": "action_budget = 18        # 提升采集预算（原12）",
        },
        "fix_success_rate": {
            "name": "double-retry",
            "description": "失败重试从1次增加到2次，提升修复成功率",
            "patch": "# 最多 2 次重试（原1次）",
        },
        "avg_question_rounds": {
            "name": "early-fix",
            "description": "提问轮数软上限从4降到2，更早进入修复",
            "patch": "# 轮数软上限 2（原4）",
        },
        "two_round_collection_ratio": {
            "name": "focused-collection",
            "description": "首轮采集预算从8提升到10，减少二轮采集",
            "patch": "budget=min(action_budget, 10)  # 首轮预算提升（原8）",
        },
    }

    template = VARIANT_TEMPLATES.get(top_metric)
    if not template:
        return None, f"无模板: {top_metric}"

    variant_name = template["name"]
    variant_file = SCRIPT_DIR / f"SKILL.variant-{variant_name}.md"

    # 生成变体内容：复制主 SKILL + 在头部加变体说明 + 应用 patch 注释
    variant_content = f"""---
name: bug-explore (variant: {variant_name})
description: "{template['description']}"
variant_of: SKILL.md
hypothesis: "{top_metric} 告警 → {template['description']}"
created: "{datetime.now().strftime('%Y-%m-%d')}"
---

# ⚠️ 这是 A/B 实验变体，不是主版本

**假设**：{template['description']}
**变更点**：`{template['patch']}`
**判定标准**：≥5 样本后比较主版本，综合得分（命中率×0.4+修复率×0.6）优于主版本 >5% 则合并

---

以下内容与主 SKILL.md 相同，仅上述变更点不同。执行时加载主 SKILL.md 但应用上述变更。
"""

    return {"file": variant_file, "name": variant_name, "content": variant_content, "reason": template["description"]}, None


def suggest_replacement_strategies(harness_gaps, ineffective):
    """从 harness_gap 模式自动生成候选替代策略"""
    # 关键词→诊断动作的模式映射
    GAP_TO_STRATEGY = {
        "NPC": {"keyword": "NPC状态 / NPC数据", "actions": "① 读取NPC实体全部组件数据 ② 对比服务端NPC状态 ③ 检查FSM当前状态和转换历史", "tools": "MCP script-execute + Grep srv_log"},
        "动画": {"keyword": "动画层 / Animancer状态", "actions": "① 读取所有Animancer层权重和State ② 多帧采样对比 ③ 检查FSM转换条件", "tools": "MCP script-execute ×3"},
        "同步": {"keyword": "帧同步 / 状态同步", "actions": "① 服务端sync日志 ② 客户端收包日志 ③ 对比服务端/客户端实体状态", "tools": "Grep srv_log + MCP console-get-logs + script-execute"},
        "配置": {"keyword": "配置表 / 打表", "actions": "① Excel MCP读取相关配置表 ② grep配置加载错误 ③ 对比运行时值与配置表值", "tools": "MCP excel_read + Grep + script-execute"},
        "资源": {"keyword": "资源加载 / Prefab / 材质", "actions": "① grep资源加载错误 ② 检查Prefab是否存在 ③ 读取ResourceManager加载队列", "tools": "Grep + Glob + MCP script-execute"},
        "碰撞": {"keyword": "碰撞 / 物理 / Raycast", "actions": "① 读取碰撞体列表 ② Raycast测试地面 ③ 检查LayerMask配置", "tools": "MCP script-execute ×3"},
        "计时": {"keyword": "计时器 / 冷却 / 延迟", "actions": "① 读取Timer/Cooldown组件状态 ② 多帧采样对比计时器值 ③ 服务端对应handler日志", "tools": "MCP script-execute ×2 + Grep"},
    }

    suggestions = []

    # 从 harness_gap 关键词匹配
    for gap_text in harness_gaps:
        for pattern, strategy in GAP_TO_STRATEGY.items():
            if pattern in gap_text:
                suggestions.append({
                    "source": f"harness_gap: {gap_text}",
                    "keyword": strategy["keyword"],
                    "actions": strategy["actions"],
                    "tools": strategy["tools"],
                })
                break

    # 从低效策略推导：如果低效策略的动作太泛，建议更精确的替代
    for s in ineffective:
        if s["rate"] == 0 and s["hits"] >= 5:
            suggestions.append({
                "source": f"零有效率策略: {s['keyword']}",
                "keyword": f"(替换 {s['keyword']})",
                "actions": "需 AI 基于最近 bug 经验手动设计",
                "tools": "待定",
            })

    return suggestions


def check_ab_experiments(records):
    """检测 A/B 实验是否达到样本阈值，返回合并/删除建议"""

    # 按 variant 分组
    groups = {}
    for r in records:
        v = r.get("variant", "main")
        if v not in groups:
            groups[v] = []
        groups[v].append(r)

    if len(groups) <= 1:
        return {"status": "no_experiment", "variants": list(groups.keys())}

    # 找到非 main 的变体
    results = []
    main_records = groups.get("main", [])
    main_metrics = compute_derived_metrics(main_records) if main_records else {}

    for variant_name, variant_records in groups.items():
        if variant_name in ("main", "seed-eval"):
            continue

        variant_metrics = compute_derived_metrics(variant_records)
        main_n = len(main_records)
        variant_n = len(variant_records)

        # Bayesian 早停：前 N 次若变体明显差，提前淘汰
        if variant_n >= AB_EARLY_STOP_N and (main_n < AB_MIN_SAMPLES or variant_n < AB_MIN_SAMPLES):
            early_main = compute_derived_metrics(main_records[-AB_EARLY_STOP_N:]) if len(main_records) >= AB_EARLY_STOP_N else {}
            early_variant = compute_derived_metrics(variant_records[-AB_EARLY_STOP_N:])
            em_score = early_main.get("diagnostic_hit_rate", 0) * 0.4 + early_main.get("fix_success_rate", 0) * 0.6
            ev_score = early_variant.get("diagnostic_hit_rate", 0) * 0.4 + early_variant.get("fix_success_rate", 0) * 0.6
            if em_score - ev_score > AB_EARLY_STOP_MARGIN:
                results.append({
                    "variant": variant_name,
                    "action": "delete",
                    "reason": f"早停淘汰: 前{AB_EARLY_STOP_N}次变体明显差 ({ev_score:.3f} vs {em_score:.3f}, 差距>{AB_EARLY_STOP_MARGIN})",
                    "main_n": main_n,
                    "variant_n": variant_n,
                })
                continue

        if main_n < AB_MIN_SAMPLES or variant_n < AB_MIN_SAMPLES:
            results.append({
                "variant": variant_name,
                "action": "wait",
                "reason": f"样本不足 (main={main_n}, variant={variant_n}, 需各≥{AB_MIN_SAMPLES})",
                "main_n": main_n,
                "variant_n": variant_n,
            })
            continue

        # 比较核心指标
        main_hit = main_metrics.get("diagnostic_hit_rate", 0)
        variant_hit = variant_metrics.get("diagnostic_hit_rate", 0)
        main_fix = main_metrics.get("fix_success_rate", 0)
        variant_fix = variant_metrics.get("fix_success_rate", 0)

        # 综合得分：命中率 40% + 修复率 60%
        main_score = main_hit * 0.4 + main_fix * 0.6
        variant_score = variant_hit * 0.4 + variant_fix * 0.6

        if variant_score > main_score + AB_WIN_MARGIN:
            action = "merge"
            reason = f"变体优于主版本 ({variant_score:.3f} > {main_score:.3f})"
        elif variant_score < main_score - AB_WIN_MARGIN:
            action = "delete"
            reason = f"变体劣于主版本 ({variant_score:.3f} < {main_score:.3f})"
        else:
            action = "delete"
            reason = f"无显著差异 ({variant_score:.3f} ≈ {main_score:.3f})，删除变体"

        results.append({
            "variant": variant_name,
            "action": action,
            "reason": reason,
            "main_score": round(main_score, 3),
            "variant_score": round(variant_score, 3),
            "main_n": main_n,
            "variant_n": variant_n,
        })

    return {"status": "evaluated", "experiments": results}


def main():
    dry_run = "--dry-run" in sys.argv
    apply = "--apply" in sys.argv
    suggest = "--suggest" in sys.argv
    check_ab = "--check-ab" in sys.argv

    # 1. 加载数据
    records = load_metrics()
    derived = compute_derived_metrics(records)
    alerts = check_health(derived)

    # 2. 分析策略
    content = ""
    if STRATEGIES_FILE.exists():
        content = STRATEGIES_FILE.read_text(encoding="utf-8")
        _, strategies = update_strategy_counts(content, records)
        ineffective = find_ineffective_strategies(strategies)
    else:
        strategies = []
        ineffective = []

    # 3. 分析 harness gaps
    harness_gaps = find_harness_gaps(records)

    # 4. 生成建议
    recommendations = generate_recommendations(ineffective, harness_gaps, derived, alerts)

    # 5. --suggest: 生成候选替代策略（必须在 apply 之前，apply 依赖此结果）
    suggested_strategies = []
    if suggest:
        suggested_strategies = suggest_replacement_strategies(
            list(harness_gaps.keys()), ineffective
        )

    # 6. --apply: 直接写回 diagnostic-strategies.md
    applied_changes = []
    if apply and not dry_run and content:
        current_content = content

        # 6a. 标记低效策略
        if ineffective:
            ineffective_kws = [s["keyword"] for s in ineffective]
            current_content, mark_changes = apply_ineffective_marks(current_content, ineffective_kws)
            applied_changes.extend(mark_changes)

        # 6b. --suggest + --apply: 自动替换低效策略为候选
        if suggest and suggested_strategies:
            current_content, replace_changes = replace_ineffective_with_suggestions(
                current_content, ineffective, suggested_strategies
            )
            applied_changes.extend(replace_changes)

        if applied_changes:
            STRATEGIES_FILE.write_text(current_content, encoding="utf-8")

            CHANGELOG_FILE.parent.mkdir(parents=True, exist_ok=True)
            today = datetime.now().strftime("%Y-%m-%d")
            entry = f"- {today} [evolve.py --apply] {'; '.join(applied_changes)}\n"
            with open(CHANGELOG_FILE, "a", encoding="utf-8") as f:
                f.write(entry)

    # 6c. --apply: 自动创建变体（当有告警且无活跃变体时）
    variant_created = None
    if apply and not dry_run and alerts:
        variant_info, skip_reason = auto_create_variant(alerts, content)
        if variant_info:
            variant_info["file"].write_text(variant_info["content"], encoding="utf-8")
            variant_created = {"name": variant_info["name"], "reason": variant_info["reason"]}

            CHANGELOG_FILE.parent.mkdir(parents=True, exist_ok=True)
            today = datetime.now().strftime("%Y-%m-%d")
            entry = f"- {today} [evolve.py --apply] 自动创建变体 {variant_info['name']}: {variant_info['reason']}\n"
            with open(CHANGELOG_FILE, "a", encoding="utf-8") as f:
                f.write(entry)

    # 7. --check-ab: 检测 A/B 实验状态
    ab_result = {}
    if check_ab:
        all_records = load_metrics(n=100)  # A/B 需要更多数据
        ab_result = check_ab_experiments(all_records)

        # --apply + --check-ab: 自动删除应删的变体文件
        if apply and not dry_run and ab_result.get("experiments"):
            for exp in ab_result["experiments"]:
                variant_file = SCRIPT_DIR / f"SKILL.variant-{exp['variant']}.md"
                if exp["action"] == "delete" and variant_file.exists():
                    variant_file.unlink()
                    ab_result.setdefault("auto_deleted", []).append(exp["variant"])

                    CHANGELOG_FILE.parent.mkdir(parents=True, exist_ok=True)
                    today = datetime.now().strftime("%Y-%m-%d")
                    entry = f"- {today} [evolve.py --check-ab] 删除变体 {exp['variant']}: {exp['reason']}\n"
                    with open(CHANGELOG_FILE, "a", encoding="utf-8") as f:
                        f.write(entry)

    # 8. 输出结果
    result = {
        "derived_metrics": {k: round(v, 3) if isinstance(v, float) else v for k, v in derived.items()},
        "health_alerts": alerts,
        "strategies_total": len(strategies),
        "strategies_ineffective": [s["keyword"] for s in ineffective],
        "harness_gaps_repeated": harness_gaps,
        "recommendations": recommendations,
        "applied_changes": applied_changes,
        "suggested_strategies": suggested_strategies,
        "ab_experiment": ab_result,
        "dry_run": dry_run,
        "variant_created": variant_created,
        "apply": apply,
        "suggest": suggest,
        "check_ab": check_ab,
    }

    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
