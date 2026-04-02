#!/usr/bin/env python3
"""
MCP 视觉验收签名库。
用于 hook 系统：PostToolUse 写签名 marker，Stop/PreToolUse 验签。
HMAC 密钥由 session_id + hostname + 固定盐值派生，Claude 无法在 Bash 中伪造。

CLI 用法:
  python3 mcp_verify_lib.py write <session_id> <tool_name>
  python3 mcp_verify_lib.py validate <session_id>
  python3 mcp_verify_lib.py is_codegen <file1> [file2 ...]
"""
import hmac
import hashlib
import time
import socket
import os
import sys

# ---- 常量 ----
SALT = "p1-mcp-verify-2026-xK9m"
MARKER_PATH = "/tmp/.mcp_visual_verified"
MAX_AGE_SECONDS = 1800  # 30 分钟

# 这些路径下的 .cs 变更视为自动生成代码，不要求 MCP 验收
CODEGEN_PATHS = [
    "Proto/",
    "Config/Gen/",
    "Managers/Net/Proto/",
]

# 这些 MCP 工具名（子串匹配）视为视觉验证工具
VISUAL_TOOLS = [
    "screenshot-game-view",
    "screenshot-scene-view",
    "script-execute",
]


def compute_hmac(session_id: str, timestamp: str, tool_name: str) -> str:
    """计算 HMAC-SHA256 签名"""
    key = f"{session_id}:{socket.gethostname()}:{SALT}".encode("utf-8")
    msg = f"{session_id}|{timestamp}|{tool_name}".encode("utf-8")
    return hmac.new(key, msg, hashlib.sha256).hexdigest()


def write_marker(session_id: str, tool_name: str) -> str:
    """写入签名 marker 文件，返回写入内容"""
    ts = str(int(time.time()))
    sig = compute_hmac(session_id, ts, tool_name)
    content = f"{session_id}|{ts}|{tool_name}|{sig}"
    with open(MARKER_PATH, "w", encoding="utf-8") as f:
        f.write(content)
    return content


def validate_marker(session_id: str) -> tuple:
    """
    验证 marker 文件。
    返回 (valid: bool, detail: str)
    valid=True 时 detail 是工具名；valid=False 时 detail 是失败原因。
    """
    if not os.path.exists(MARKER_PATH):
        return False, "marker not found"

    try:
        with open(MARKER_PATH, "r", encoding="utf-8") as f:
            content = f.read().strip()
    except Exception as e:
        return False, f"read error: {e}"

    parts = content.split("|")
    if len(parts) != 4:
        return False, "invalid format"

    sid, ts, tool, sig = parts

    # 验证 session_id 匹配（防止跨会话复用 marker）
    if sid != session_id:
        return False, f"session mismatch (marker={sid[:8]}..., current={session_id[:8]}...)"

    # 验证 HMAC 签名
    expected = compute_hmac(sid, ts, tool)
    if not hmac.compare_digest(sig, expected):
        return False, "invalid signature"

    # 检查过期
    try:
        age = int(time.time()) - int(ts)
        if age > MAX_AGE_SECONDS:
            return False, f"expired ({age}s > {MAX_AGE_SECONDS}s)"
    except ValueError:
        return False, "invalid timestamp"

    return True, tool


def is_codegen_only(cs_files: list) -> bool:
    """判断所有 .cs 文件是否都在自动生成代码路径下"""
    if not cs_files:
        return True
    return all(
        any(codegen_path in f for codegen_path in CODEGEN_PATHS)
        for f in cs_files
    )


# ---- CLI 入口 ----
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: mcp_verify_lib.py <write|validate|is_codegen> ...", file=sys.stderr)
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "write":
        if len(sys.argv) < 4:
            print("Usage: mcp_verify_lib.py write <session_id> <tool_name>", file=sys.stderr)
            sys.exit(1)
        content = write_marker(sys.argv[2], sys.argv[3])
        print(f"OK: {content}")
        sys.exit(0)

    elif cmd == "validate":
        if len(sys.argv) < 3:
            print("Usage: mcp_verify_lib.py validate <session_id>", file=sys.stderr)
            sys.exit(1)
        valid, detail = validate_marker(sys.argv[2])
        if valid:
            print(f"VALID: {detail}")
            sys.exit(0)
        else:
            print(f"INVALID: {detail}", file=sys.stderr)
            sys.exit(1)

    elif cmd == "is_codegen":
        files = sys.argv[2:]
        if is_codegen_only(files):
            print("CODEGEN_ONLY")
            sys.exit(0)
        else:
            print("HAS_NON_CODEGEN")
            sys.exit(1)

    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)
