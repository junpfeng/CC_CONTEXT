# 任务清单：行为树长运行行为节点重构

## 业务工程 (P1GoServer/)

### 配置层
- [x] [TASK-001] 移除 BTreeConfig.OnExit 字段 (`config/types.go`)

### Runner 层
- [x] [TASK-002] 移除 executeOnExitTree 方法，简化 Stop/Tick (`runner/runner.go`)
- [x] [TASK-003] 更新 runner_test.go：移除 on_exit 测试，新增长运行节点测试

### 节点层
- [x] [TASK-004] 重写 behavior_nodes.go：19 个 entry/exit 节点 → 10 个长运行行为节点
- [x] [TASK-005] 更新 factory.go：移除 19 个旧注册，新增 10 个新注册

### JSON 配置
- [x] [TASK-006] 更新 10 个 JSON 树文件：移除 on_exit，替换为长运行行为节点

### 测试层
- [x] [TASK-007] 更新 integration_test.go 和 integration_phased_test.go

### 构建验证
- [x] [TASK-008] 构建验证 (`make scene_server` + `go test`)

## 任务依赖

```
TASK-001 ─┐
TASK-002 ─┤
TASK-004 ─┼─→ TASK-006 → TASK-007 → TASK-008
TASK-005 ─┘
```

TASK-001/002/004/005 可并行（不同文件），完成后 TASK-006 更新 JSON，然后 TASK-007 更新测试，最后 TASK-008 构建验证。
