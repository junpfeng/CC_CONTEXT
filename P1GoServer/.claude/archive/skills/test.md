---
name: test
description: 运行测试、生成测试用例、分析测试覆盖率
---

# 测试助手

当用户调用此 skill 时，帮助进行测试相关的工作。

## 功能

### 1. 运行测试

```bash
# 运行所有测试
go test ./...

# 运行特定包的测试
go test ./path/to/package

# 运行特定测试函数
go test -run TestFunctionName ./...

# 带覆盖率运行
go test -cover ./...

# 详细输出
go test -v ./...
```

### 2. 生成测试用例

为指定的函数或文件生成测试用例，包括：

- **表驱动测试** (Table-driven tests)
- **边界条件测试**
- **错误场景测试**
- **并发测试** (如适用)

测试模板：
```go
func TestFunctionName(t *testing.T) {
    tests := []struct {
        name    string
        input   InputType
        want    OutputType
        wantErr bool
    }{
        {
            name:    "正常情况",
            input:   validInput,
            want:    expectedOutput,
            wantErr: false,
        },
        {
            name:    "边界条件",
            input:   boundaryInput,
            want:    boundaryOutput,
            wantErr: false,
        },
        {
            name:    "错误情况",
            input:   invalidInput,
            want:    zeroValue,
            wantErr: true,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := FunctionName(tt.input)
            if (err != nil) != tt.wantErr {
                t.Errorf("FunctionName() error = %v, wantErr %v", err, tt.wantErr)
                return
            }
            if got != tt.want {
                t.Errorf("FunctionName() = %v, want %v", got, tt.want)
            }
        })
    }
}
```

### 3. 分析测试覆盖率

```bash
# 生成覆盖率报告
go test -coverprofile=coverage.out ./...

# 查看覆盖率详情
go tool cover -func=coverage.out

# 生成 HTML 报告
go tool cover -html=coverage.out -o coverage.html
```

### 4. Mock 生成

使用 mockgen 或手动创建 mock：
```go
type MockService struct {
    mock.Mock
}

func (m *MockService) Method(arg Type) (Result, error) {
    args := m.Called(arg)
    return args.Get(0).(Result), args.Error(1)
}
```

## 使用方式

- `/test` - 运行所有测试
- `/test path/to/file.go` - 为指定文件生成测试
- `/test -cover` - 运行测试并显示覆盖率
- `/test FunctionName` - 为指定函数生成测试
