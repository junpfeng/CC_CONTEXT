#!/bin/bash
# Hook: Stop (command type)
# 交付质量守卫：检查 Claude 即将交付的内容是否违反自主闭环原则
# 通过上下文感知检测，排除引用/描述/测试结果中的误报
# exit 0 = 允许停止, exit 2 = 阻止停止（强制继续）

INPUT=$(cat 2>/dev/null || true)

if [ -z "$INPUT" ]; then
    exit 0
fi

# 用 Python 做上下文感知检测，纯关键词匹配误报太多
RESULT=$(echo "$INPUT" | python3 -X utf8 -c '
import sys, re

text = sys.stdin.read()
lines = text.splitlines()
violations = []

# 排除模式：代码块、表格行、测试输出引用、hook 描述
def is_context_line(line):
    """判断该行是否为引用/描述上下文（不应触发检测）"""
    stripped = line.strip()
    # JSON 元数据行（Stop hook stdin 包含 session_id/transcript 等 JSON）
    if stripped.startswith("{") or stripped.startswith(chr(34)):
        return True
    # 代码块内容
    if stripped.startswith("`") or stripped.startswith("```"):
        return True
    # 表格行
    if stripped.startswith("|"):
        return True
    # 测试结果引用（→、->、exit、echo）
    if any(x in stripped for x in ["→", "->", "exit 2", "exit 0", "echo ", "EXIT:"]):
        return True
    # 引用块
    if stripped.startswith(">"):
        return True
    # hook/脚本描述行（包含 .sh、hook、检测到）
    if re.search(r"\.(sh|py)\b", stripped) and ("阻止" in stripped or "放行" in stripped):
        return True
    return False

# 只检测非上下文行
active_lines = [l for l in lines if not is_context_line(l)]
active_text = "\n".join(active_lines)

# === 检查1: 未解决的阻塞项（必须是陈述性的，不是引用） ===
unresolved_patterns = [
    (r"(?:存在|有|还有|剩余).*(?:阻塞|待解决|未解决)", "存在未解决的阻塞项"),
    (r"暂时跳过", "暂时跳过"),
    (r"后续(?:处理|再|补充)", "后续处理"),
    (r"(?:暂未|尚未)(?:完成|实现|解决)", "暂未完成"),
    (r"待(?:补充|完善|实现|处理)", "待补充/待完善"),
]
for pat, desc in unresolved_patterns:
    for line in active_lines:
        if re.search(pat, line):
            violations.append(f"未解决事项：{desc}（{line.strip()[:60]}）")
            break

# === 检查2: 把问题抛给用户 ===
defer_patterns = [
    (r"(?:需要|等待)你", "需要你/等待你"),
    (r"请你(?!放心)", "请你"),  # "请你放心"不算
    (r"(?:是否|要不要)要我", "是否要我"),
    (r"需要我.{0,10}吗", "需要我...吗（反向询问）"),
    (r"要我.{0,10}吗", "要我...吗（反向询问）"),
    (r"你(?:手动|自己|来)", "你手动/你自己"),
    (r"(?:建议|推荐)你", "建议你"),
    (r"请(?:确认|检查)", "请确认/请检查"),
    (r"可以告诉我", "可以告诉我"),
    (r"让我知道", "让我知道"),
    (r"如果(?:需要我|你想|你需要)", "如果需要我/如果你想"),
    (r"你可以决定", "你可以决定"),
    (r"确认.*(?:可以|开始|继续|执行)\？", "确认是否执行（应直接做）"),
    # 请求用户许可执行技术动作（应直接做）
    (r"要(?:现在|我)?.*(?:重启|验证|测试|编译|登录|运行|部署|推送|提交).*吗[？?]", "请求许可执行技术动作（应直接做）"),
    (r"(?:是否|要不要).*(?:重启|验证|测试|编译|登录|运行|部署|推送|提交)", "询问是否执行技术动作（应直接做）"),
    (r"需要.*(?:重启|验证|测试|编译|登录|运行|部署|推送|提交).*吗[？?]", "询问是否需要技术动作（应直接做）"),
    # 通用：以"吗？"结尾的操作许可请求
    (r"(?:要不要|需不需要|用不用).*[？?]", "二选一式询问（应直接判断）"),
]
for pat, desc in defer_patterns:
    for line in active_lines:
        if re.search(pat, line):
            violations.append(f"把问题抛给用户：{desc}（{line.strip()[:60]}）")
            break

# === 检查3: 声明无法完成但未排障 ===
giveup_patterns = [
    (r"(?:无法|不能|没法)(?:完成|解决|处理|修复)", "声明无法完成"),
    (r"(?:做不到|办不到)", "做不到"),
    (r"(?:工具|环境)不(?:可用|支持)", "工具/环境不可用"),
    (r"超出能力", "超出能力"),
]
for pat, desc in giveup_patterns:
    for line in active_lines:
        if re.search(pat, line):
            violations.append(f"放弃声明：{desc}（{line.strip()[:60]}）")
            break

# === 检查4: 行为追踪验证（基于 action log，不再只看文本） ===
# 读取行为追踪日志，检查实际执行了哪些验证动作
import os, tempfile
# Windows 上 bash 的 /tmp/ 映射到 TEMP 环境变量，Python 的 /tmp/ 不同
tmp_dir = os.environ.get("TEMP", os.environ.get("TMPDIR", tempfile.gettempdir()))
action_log_path = os.path.join(tmp_dir, ".claude_action_log")
actions = set()
if os.path.exists(action_log_path):
    try:
        with open(action_log_path, "r") as f:
            for line in f:
                line = line.strip()
                if line.startswith("#") or not line:
                    continue
                parts = line.split("|", 2)
                if len(parts) >= 2:
                    actions.add(parts[1])
    except Exception:
        pass

has_go_compile = "GO_COMPILE_PASS" in actions
has_cs_compile = "CS_COMPILE_PASS" in actions
has_mcp_verify = "MCP_VERIFY" in actions
has_go_test = "GO_TEST_PASS" in actions

# 检测本会话是否修改了 .go / .cs 文件（从文本和 action log 推断）
go_change = re.search(r"\.go\b|服务端|Go|server", active_text) or "GO_COMPILE_PASS" in actions or "GO_COMPILE_FAIL" in actions
cs_change = re.search(r"\.cs\b|客户端|C#|Unity", active_text) or "CS_COMPILE_PASS" in actions or "CS_COMPILE_FAIL" in actions

# 4a: Go 代码变更需要编译通过记录
if go_change and not has_go_compile:
    # 排除纯脚本/hook 修改
    if not (re.search(r"\.sh|\.py|\.ps1|hook|脚本", active_text) and not re.search(r"\.go\b|服务端", active_text)):
        violations.append("Go 代码变更但 action log 中无编译通过记录（需实际执行 go build）")

# 4b: C# 代码变更需要编译通过 + MCP 验证
if cs_change and not has_cs_compile:
    if not (re.search(r"\.sh|\.py|\.ps1|hook|脚本", active_text) and not re.search(r"\.cs\b|客户端", active_text)):
        violations.append("C# 代码变更但 action log 中无编译通过记录")

# 4c: C# 代码变更声称修复完成但无 MCP 验证记录
fix_claim = re.search(r"修复完成|修复成功|已修复|已完成修复|已完成|功能完成", active_text)
if cs_change and fix_claim and not has_mcp_verify:
    # 排除纯 codegen 路径的变更
    codegen_only = re.search(r"Proto/|Config/Gen/|Managers/Net/Proto/", active_text) and not re.search(r"(?:新增|修改|创建).*\.cs", active_text)
    if not codegen_only:
        violations.append("C# 代码声称完成但 action log 中无 MCP 视觉验证记录（需实际截图验证）")

# === 检查5: DDRP 依赖未解决（status: open 的 ddrp-req 文件） ===
import glob as globmod

project_root = os.environ.get("CLAUDE_PROJECT_DIR", "")
if not project_root:
    import subprocess
    try:
        project_root = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL, text=True
        ).strip()
    except Exception:
        project_root = ""

