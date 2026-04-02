# DDRP: 递归依赖发现与上报协议

## 触发条件
当 feature:developing 编码阶段发现当前 task 依赖的系统/模块/接口不存在时触发。

## 发现与分级规则

| 规模 | 判断标准 | 处理 |
|------|----------|------|
| 内联 | ≤50 行、单文件、无外部依赖 | 当前 task 直接实现，develop-log 记录 `[DDRP-INLINE]` |
| 子任务 | 50-300 行、1-3 文件、自包含 | 暂停当前 task → 实现依赖 → 编译验证 → 恢复当前 task，记录 `[DDRP-SUBTASK]` |
| 子系统 | >300 行 或 3+ 文件 或 有自身依赖 | 写 ddrp-req 文件后继续尝试当前 task（引擎正常 discard） |

## 核心规则

1. **子系统必须上报**：达到子系统规模的缺失依赖，必须写 ddrp-req 文件，禁止 developing 内部 spawn 进程
2. **DDRP 实现只做最小可用版本**：满足调用方需求的最小实现，不做完整功能
3. **写入 ddrp-req 后继续尝试**：不要停下来等，继续尝试当前 task（编译失败后引擎会正常 discard）
4. **PROJECT_ROOT**：直接取 CWD
5. **registry 文件锁**：`ddrp-registry.json` 的所有读-改-写操作必须持文件锁，防止并行进程竞态覆盖。使用 `mkdir` 原子锁（跨平台兼容）：
   ```bash
   REGISTRY="${FEATURE_DIR}/../ddrp-registry.json"
   LOCKDIR="${REGISTRY}.lock"
   acquire_lock() { local t=0; while ! mkdir "$LOCKDIR" 2>/dev/null; do t=$((t+1)); [ $t -ge 20 ] && return 1; sleep 0.5; done; }
   release_lock() { rmdir "$LOCKDIR" 2>/dev/null; }
   acquire_lock && { <read-modify-write>; release_lock; }
   ```

## ddrp-req 文件格式

每个 task 写独立文件（避免并发写碰撞）：`{FEATURE_DIR}/ddrp-req-{TASK_ID}.md`

```markdown
# DDRP-REQ: {系统名}
- status: open
- 核心能力：{调用方需要的具体接口/类型名/方法签名}
- 预估规模：{N 文件, ~M 行}
- 阻塞的 task：{task ID 或描述}
- 参考实现：{最相似已有系统路径}
```

**字段要求**：
- `核心能力` 必须写明具体的类型名、方法签名和预期行为，不能只写概括性描述
- `参考实现` 帮助子 feature 快速定位代码风格和架构模式
- `status` 有三个值：`open`（待解决）、`resolved`（已解决）、`failed`（依赖无法满足，降级继续）

## PROJECT_ROOT 发现

```bash
PROJECT_ROOT="$PWD"
FEATURE_DIR="${PROJECT_ROOT}/docs/version/${VERSION_ID}/${FEATURE_NAME}"
```

ddrp-req 文件写入 `${FEATURE_DIR}/`。

## 跨 Feature 依赖（多窗口并行）

DDRP 发现依赖时，检查 `ddrp-registry.json` 中是否已有该依赖的记录。未匹配则按原有逻辑 spawn 独立子 feature。

## 来源
design-ddrp-recursive-dependency-resolution.md v5
