---
name: optimize
description: 性能优化分析和建议
---

# 性能优化助手

当用户调用此 skill 时，帮助分析和优化代码性能。

## 优化流程

### 1. 性能分析

#### CPU 分析
```bash
# 生成 CPU profile
go test -cpuprofile=cpu.prof -bench=.
go tool pprof cpu.prof

# 或在运行时收集
import _ "net/http/pprof"
go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30
```

#### 内存分析
```bash
# 生成内存 profile
go test -memprofile=mem.prof -bench=.
go tool pprof mem.prof

# 查看内存分配
go tool pprof -alloc_space mem.prof
```

#### Trace 分析
```bash
go test -trace=trace.out
go tool trace trace.out
```

### 2. 常见优化点

#### 内存优化

```go
// 避免不必要的分配
// Bad
func process(items []Item) []Result {
    var results []Result
    for _, item := range items {
        results = append(results, convert(item))
    }
    return results
}

// Good: 预分配
func process(items []Item) []Result {
    results := make([]Result, 0, len(items))
    for _, item := range items {
        results = append(results, convert(item))
    }
    return results
}
```

```go
// 使用 sync.Pool 复用对象
var bufPool = sync.Pool{
    New: func() interface{} {
        return new(bytes.Buffer)
    },
}

func process() {
    buf := bufPool.Get().(*bytes.Buffer)
    defer func() {
        buf.Reset()
        bufPool.Put(buf)
    }()
    // 使用 buf
}
```

#### 并发优化

```go
// 使用 worker pool
func processItems(items []Item, workers int) []Result {
    jobs := make(chan Item, len(items))
    results := make(chan Result, len(items))

    // 启动 workers
    for w := 0; w < workers; w++ {
        go worker(jobs, results)
    }

    // 发送任务
    for _, item := range items {
        jobs <- item
    }
    close(jobs)

    // 收集结果
    var output []Result
    for range items {
        output = append(output, <-results)
    }
    return output
}
```

#### 算法优化

- 使用合适的数据结构（map vs slice）
- 减少循环嵌套
- 避免不必要的排序
- 使用缓存

#### I/O 优化

```go
// 使用 bufio
reader := bufio.NewReader(file)
writer := bufio.NewWriter(file)

// 批量处理数据库操作
tx, _ := db.Begin()
stmt, _ := tx.Prepare("INSERT INTO table VALUES (?)")
for _, item := range items {
    stmt.Exec(item)
}
tx.Commit()
```

### 3. Benchmark 编写

```go
func BenchmarkFunction(b *testing.B) {
    // 准备数据
    data := prepareData()

    b.ResetTimer() // 重置计时器

    for i := 0; i < b.N; i++ {
        Function(data)
    }
}

// 运行
// go test -bench=. -benchmem
```

## 输出格式

```markdown
## 性能优化报告

### 当前性能指标
- 执行时间: Xms
- 内存分配: Y MB
- GC 暂停: Z ms

### 发现的瓶颈
1. **瓶颈1** (文件:行号)
   - 问题: 描述
   - 影响: 性能影响程度
   - 建议: 优化建议

### 优化建议

#### 高优先级
- [ ] 优化点1

#### 中优先级
- [ ] 优化点2

### 预期收益
- 执行时间: 预计减少 X%
- 内存使用: 预计减少 Y%
```

## 使用方式

- `/optimize path/to/file.go` - 分析指定文件
- `/optimize --profile` - 生成性能报告
- `/optimize --memory` - 专注内存优化
- `/optimize --cpu` - 专注 CPU 优化
