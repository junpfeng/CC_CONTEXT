# NPC AI Test Agent

## 职责

验证 NPC AI 重构的正确性，确保小镇和樱校场景的 NPC AI 功能正常。

## 前置条件

- 完成对应阶段的重构任务
- 编译通过：`make build APPS='scene_server'`

---

## 阶段一测试

### 测试目标

验证系统重构后，小镇 NPC AI 功能正常（回归），Sakura NPC AI 功能可用（新增）。

### 1.1 编译验证

```bash
# 确保编译通过
make build APPS='scene_server'

# 检查是否有未使用的 import
go vet ./servers/scene_server/...
```

### 1.2 代码审查检查点

检查以下文件的修改：

**sensor_feature.go**
- [ ] 不再 import `"mp/servers/scene_server/internal/ecs/res/town"`（如果不需要）
- [ ] Update() 使用 `EntityListByType(common.EntityType_Npc)` 遍历
- [ ] 日程感知检查组件存在性

**vision_system.go**
- [ ] 不再 import `"mp/servers/scene_server/internal/ecs/res/town"`（如果不需要）
- [ ] Update() 和 UpdateVisionByProto() 使用通用遍历

**police_system.go**
- [ ] 不再 import `"mp/servers/scene_server/internal/ecs/res/town"`（如果不需要）
- [ ] Update() 使用 `IsNpcPolice()` 判断警察
- [ ] `police_utils.go` 已创建

**scene_impl.go**
- [ ] Sakura case 调用了 `loadNavMesh("sakura")`
- [ ] Sakura case 调用了 AI 系统初始化

### 1.3 运行时验证（需要服务器环境）

```bash
# 启动场景服务器
./bin/scene_server -c bin/config.toml

# 观察日志，确认：
# 1. 小镇场景初始化 NPC AI 系统成功
# 2. 樱校场景初始化 NPC AI 系统成功
# 3. NPC 感知系统正常 tick
# 4. NPC 决策系统正常 tick
# 5. NPC 视野系统正常工作
```

### 1.4 功能验证点

| 场景 | 功能 | 预期结果 |
|------|------|----------|
| 小镇 | NPC 感知 | 感知系统正常更新特征 |
| 小镇 | NPC 决策 | 决策系统正常执行 |
| 小镇 | NPC 视野 | 视野系统正常工作 |
| 小镇 | 警察追捕 | 警察系统正常工作 |
| 樱校 | NPC 感知 | 感知系统正常更新特征 |
| 樱校 | NPC 决策 | 决策系统正常执行 |
| 樱校 | NPC 视野 | 视野系统正常工作 |

---

## 阶段二测试

### 测试目标

验证接口化配置后，系统初始化流程正确。

### 2.1 编译验证

```bash
make build APPS='scene_server'
go vet ./servers/scene_server/...
```

### 2.2 代码审查检查点

**common/scene_info.go（或对应文件）**
- [ ] `SceneNpcAIConfig` 结构体已定义
- [ ] `NpcAIConfigProvider` 接口已定义
- [ ] `TownSceneInfo` 实现了 `GetNpcAIConfig()`
- [ ] `SakuraSceneInfo` 实现了 `GetNpcAIConfig()`

**scene_impl.go**
- [ ] `initNpcAISystemsFromConfig()` 已实现
- [ ] `init()` 统一调用 `initNpcAISystemsFromConfig()`
- [ ] 删除了旧的 `initNpcAISystems()` 方法
- [ ] 删除了各 case 中的 `loadNavMesh()` 调用

### 2.3 接口实现验证

```go
// 验证接口实现（可以写个简单的测试）
var _ common.NpcAIConfigProvider = (*common.TownSceneInfo)(nil)
var _ common.NpcAIConfigProvider = (*common.SakuraSceneInfo)(nil)
```

### 2.4 配置正确性验证

| 场景 | EnableSensor | EnableDecision | EnableVision | EnablePolice | EnableWanted | NavMeshName |
|------|--------------|----------------|--------------|--------------|--------------|-------------|
| Town | true | true | true | true | true | "town" |
| Sakura | true | true | true | false | false | "sakura" |

---

## 阶段三测试

