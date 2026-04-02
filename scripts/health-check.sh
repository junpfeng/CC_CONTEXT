#!/bin/bash
# health-check.sh — Workspace health check: services, configs, Go build, MCP, Unity compilation
# Output: [PASS]/[FAIL]/[WARN] prefixed lines for each check item
# Exit code: 0 if all pass, 1 if any fail

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
FAIL_COUNT=0
WARN_COUNT=0
PASS_COUNT=0

pass() { echo "[PASS] $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "[FAIL] $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
warn() { echo "[WARN] $1"; WARN_COUNT=$((WARN_COUNT + 1)); }

# ---------- 1. Service Port Checks ----------
echo "=== Service Checks ==="

check_service() {
    local name="$1" port="$2"
    if netstat -ano 2>/dev/null | grep -q ":${port}.*LISTENING"; then
        pass "Service ${name} — listening on port ${port}"
    else
        fail "Service ${name} — not listening on port ${port}"
    fi
}

# Core infrastructure services (check PID files + ports)
SERVICES_DIR="$PROJECT_DIR/P1GoServer"
RUN_DIR="$PROJECT_DIR/run"

# Check if any game server processes are running via PID files
if [ -d "$RUN_DIR" ]; then
    running=0
    for pidfile in "$RUN_DIR"/*.pid; do
        [ -f "$pidfile" ] || continue
        pid=$(cat "$pidfile" 2>/dev/null)
        if [ -n "$pid" ] && tasklist //FI "PID eq $pid" 2>/dev/null | grep -q "$pid"; then
            running=$((running + 1))
        fi
    done
    if [ "$running" -gt 0 ]; then
        pass "Game servers — ${running} processes running (PID files in run/)"
    else
        warn "Game servers — no running processes detected (may not be started)"
    fi
else
    warn "Game servers — run/ directory not found (servers not started)"
fi

# Gateway (client-facing entry point)
if netstat -ano 2>/dev/null | grep -q ":8888.*LISTENING"; then
    pass "Gateway server — listening on port 8888"
else
    warn "Gateway server — not listening on port 8888 (may not be started)"
fi

# Redis
if netstat -ano 2>/dev/null | grep -q ":6379.*LISTENING"; then
    pass "Redis — listening on port 6379"
else
    fail "Redis — not listening on port 6379"
fi

# MongoDB
if netstat -ano 2>/dev/null | grep -q ":27017.*LISTENING"; then
    pass "MongoDB — listening on port 27017"
else
    fail "MongoDB — not listening on port 27017"
fi

# ---------- 2. Config File Checks ----------
echo ""
echo "=== Config File Checks ==="

check_config() {
    local path="$1" desc="$2"
    if [ -f "$path" ]; then
        if [ -s "$path" ]; then
            pass "Config ${desc} — exists and non-empty"
        else
            fail "Config ${desc} — exists but empty: ${path}"
        fi
    else
        fail "Config ${desc} — missing: ${path}"
    fi
}

check_config "$SERVICES_DIR/bin/config.toml" "server config.toml"
check_config "$SERVICES_DIR/go.mod" "Go module file"
check_config "$PROJECT_DIR/freelifeclient/ProjectSettings/ProjectSettings.asset" "Unity ProjectSettings"

# Check bin/config directory has table data
if [ -d "$SERVICES_DIR/bin/config" ]; then
    cfg_count=$(find "$SERVICES_DIR/bin/config" -name "*.bytes" -o -name "*.json" 2>/dev/null | head -20 | wc -l)
    if [ "$cfg_count" -gt 0 ]; then
        pass "Server table data — ${cfg_count}+ files in bin/config/"
    else
        warn "Server table data — bin/config/ exists but no data files found"
    fi
else
    fail "Server table data — bin/config/ directory missing"
fi

# ---------- 3. Go Server Compilation ----------
echo ""
echo "=== Go Build Check ==="

if [ -f "$SERVICES_DIR/Makefile" ]; then
    build_output=$(cd "$SERVICES_DIR" && make build 2>&1) && {
        pass "Go server — compiles cleanly (make build)"
    } || {
        # Extract first few error lines
        errors=$(echo "$build_output" | grep -i "error" | head -5)
        fail "Go server — build failed: ${errors}"
    }
elif [ -f "$SERVICES_DIR/go.mod" ]; then
    build_output=$(cd "$SERVICES_DIR" && go build ./... 2>&1) && {
        pass "Go server — compiles cleanly (go build ./...)"
    } || {
        errors=$(echo "$build_output" | grep -i "error" | head -5)
        fail "Go server — build failed: ${errors}"
    }
else
    fail "Go server — neither Makefile nor go.mod found"
fi

# ---------- 4. MCP Connectivity ----------
echo ""
echo "=== MCP Connectivity ==="

MCP_SCRIPT="$PROJECT_DIR/scripts/mcp_call.py"

if [ -f "$MCP_SCRIPT" ]; then
    # Ping test: call a lightweight MCP tool
    mcp_output=$(python3 "$MCP_SCRIPT" ping '{}' 2>&1) && {
        pass "MCP connectivity — ping successful"
    } || {
        # Fallback: check if port 8080 is listening
        if netstat -ano 2>/dev/null | grep -q ":8080.*LISTENING"; then
            warn "MCP connectivity — port 8080 open but ping tool failed: $(echo "$mcp_output" | head -1)"
        else
            fail "MCP connectivity — port 8080 not listening, Unity MCP unreachable"
        fi
    }
else
    # Direct port check as fallback
    if netstat -ano 2>/dev/null | grep -q ":8080.*LISTENING"; then
        pass "MCP connectivity — port 8080 listening (mcp_call.py not found for ping)"
    else
        fail "MCP connectivity — port 8080 not listening, Unity MCP unreachable"
    fi
fi

# ---------- 5. Unity Compilation Errors ----------
echo ""
echo "=== Unity Compilation Check ==="

UNITY_ASSETS="$PROJECT_DIR/freelifeclient/Assets"

if [ -d "$UNITY_ASSETS" ]; then
    # Check for Editor.log compilation errors (only files under Assets/)
    # Look for the most recent Editor.log
    EDITOR_LOG=""
    for candidate in \
        "$LOCALAPPDATA/Unity/Editor/Editor.log" \
        "$APPDATA/Unity/Editor/Editor.log" \
        "$HOME/Library/Logs/Unity/Editor.log"; do
        if [ -f "$candidate" ]; then
            EDITOR_LOG="$candidate"
            break
        fi
    done

    if [ -n "$EDITOR_LOG" ]; then
        # Extract CS errors only from Assets/ paths (not Temp/, Library/, or MCP scripts)
        real_errors=$(grep -E "^Assets/.*\.cs\([0-9]+,[0-9]+\): error CS" "$EDITOR_LOG" 2>/dev/null | sort -u | head -10 || true)
        if [ -z "$real_errors" ]; then
            pass "Unity compilation — no real errors in Assets/"
        else
            error_count=$(echo "$real_errors" | wc -l)
            fail "Unity compilation — ${error_count} error(s) in Assets/: $(echo "$real_errors" | head -3)"
        fi
    else
        # No Editor.log available — try MCP if reachable
        if [ -f "$MCP_SCRIPT" ]; then
            log_output=$(python3 "$MCP_SCRIPT" console-get-logs '{"count": 50}' 2>&1) && {
                cs_errors=$(echo "$log_output" | grep -i "error CS" | grep -i "Assets/" | head -5)
                if [ -z "$cs_errors" ]; then
                    pass "Unity compilation — no errors via MCP console"
                else
                    fail "Unity compilation — errors via MCP: $(echo "$cs_errors" | head -3)"
                fi
            } || {
                warn "Unity compilation — cannot verify (no Editor.log, MCP unavailable)"
            }
        else
            warn "Unity compilation — cannot verify (no Editor.log found)"
        fi
    fi
else
    fail "Unity project — Assets/ directory not found at ${UNITY_ASSETS}"
fi

# ---------- Summary ----------
echo ""
echo "=== Health Check Summary ==="
TOTAL=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT))
echo "Total: ${PASS_COUNT} pass, ${FAIL_COUNT} fail, ${WARN_COUNT} warn (${TOTAL} checks)"

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
else
    exit 0
fi
