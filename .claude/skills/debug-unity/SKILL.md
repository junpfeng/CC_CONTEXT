# Debug Unity Compilation

## Steps
1. Run clean build via MCP
2. For each error, check if the file exists in project source (not MCP temp)
3. If all errors are MCP artifacts, report "No real compilation errors" and stop
4. For real errors: fix, rebuild, verify no regressions
5. Check that no duplicate scripts were created
6. After applying a fix, test all related states and behaviors - not just the one that was broken. List what you're verifying and confirm each passes. If anything regressed, fix it before reporting success.