### 测试目标

验证 NPC 创建流程统一后，各场景 NPC 创建正常。

### 3.1 编译验证

```bash
make build APPS='scene_server'
go vet ./servers/scene_server/...
```

### 3.2 代码审查检查点

**common.go**
- [ ] `CreateSceneNpcParam` 结构体已定义
- [ ] `CreateSceneNpc()` 函数已实现
- [ ] `InitNpcAIComponentsParam` 结构体已定义
- [ ] `InitNpcAIComponentsWithParam()` 函数已实现
- [ ] `getDefaultPoliceConfig()` 函数已实现
- [ ] `InitNpcAIComponents()` 保持向后兼容

**town_npc.go**
- [ ] `CreateTownNpc()` 使用 `CreateSceneNpc()`
- [ ] 删除了重复的组件创建代码
- [ ] 删除了不再需要的 import

**sakura_npc.go**
- [ ] `CreateSakuraNpc()` 使用 `CreateSceneNpc()`
- [ ] 删除了重复的组件创建代码
- [ ] 删除了不再需要的 import

### 3.3 NPC 组件验证

检查创建的 NPC 是否包含正确的组件：

| 场景 | 基础组件 | 场景组件 | 日程组件 | 对话组件 | 决策组件 | 视野组件 | 警察组件 |
|------|----------|----------|----------|----------|----------|----------|----------|
| 小镇 | ✓ | TownNpcComp | ✓ | ✓ | ✓ | ✓ | ✓ |
| 樱校 | ✓ | SakuraNpcComp | ✓ | ✓ | ✓ | ✓ | ✗ |

### 3.4 运行时验证

```bash
# 启动服务器
./bin/scene_server -c bin/config.toml

# 观察日志，确认：
# 1. 小镇 NPC 创建成功，包含所有必要组件
# 2. 樱校 NPC 创建成功，包含所有必要组件
# 3. NPC AI 功能正常工作
```

---

## 回归测试清单

### 小镇场景

- [ ] NPC 正常生成
- [ ] NPC 感知系统正常工作
- [ ] NPC 决策系统正常工作
- [ ] NPC 视野系统正常工作
- [ ] 警察 NPC 正常巡逻
- [ ] 警察追捕功能正常
- [ ] 被通缉系统正常工作
- [ ] NPC 对话功能正常
- [ ] NPC 日程功能正常

### 樱校场景

- [ ] NPC 正常生成
- [ ] NPC 感知系统正常工作
- [ ] NPC 决策系统正常工作
- [ ] NPC 视野系统正常工作
- [ ] NPC 对话功能正常
- [ ] NPC 日程功能正常

---

## 性能测试

### 测试方法

```bash
# 使用 pprof 分析性能
go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30
```

### 性能指标

| 指标 | 目标值 | 备注 |
|------|--------|------|
| NPC 遍历时间 | <5ms/帧 | 所有系统遍历 NPC 的总时间 |
| 内存增长 | 无明显增长 | 对比重构前后 |
| GC 暂停 | 无明显增加 | 对比重构前后 |

---

## 问题排查

### 常见问题

1. **编译错误：undefined**
   - 检查 import 是否正确
   - 检查函数/类型名称是否拼写正确

2. **运行时 panic：nil pointer**
   - 检查组件是否正确添加
   - 检查资源是否正确初始化

3. **NPC AI 不工作**
   - 检查系统是否正确初始化
   - 检查 NPC 是否有决策组件
   - 检查日志是否有错误

4. **警察系统不工作**
   - 检查 IsNpcPolice() 返回值
   - 检查警察组件是否正确添加
   - 检查 EnablePolice 配置

### 日志关键字

```bash
# 查看感知系统日志
grep "SensorFeatureSystem" logs/scene_server.log

# 查看决策系统日志
grep "DecisionSystem" logs/scene_server.log

# 查看视野系统日志
grep "VisionSystem" logs/scene_server.log

# 查看警察系统日志
grep "PoliceSystem" logs/scene_server.log

# 查看 NPC 创建日志
grep "CreateSceneNpc\|CreateTownNpc\|CreateSakuraNpc" logs/scene_server.log
```
