---
name: docs
description: 生成代码文档、API 文档、README
---

# 文档生成助手

当用户调用此 skill 时，帮助生成各类文档。

## 文档类型

### 1. 代码注释 (GoDoc)

为 Go 代码生成符合 GoDoc 规范的注释：

```go
// Package packagename provides functionality for ...
//
// Example usage:
//
//     result, err := packagename.DoSomething(input)
//     if err != nil {
//         log.Fatal(err)
//     }
package packagename

// FunctionName does something important.
//
// It takes input and returns output. If the input is invalid,
// it returns an error.
//
// Parameters:
//   - input: description of input
//
// Returns:
//   - output: description of output
//   - error: nil on success, error on failure
func FunctionName(input Type) (output Type, err error) {
    // ...
}
```

### 2. API 文档

生成 RESTful API 文档：

```markdown
## API Endpoint

### POST /api/v1/resource

创建新资源

#### Request

**Headers:**
- `Content-Type: application/json`
- `Authorization: Bearer <token>`

**Body:**
```json
{
  "field1": "value1",
  "field2": 123
}
```

#### Response

**Success (200):**
```json
{
  "id": "uuid",
  "field1": "value1",
  "created_at": "2024-01-01T00:00:00Z"
}
```

**Error (400):**
```json
{
  "error": "error message",
  "code": "ERROR_CODE"
}
```
```

### 3. README 生成

项目 README 模板：

```markdown
# Project Name

简短描述

## Features

- Feature 1
- Feature 2

## Installation

## Usage

## Configuration

## API Reference

## Contributing

## License
```

### 4. 架构文档

- 系统架构图描述
- 组件交互说明
- 数据流说明
- 部署架构

## 使用方式

- `/docs path/to/file.go` - 为文件生成 GoDoc 注释
- `/docs api` - 生成 API 文档
- `/docs readme` - 生成 README
- `/docs architecture` - 生成架构文档
