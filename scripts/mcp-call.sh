#!/bin/bash
# Unity MCP 直连脚本
# 用法: ./mcp-call.sh <tool-name> [json-params]

MCP_BASE="http://localhost:8080"
TOOL_NAME="$1"
PARAMS="${2:-{}}"
# 用 Windows 路径避免 MSYS/Python 路径不兼容
TMPFILE="C:/Users/admin/AppData/Local/Temp/mcp_sse_$$.txt"

# SSE 连接
curl -s -N "$MCP_BASE/sse" > "$TMPFILE" 2>/dev/null &
SSE_PID=$!
sleep 1

SP=$(grep "^data:" "$TMPFILE" | head -1 | sed 's/^data: //')
if [ -z "$SP" ]; then
    kill $SSE_PID 2>/dev/null; rm -f "$TMPFILE"
    echo "ERROR: SSE 连接失败"; exit 1
fi
URL="$MCP_BASE$SP"

# 初始化
curl -s -X POST "$URL" -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"mcp-call","version":"1.0"}}}' > /dev/null 2>&1
sleep 2
curl -s -X POST "$URL" -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' > /dev/null 2>&1
sleep 1

# 调用工具
curl -s -X POST "$URL" -H "Content-Type: application/json" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"$TOOL_NAME\",\"arguments\":$PARAMS}}" > /dev/null 2>&1

# 等待结果
sleep 5

# 用 python 解析
python3 -c "
import sys, json

with open(r'$TMPFILE', 'r', encoding='utf-8', errors='replace') as f:
    lines = f.readlines()

data_lines = [l.strip()[len('data: '):] for l in lines if l.strip().startswith('data:')]

for dl in data_lines:
    try:
        obj = json.loads(dl)
        if obj.get('id') == 2:
            sc = obj.get('result',{}).get('structuredContent',{}).get('result')
            if sc is not None:
                print(json.dumps(sc, ensure_ascii=False))
            else:
                for t in obj.get('result',{}).get('content',[]):
                    print(t.get('text',''))
            sys.exit(0)
    except:
        pass

print('ERROR: 未找到工具响应, data_lines=' + str(len(data_lines)))
" 2>&1

kill $SSE_PID 2>/dev/null
rm -f "$TMPFILE"
