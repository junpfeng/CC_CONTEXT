#!/usr/bin/env python3
"""Lightweight MCP helper - single tool call per invocation"""
import requests, json, sys, time

MCP_BASE = "http://localhost:8080"

def mcp(tool, args=None):
    if args is None:
        args = {}
    headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
    init_resp = requests.post(f"{MCP_BASE}/mcp", headers=headers, json={
        "jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "mcp-helper", "version": "1.0"}}
    }, timeout=5)
    session_id = init_resp.headers.get("Mcp-Session-Id", "")
    if not session_id:
        return {"error": "no session"}
    sess_headers = {**headers, "Mcp-Session-Id": session_id}
    requests.post(f"{MCP_BASE}/mcp", headers=sess_headers, json={"jsonrpc": "2.0", "method": "notifications/initialized"}, timeout=5)
    tool_resp = requests.post(f"{MCP_BASE}/mcp", headers=sess_headers, json={
        "jsonrpc": "2.0", "id": 2, "method": "tools/call",
        "params": {"name": tool, "arguments": args}
    }, timeout=60, stream=True)
    for line in tool_resp.iter_lines(decode_unicode=True):
        if line.startswith("data:"):
            d = line[5:].strip()
            try:
                obj = json.loads(d)
                result = obj.get("result", {})
                sc = result.get("structuredContent")
                if sc:
                    return sc
                content = result.get("content", [])
                for c in content:
                    if c.get("text"):
                        try:
                            return json.loads(c["text"])
                        except:
                            return {"text": c["text"]}
                return {"raw": result}
            except:
                return {"raw": d[:500]}
    return {"error": "no response"}

if __name__ == "__main__":
    tool = sys.argv[1]
    args = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
    result = mcp(tool, args)
    print(json.dumps(result, ensure_ascii=False, indent=2))
