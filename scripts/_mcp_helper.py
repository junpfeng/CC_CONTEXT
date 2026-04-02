#!/usr/bin/env python3
"""Helper to call mcp_call.py with csharpCode parameter."""
import sys, json, importlib.util

spec = importlib.util.spec_from_file_location('mcp_call', 'scripts/mcp_call.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

def run_script(code):
    result = m.mcp_call('script-execute', {'csharpCode': code})
    return result

def mcp(tool, args=None):
    return m.mcp_call(tool, args or {})

if __name__ == "__main__":
    tool = sys.argv[1]
    if tool == 'script-execute':
        code = sys.argv[2]
        print(json.dumps(run_script(code), ensure_ascii=False, indent=2))
    else:
        args = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}
        print(json.dumps(mcp(tool, args), ensure_ascii=False, indent=2))
