#!/usr/bin/env python3
"""Unity MCP 直连脚本 - 支持 Streamable HTTP 传输（MCP v0.55.0+）"""
import sys, json, os
try:
    import requests
except ImportError:
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "requests", "-q"])
    import requests

MCP_BASE = "http://localhost:8080"

def mcp_call(tool_name: str, arguments: dict = None, timeout: float = 30) -> dict:
    if arguments is None:
        arguments = {}
    headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}

    # 1. Initialize
    init_resp = requests.post(f"{MCP_BASE}/mcp", headers=headers, json={
        "jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05", "capabilities": {},
            "clientInfo": {"name": "mcp-call-py", "version": "2.0"}
        }
    }, timeout=timeout)

    session_id = init_resp.headers.get("Mcp-Session-Id", "")
    if not session_id:
        # 尝试旧协议路径
        init_resp = requests.post(f"{MCP_BASE}", headers=headers, json={
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {
                "protocolVersion": "2024-11-05", "capabilities": {},
                "clientInfo": {"name": "mcp-call-py", "version": "2.0"}
            }
        }, timeout=timeout)
        session_id = init_resp.headers.get("Mcp-Session-Id", "")

    if not session_id:
        return {"error": f"未获取到 Session ID, status={init_resp.status_code}, body={init_resp.text[:200]}"}

    sess_headers = {**headers, "Mcp-Session-Id": session_id}

    # 2. Notify initialized
    requests.post(f"{MCP_BASE}/mcp", headers=sess_headers, json={
        "jsonrpc": "2.0", "method": "notifications/initialized"
    }, timeout=5)

    # 3. tools/list (for list-tools command)
    if tool_name == "list-tools":
        resp = requests.post(f"{MCP_BASE}/mcp", headers=sess_headers, json={
            "jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}
        }, timeout=timeout)
        data = _parse_response(resp)
        tools = data.get("result", {}).get("tools", [])
        return {"tools": [t.get("name", "") for t in tools], "count": len(tools)}

    # 4. tools/call
    resp = requests.post(f"{MCP_BASE}/mcp", headers=sess_headers, json={
        "jsonrpc": "2.0", "id": 2, "method": "tools/call",
        "params": {"name": tool_name, "arguments": arguments}
    }, timeout=timeout)

    data = _parse_response(resp)

    # 提取结果
    sc = data.get("result", {}).get("structuredContent", {}).get("result")
    if sc is not None:
        return sc
    texts = data.get("result", {}).get("content", [])
    if texts:
        try:
            return json.loads(texts[0].get("text", "{}"))
        except:
            return {"text": texts[0].get("text", "")}
    return data


def _parse_response(resp):
    """解析 JSON 或 SSE 格式响应"""
    ct = resp.headers.get("Content-Type", "")
    if "text/event-stream" in ct:
        # SSE 格式：提取最后一个 data: 行
        for line in reversed(resp.text.strip().split("\n")):
            if line.startswith("data: "):
                try:
                    return json.loads(line[6:])
                except:
                    pass
        return {"error": f"SSE 解析失败: {resp.text[:200]}"}
    try:
        return resp.json()
    except:
        return {"error": f"响应解析失败: status={resp.status_code}, body={resp.text[:200]}"}


if __name__ == "__main__":
    tool = sys.argv[1] if len(sys.argv) > 1 else "editor-application-get-state"

    if len(sys.argv) > 2:
        arg = sys.argv[2]
        if os.path.isfile(arg):
            with open(arg, 'r', encoding='utf-8') as f:
                params = json.load(f)
        else:
            params = json.loads(arg)
    else:
        params = {}

    result = mcp_call(tool, params)
    print(json.dumps(result, ensure_ascii=False, indent=2))

    # Visual tool 调用成功时写 HMAC 签名 marker，与 PostToolUse hook 等效
    # 解决 mcp_call.py 绕过 MCP 工具直接调用时 PostToolUse hook 不触发的缺口
    VISUAL_TOOLS = ["screenshot-game-view", "screenshot-scene-view", "script-execute"]
    if any(vt in tool for vt in VISUAL_TOOLS) and result and "error" not in str(result).lower():
        try:
            session_id = os.environ.get("CLAUDE_SESSION_ID", "mcp-call-fallback")
            lib_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".claude", "hooks", "mcp_verify_lib.py")
            import subprocess as _sp
            _sp.run([sys.executable, lib_path, "write", session_id, tool],
                    capture_output=True, timeout=5)
        except Exception:
            pass
