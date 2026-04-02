#!/bin/bash
# PostToolUse hook: 在 Edit/Write .cs 文件后自动检查语法错误
# 检查层级:
#   1. 正则规则 - 捕捉项目常见低级错误（始终运行）
#   2. Roslyn 语法检查 - 使用 CSharpSyntaxChecker 检测语法错误（毫秒级）

INPUT=$(cat)
# 不依赖 jq，用 grep + sed 解析 file_path
FILE=$(echo "$INPUT" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//;s/"$//')

# 只检查 .cs 文件
if [[ "$FILE" != *.cs ]]; then
  exit 0
fi

# 跳过自动生成的文件
if [[ "$FILE" == *"/Config/Gen/"* ]] || [[ "$FILE" == *"/orm/"* ]]; then
  exit 0
fi

# 只检查 Unity 客户端代码（freelifeclient/Assets/Scripts 下的文件）
if [[ "$FILE" != *"freelifeclient/Assets/Scripts/"* ]] && [[ "$FILE" != *"freelifeclient\\Assets\\Scripts\\"* ]]; then
  exit 0
fi

# 文件不存在则跳过（可能是删除操作）
if [[ ! -f "$FILE" ]]; then
  exit 0
fi

ERRORS=""

# ============================================================
# 第一层：正则规则检查（项目常见低级错误）
# ============================================================

# 1. 检查括号匹配（粗略：统计 { 和 } 数量）
OPEN=$(grep -o '{' "$FILE" | wc -l)
CLOSE=$(grep -o '}' "$FILE" | wc -l)
if [[ "$OPEN" -ne "$CLOSE" ]]; then
  ERRORS+="[括号不匹配] { 出现 ${OPEN} 次，} 出现 ${CLOSE} 次\n"
fi

# 2. 检查圆括号匹配
OPEN_PAREN=$(grep -o '(' "$FILE" | wc -l)
CLOSE_PAREN=$(grep -o ')' "$FILE" | wc -l)
if [[ "$OPEN_PAREN" -ne "$CLOSE_PAREN" ]]; then
  ERRORS+="[圆括号不匹配] ( 出现 ${OPEN_PAREN} 次，) 出现 ${CLOSE_PAREN} 次\n"
fi

# 3. 禁止使用 Debug.Log（项目规范：必须用 MLog）
DEBUG_LINES=$(grep -n 'Debug\.Log\|Debug\.LogWarning\|Debug\.LogError' "$FILE" | grep -v '//' | head -5)
if [[ -n "$DEBUG_LINES" ]]; then
  ERRORS+="[禁止 Debug.Log] 请使用 MLog，违规行:\n${DEBUG_LINES}\n"
fi

# 4. 检查 async void（危险模式，应使用 async UniTask 或 async UniTaskVoid + try-catch）
ASYNC_VOID=$(grep -n 'async void ' "$FILE" | grep -v '//' | grep -v 'override' | head -5)
if [[ -n "$ASYNC_VOID" ]]; then
  ERRORS+="[async void 警告] 建议使用 async UniTask/UniTaskVoid + try-catch:\n${ASYNC_VOID}\n"
fi

# 5. 检查命名空间冲突：同时 using FL.Net.Proto 和 UnityEngine 但无别名消解
HAS_PROTO=$(grep -c 'using FL\.Net\.Proto;' "$FILE")
HAS_UNITY=$(grep -c 'using UnityEngine;' "$FILE")
HAS_ALIAS=$(grep -c 'using.*Vector3\s*=' "$FILE")
if [[ "$HAS_PROTO" -gt 0 ]] && [[ "$HAS_UNITY" -gt 0 ]] && [[ "$HAS_ALIAS" -eq 0 ]]; then
  ERRORS+="[命名空间冲突] 同时 using FL.Net.Proto 和 UnityEngine，需要添加 using Vector3 = ... 别名消解\n"
fi

# 6. 检查裸 Physics. 调用（应使用 UnityEngine.Physics）
BARE_PHYSICS=$(grep -n '[^.]Physics\.\(Raycast\|SphereCast\|BoxCast\|OverlapSphere\|CapsuleCast\)' "$FILE" | grep -v 'UnityEngine\.Physics' | grep -v '//' | head -3)
if [[ -n "$BARE_PHYSICS" ]]; then
  ERRORS+="[裸 Physics 调用] 请使用 UnityEngine.Physics 全限定名:\n${BARE_PHYSICS}\n"
fi

# 7. 检查废弃的 MLog 命名空间
OLD_MLOG=$(grep -n 'using FL\.Framework\.Console;' "$FILE" | head -3)
if [[ -n "$OLD_MLOG" ]]; then
  ERRORS+="[废弃命名空间] FL.Framework.Console 已废弃，请改用 using FL.MLogRuntime;\n${OLD_MLOG}\n"
fi

# 8. 检查 System.Threading.Tasks（应使用 UniTask）
SYS_TASK=$(grep -n 'using System\.Threading\.Tasks;' "$FILE" | head -3)
if [[ -n "$SYS_TASK" ]]; then
  ERRORS+="[禁止 System.Threading.Tasks] 请使用 Cysharp.Threading.Tasks (UniTask)\n"
fi

# ============================================================
# 第二层：Roslyn 语法检查（使用 CSharpSyntaxChecker 单文件模式）
# ============================================================

CHECKER="$CLAUDE_PROJECT_DIR/_tool/CSharpSyntaxChecker/bin/Release/net9.0/CSharpSyntaxChecker.exe"
ROSLYN_ERRORS=""
if [[ -f "$CHECKER" ]]; then
  ROSLYN_OUTPUT=$("$CHECKER" -f "$FILE" 2>&1)
  if [[ $? -ne 0 ]] && [[ -n "$ROSLYN_OUTPUT" ]]; then
    ROSLYN_ERRORS="[Roslyn 语法错误]\n${ROSLYN_OUTPUT}\n"
  fi
fi

# ============================================================
# 输出结果
# ============================================================

ALL_ERRORS="${ERRORS}${ROSLYN_ERRORS}"

if [[ -n "$ALL_ERRORS" ]]; then
  # 输出错误信息到 stderr，Claude 会看到并修复
  echo -e "⚠️ C# 语法检查发现问题 (${FILE##*/}):\n${ALL_ERRORS}" >&2
  # 写入行为追踪日志
  echo "$(date +%s)|CS_COMPILE_FAIL|$FILE" >> "/tmp/.claude_action_log" 2>/dev/null
  exit 2  # exit 2 = 告知 Claude 有问题需要修复
fi

# 写入行为追踪日志
echo "$(date +%s)|CS_COMPILE_PASS|$FILE" >> "/tmp/.claude_action_log" 2>/dev/null

exit 0
