# 行为树系统测试计划

## 概述

本文档定义行为树系统的测试策略、测试用例和验收标准。

## 测试范围

### 核心组件

| 组件 | 测试文件 | 优先级 |
|------|----------|--------|
| BtContext | `bt/context/context_test.go` | P0 |
| BtRunner | `bt/runner/runner_test.go` | P0 |
| NodeFactory | `bt/nodes/factory_test.go` | P1 |
| BTreeLoader | `bt/config/loader_test.go` | P1 |
| 控制节点 | `bt/nodes/control_test.go` | P1 |
| 叶子节点 | `bt/nodes/leaf_test.go` | P2 |

### 集成测试

| 测试 | 位置 | 优先级 |
|------|------|--------|
| Executor 集成 | `ecs/system/decision/executor_test.go` | P0 |
| 端到端流程 | `bt/integration_test.go` | P0 |

---

## 测试用例

### 1. BtContext 测试

#### 1.1 黑板操作
- [x] `TestBlackboard_SetAndGet`: 设置并读取值
- [x] `TestBlackboard_GetTyped`: 类型化读取 (int64, float32, string, bool, uint64)
- [x] `TestBlackboard_GetMissing`: 读取不存在的 key
- [x] `TestBlackboard_Overwrite`: 覆盖已有值
- [x] `TestBlackboard_HasBlackboard`: 检查键是否存在
- [x] `TestBlackboard_DeleteBlackboard`: 删除键
- [x] `TestBlackboard_ClearBlackboard`: 清空黑板
- [x] `TestBlackboard_NilBlackboard`: nil 黑板处理

#### 1.2 组件访问
- [ ] `TestGetMoveComp`: 获取移动组件 (需要集成测试)
- [ ] `TestGetDecisionComp`: 获取决策组件 (需要集成测试)
- [ ] `TestGetTransformComp`: 获取变换组件 (需要集成测试)
- [ ] `TestComponentCache`: 组件缓存机制 (需要集成测试)

#### 1.3 上下文生命周期
- [x] `TestNewBtContext`: 创建上下文
- [x] `TestContextReset`: 重置上下文

---

### 2. BtRunner 测试

#### 2.1 树注册
- [x] `TestRegisterTree`: 注册行为树
- [x] `TestRegisterTree_NilRoot`: 注册 nil 根节点
- [x] `TestRegisterTree_Overwrite`: 覆盖注册
- [x] `TestUnregisterTree`: 取消注册
- [x] `TestHasTree_Exists`: 检查已注册的树
- [x] `TestHasTree_NotExists`: 检查未注册的树
- [x] `TestGetTree`: 获取树模板

#### 2.2 执行生命周期
- [x] `TestRun_Success`: 成功启动行为树
- [x] `TestRun_TreeNotFound`: 启动不存在的树
- [x] `TestRun_StopPrevious`: 启动新树时停止旧树
- [x] `TestRun_ImmediateComplete`: 立即完成的树
- [x] `TestStop_Running`: 停止运行中的树
- [x] `TestStop_NotRunning`: 停止未运行的树
- [x] `TestStop_RecursiveExit`: 递归停止子节点

#### 2.3 Tick 执行
- [x] `TestTick_Running`: Tick 运行中的树
- [x] `TestTick_Complete`: 树执行完成
- [x] `TestTick_Failed`: 树执行失败
- [x] `TestTick_NotFound`: Tick 不存在的实体
- [x] `TestTick_AlreadyComplete`: 已完成的树不再 Tick
- [x] `TestTick_DeltaTime`: DeltaTime 传递

#### 2.4 状态管理
- [x] `TestIsRunning`: 检查运行状态
- [x] `TestGetRunningTrees`: 获取运行中的树列表
- [x] `TestGetRunningCount`: 获取运行中的树数量
- [x] `TestGetRegisteredCount`: 获取已注册的树数量
- [x] `TestGetInstance`: 获取树实例
- [x] `TestGetScene`: 获取场景
- [x] `TestMultipleEntities`: 多实体测试

---

### 3. 节点测试

#### 3.1 BaseNode 测试
- [x] `TestNewBaseNode`: 创建基础节点
- [x] `TestNewBaseNode_DifferentTypes`: 不同类型节点
- [x] `TestBtNodeStatus_String`: 状态字符串
- [x] `TestBtNodeType_String`: 类型字符串
- [x] `TestSetStatus`: 设置状态
- [x] `TestIsRunning`: 检查运行状态
- [x] `TestIsCompleted`: 检查完成状态
- [x] `TestAddChild`: 添加子节点
- [x] `TestAddChild_Multiple`: 添加多个子节点
- [x] `TestChildren_Empty`: 空子节点列表
- [x] `TestReset`: 重置节点
- [x] `TestReset_Recursive`: 递归重置
- [x] `TestReset_DeepRecursive`: 深层递归重置
- [x] `TestOnEnter_Default`: 默认 OnEnter
- [x] `TestOnTick_Default`: 默认 OnTick
- [x] `TestOnExit_Default`: 默认 OnExit
- [x] `TestBaseNode_ImplementsIBtNode`: 接口实现验证