if project_root:
    ddrp_pattern = os.path.join(project_root, "docs", "version", "*", "*", "ddrp-req-*.md")
    ddrp_files = globmod.glob(ddrp_pattern)
    open_reqs = []
    for f in ddrp_files:
        try:
            with open(f) as fh:
                content = fh.read()
                if "status: open" in content:
                    for dl in content.splitlines():
                        if dl.startswith("# DDRP-REQ:"):
                            name = dl.replace("# DDRP-REQ:", "").strip()
                            open_reqs.append(name + " (" + os.path.basename(f) + ")")
                            break
        except Exception:
            pass
    if open_reqs:
        violations.append("DDRP 依赖未解决：" + str(len(open_reqs)) + " 个 open — " + "; ".join(open_reqs[:3]) + "。必须实现或标记 failed 后才能交付")

# === 检查6: bug-explore Phase 4 步骤完成度 ===
# 仅当 bug-explore 流程标记存在时检查（避免误拦截 feature pipeline 等其他自主流程）
bug_explore_marker = os.path.join(tmp_dir, ".bug_explore_active")
if os.path.exists(bug_explore_marker):
    metrics_marker = os.path.join(tmp_dir, ".bug_explore_metrics_recorded")
    if not os.path.exists(metrics_marker):
        violations.append("bug-explore Phase 4 未完成：指标未记录（Step 4.5 record-metrics.py 未执行），必须走完全流程")

if violations:
    print("BLOCK:" + "|".join(violations))
else:
    print("PASS")
' 2>/dev/null || echo "PASS")

if [[ "$RESULT" == BLOCK:* ]]; then
    REASON="${RESULT#BLOCK:}"
    echo "交付质量检查 BLOCKED：${REASON}。必须自主解决后才能交付。" >&2
    exit 2
fi

exit 0
