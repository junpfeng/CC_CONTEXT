---
name: refactor
description: 智能重构代码，提升代码质量
---

# 代码重构助手

当用户调用此 skill 时，帮助进行代码重构。

## 重构类型

### 1. 提取函数 (Extract Function)
将一段代码提取为独立函数：
- 识别可重用的代码块
- 确定输入参数和返回值
- 为函数命名
- 替换原代码为函数调用

### 2. 提取接口 (Extract Interface)
从具体实现中提取接口：
- 分析类/结构体的公开方法
- 创建对应的接口定义
- 更新依赖方使用接口

### 3. 重命名 (Rename)
批量重命名：
- 变量/常量
- 函数/方法
- 类型/结构体
- 包名

### 4. 移动 (Move)
移动代码到更合适的位置：
- 移动函数到其他文件/包
- 重组包结构
- 拆分大文件

### 5. 简化条件 (Simplify Conditionals)
- 合并嵌套 if
- 使用 early return
- 简化布尔表达式
- 使用 switch 替代多重 if-else

### 6. 消除重复 (Remove Duplication)
- 识别重复代码
- 提取公共逻辑
- 创建共享函数或方法

## 重构原则

1. **小步前进** - 每次只做一个小改动
2. **保持测试通过** - 每次改动后运行测试
3. **不改变行为** - 重构不应改变代码的外部行为
4. **提交频繁** - 每完成一步重构就提交

## 重构禁忌（经验教训）

### 1. 不要随意改变代码风格
- **禁止**：将 switch-case 改为 if-else（或反之）
- **原因**：用户可能有特定的代码风格偏好，switch-case 更清晰地表达状态分支
- **正确做法**：保持原有代码结构，只修改必要的逻辑

### 2. 移除代码前确认调用链完整
- **问题案例**：移除业务系统中的特征更新代码，但忘记确认感知器是否被调用
- **正确做法**：
  1. 确认新的处理位置（如 MiscSensor）已正确实现
  2. 确认新处理位置的调用代码没有被注释
  3. 全局搜索确认没有遗漏的调用点

### 3. 不要注释掉调用代码
- **问题案例**：在 sensor_feature.go 中，`miscSensor.GetAndUpdateFeature(entityID)` 被注释掉
- **后果**：整个感知器失效，导致功能异常
- **正确做法**：明确删除或保留，不要留下注释掉的代码

### 4. 使用正确的 API
- **问题案例**：使用不存在的 `common.GetSystemAs[T]()` 或 `sensor.EventSensor.Get()`
- **正确做法**：先检查目标包中实际存在的方法
  ```go
  // 获取系统的正确方式
  eventSystem, ok := sensor.EventSensor.Get(scene)  // 使用 helper
  // 或
  sys, ok := scene.GetSystem(common.SystemType_EventSensor)
  eventSystem := sys.(*sensor.EventSensorSystem)
  ```

### 5. 使用 Agent 重构时的注意事项
- **逐步验证**：每个 Phase 完成后立即编译验证
- **检查 Agent 的修改**：Agent 可能会：
  - 注释掉关键代码
  - 改变代码风格
  - 使用不存在的 API
- **功能测试**：编译通过不等于功能正常，需要实际测试

## 输出格式

```markdown
## 重构计划

### 识别的问题
- 问题1: 描述
- 问题2: 描述

### 重构步骤
1. [ ] 步骤1
2. [ ] 步骤2
3. [ ] 步骤3

### 预期效果
- 改进1
- 改进2

### 风险评估
- 潜在风险及缓解措施
```

## 使用方式

- `/refactor path/to/file.go` - 分析并建议重构
- `/refactor extract-func` - 提取函数
- `/refactor rename OldName NewName` - 重命名
- `/refactor simplify` - 简化当前文件的代码
