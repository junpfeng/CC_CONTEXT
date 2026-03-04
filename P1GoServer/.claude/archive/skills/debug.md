---
name: debug
description: 帮助调试代码问题、分析错误日志
---

# 调试助手

当用户调用此 skill 时，帮助定位和解决代码问题。

## 调试流程

### 1. 收集信息

- **错误信息**: 完整的错误消息和堆栈跟踪
- **复现步骤**: 如何触发这个问题
- **预期行为**: 期望的正确行为
- **环境信息**: Go 版本、操作系统、依赖版本

### 2. 分析问题

#### 常见问题类型

**空指针/nil 引用**
```go
// 问题
var ptr *Type
ptr.Method() // panic: nil pointer dereference

// 解决
if ptr != nil {
    ptr.Method()
}
```

**并发问题**
```go
// 问题: 数据竞争
go func() { counter++ }()
go func() { counter++ }()

// 解决: 使用 mutex 或 atomic
atomic.AddInt64(&counter, 1)
```

**资源泄漏**
```go
// 问题: 文件句柄泄漏
f, _ := os.Open(path)
// 忘记 close

// 解决: 使用 defer
f, err := os.Open(path)
if err != nil {
    return err
}
defer f.Close()
```

**死锁**
```go
// 检查 channel 阻塞
// 检查 mutex 嵌套锁定
// 使用 go run -race 检测
```

### 3. 调试工具

```bash
# 运行 race detector
go run -race main.go

# 使用 delve 调试器
dlv debug main.go

# 查看 goroutine 堆栈
kill -SIGQUIT <pid>

# pprof 性能分析
go tool pprof http://localhost:6060/debug/pprof/goroutine
```

### 4. 日志分析

```go
// 添加调试日志
log.Printf("[DEBUG] variable=%+v", variable)

// 使用结构化日志
logger.Debug("operation completed",
    "key", value,
    "duration", elapsed,
)
```

### 5. 常用调试命令

```bash
# 查看进程状态
ps aux | grep process_name

# 查看端口占用
lsof -i :port
netstat -tlnp | grep port

# 查看系统资源
top -p <pid>
htop

# 查看日志
tail -f /path/to/log
journalctl -u service_name -f
```

## 输出格式

```markdown
## 问题诊断报告

### 问题描述
[问题的简要描述]

### 根本原因
[分析出的根本原因]

### 解决方案
1. [步骤1]
2. [步骤2]

### 代码修改
[具体的代码修改建议]

### 预防措施
[如何避免类似问题]
```

## 使用方式

- `/debug` - 交互式调试当前问题
- `/debug error_message` - 分析特定错误
- `/debug path/to/file.go:123` - 调试特定代码位置