#### 3.2 控制节点
- [x] `TestSequence_AllSuccess`: 所有子节点成功
- [x] `TestSequence_OneFails`: 一个子节点失败
- [x] `TestSequence_FirstFails_OnEnter`: 第一个在 OnEnter 失败
- [x] `TestSequence_Empty`: 空序列
- [x] `TestSequence_ImmediateSuccess`: 立即成功
- [x] `TestSequence_Running`: Running 状态
- [x] `TestSequence_Reset`: 重置
- [x] `TestSequence_OnExit_RunningChild`: OnExit 处理运行中子节点
- [x] `TestSelector_FirstSuccess`: 第一个成功
- [x] `TestSelector_SecondSuccess`: 第二个成功
- [x] `TestSelector_AllFail`: 全部失败
- [x] `TestSelector_Empty`: 空选择器
- [x] `TestSelector_ImmediateSuccess_OnEnter`: OnEnter 立即成功
- [x] `TestSelector_ImmediateFail_TryNext`: OnEnter 失败尝试下一个
- [x] `TestSelector_Running`: Running 状态
- [x] `TestSelector_Reset`: 重置
- [x] `TestSelector_OnExit_RunningChild`: OnExit 处理运行中子节点

#### 3.3 节点工厂
- [x] `TestNewNodeFactory`: 创建工厂
- [x] `TestRegister_Custom`: 注册自定义节点
- [x] `TestRegister_Override`: 覆盖注册
- [x] `TestHasCreator_Exists`: 检查已注册
- [x] `TestHasCreator_NotExists`: 检查未注册
- [x] `TestCreate_Sequence`: 创建 Sequence
- [x] `TestCreate_Selector`: 创建 Selector
- [x] `TestCreate_Wait_*`: 创建 Wait 节点
- [x] `TestCreate_MoveTo_*`: 创建 MoveTo 节点
- [x] `TestCreate_Log_*`: 创建 Log 节点
- [x] `TestCreate_SetBlackboard_*`: 创建 SetBlackboard 节点
- [x] `TestCreate_SetFeature_*`: 创建 SetFeature 节点
- [x] `TestCreate_CheckCondition_*`: 创建 CheckCondition 节点
- [x] `TestCreate_LookAt_*`: 创建 LookAt 节点
- [x] `TestCreate_UnknownType`: 未知类型错误
- [x] `TestParseVec3_*`: Vec3 解析
- [x] `TestToFloat32_*`: Float32 转换

#### 3.4 叶子节点 (需要集成测试)
- [ ] `TestWaitNode_Complete`: 等待完成
- [ ] `TestWaitNode_Running`: 等待中
- [ ] `TestLogNode_Execute`: 日志输出
- [ ] `TestStopMoveNode_Execute`: 停止移动

---

### 4. 配置加载测试

#### 4.1 JSON 解析
- [ ] `TestLoadFromJSON_Valid`: 加载有效 JSON
- [ ] `TestLoadFromJSON_Invalid`: 加载无效 JSON
- [ ] `TestLoadFromJSON_MissingFields`: 缺少必要字段

#### 4.2 节点构建
- [ ] `TestBuildNode_Sequence`: 构建序列节点
- [ ] `TestBuildNode_Selector`: 构建选择器节点
- [ ] `TestBuildNode_Leaf`: 构建叶子节点
- [ ] `TestBuildNode_Unknown`: 未知节点类型

#### 4.3 黑板初始化
- [ ] `TestParseBlackboard_Int`: 解析整数
- [ ] `TestParseBlackboard_Float`: 解析浮点数
- [ ] `TestParseBlackboard_Vec3`: 解析向量

---

### 5. 集成测试

#### 5.1 Executor 集成
- [ ] `TestExecutor_RegisterBehaviorTree`: 注册行为树
- [ ] `TestExecutor_OnPlanCreated_WithBT`: Plan 有行为树时启动
- [ ] `TestExecutor_OnPlanCreated_WithoutBT`: Plan 无行为树时走原逻辑
- [ ] `TestExecutor_GetBtRunner`: 获取 BtRunner

#### 5.2 端到端流程
- [ ] `TestE2E_SimpleTree`: 简单行为树执行完成
- [ ] `TestE2E_TreeCompletion`: 树完成后触发重评估
- [ ] `TestE2E_TreeInterrupt`: 树被中断

---

## 测试命令

```bash
# 运行所有行为树测试
go test -v ./servers/scene_server/internal/common/ai/bt/...

# 运行特定测试
go test -v ./servers/scene_server/internal/common/ai/bt/runner -run TestBtRunner

# 运行带覆盖率
go test -cover ./servers/scene_server/internal/common/ai/bt/...

# 生成覆盖率报告
go test -coverprofile=coverage.out ./servers/scene_server/internal/common/ai/bt/...
go tool cover -html=coverage.out -o coverage.html
```

---

## 验收标准

1. **覆盖率**: 核心组件 > 80%
2. **通过率**: 100% 测试通过
3. **端到端**: 至少 3 个端到端测试场景通过
4. **回归**: 现有功能不受影响

---

## 测试数据

### 示例行为树 JSON

```json
{
  "name": "test_simple",
  "root": {
    "type": "Sequence",
    "children": [
      { "type": "Log", "params": { "message": "step 1" } },
      { "type": "Wait", "params": { "duration_ms": 100 } },
      { "type": "Log", "params": { "message": "step 2" } }
    ]
  }
}
```

---

## 测试覆盖率

| 包 | 覆盖率 | 测试数 |
|----|--------|--------|
| bt/context | 58.7% | 18 |
| bt/node | 100% | 19 |
| bt/nodes | 47.8% | 63 |
| bt/runner | 91.2% | 27 |
| **总计** | **~70%** | **127+** |

---

## 更新记录

| 日期 | 更新内容 |
|------|----------|
| 2026-02-02 | 创建测试计划 |
| 2026-02-02 | 实现 context, node, nodes, runner 测试，127+ 测试通过 |
