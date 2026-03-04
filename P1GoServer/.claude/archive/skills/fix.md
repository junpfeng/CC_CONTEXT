---
name: fix
description: 智能修复代码错误和 Bug
---

# Bug 修复助手

当用户调用此 skill 时，帮助定位和修复代码中的 Bug。

## 修复流程

### 1. 问题识别

- 收集错误信息（错误消息、堆栈跟踪）
- 确定错误发生的位置
- 理解预期行为与实际行为的差异

### 2. 根因分析

常见 Bug 类型：

| 类型 | 表现 | 常见原因 |
|------|------|----------|
| 空指针 | panic: nil pointer | 未初始化、未检查返回值 |
| 数组越界 | index out of range | 边界条件错误 |
| 并发问题 | 数据不一致、死锁 | 缺少同步、锁顺序错误 |
| 逻辑错误 | 结果不正确 | 条件判断错误、算法问题 |
| 资源泄漏 | 内存增长、句柄耗尽 | 未关闭资源、goroutine 泄漏 |
| 类型错误 | 类型断言失败 | 类型假设错误 |

### 3. 修复策略

#### 空指针修复
```go
// Before
func process(data *Data) {
    fmt.Println(data.Field) // 可能 panic
}

// After
func process(data *Data) {
    if data == nil {
        return // 或返回错误
    }
    fmt.Println(data.Field)
}
```

#### 错误处理修复
```go
// Before
result, _ := doSomething() // 忽略错误

// After
result, err := doSomething()
if err != nil {
    return fmt.Errorf("doSomething failed: %w", err)
}
```

#### 并发修复
```go
// Before
var counter int
go func() { counter++ }()
go func() { counter++ }()

// After
var counter int64
go func() { atomic.AddInt64(&counter, 1) }()
go func() { atomic.AddInt64(&counter, 1) }()
```

#### 资源泄漏修复
```go
// Before
func readFile(path string) ([]byte, error) {
    f, err := os.Open(path)
    if err != nil {
        return nil, err
    }
    // 忘记关闭文件
    return io.ReadAll(f)
}

// After
func readFile(path string) ([]byte, error) {
    f, err := os.Open(path)
    if err != nil {
        return nil, err
    }
    defer f.Close()
    return io.ReadAll(f)
}
```

### 4. 验证修复

- 编写测试用例复现 Bug
- 应用修复后运行测试
- 检查是否引入新问题
- 运行相关的回归测试

## 输出格式

```markdown
## Bug 修复报告

### 问题描述
[Bug 的表现和影响]

### 根本原因
[分析出的根本原因]

### 修复方案
[详细的修复方案]

### 代码变更
```diff
- 旧代码
+ 新代码
```

### 测试验证
- [ ] 添加了复现 Bug 的测试
- [ ] 修复后测试通过
- [ ] 回归测试通过

### 预防措施
[如何避免类似问题]
```

## 使用方式

- `/fix` - 交互式修复当前问题
- `/fix "error message"` - 根据错误信息修复
- `/fix path/to/file.go:123` - 修复指定位置的问题
