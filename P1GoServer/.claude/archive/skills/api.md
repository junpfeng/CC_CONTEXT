---
name: api
description: 设计和实现 API 接口
---

# API 设计助手

当用户调用此 skill 时，帮助设计和实现 RESTful API。

## API 设计原则

### 1. RESTful 规范

| 操作 | HTTP 方法 | 路径示例 | 描述 |
|------|----------|---------|------|
| 列表 | GET | /users | 获取用户列表 |
| 详情 | GET | /users/:id | 获取单个用户 |
| 创建 | POST | /users | 创建用户 |
| 更新 | PUT | /users/:id | 全量更新 |
| 部分更新 | PATCH | /users/:id | 部分更新 |
| 删除 | DELETE | /users/:id | 删除用户 |

### 2. 路径设计

```
# Good
GET  /api/v1/users
GET  /api/v1/users/{id}
GET  /api/v1/users/{id}/orders
POST /api/v1/users/{id}/orders

# Bad
GET  /api/v1/getUsers
POST /api/v1/createUser
GET  /api/v1/user/orders/list
```

### 3. 请求/响应格式

#### 成功响应
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "id": 1,
    "name": "example"
  }
}
```

#### 列表响应
```json
{
  "code": 0,
  "message": "success",
  "data": {
    "list": [],
    "total": 100,
    "page": 1,
    "page_size": 20
  }
}
```

#### 错误响应
```json
{
  "code": 10001,
  "message": "参数错误",
  "error": "field 'name' is required"
}
```

### 4. 状态码使用

| 状态码 | 含义 | 使用场景 |
|-------|------|---------|
| 200 | OK | 成功 |
| 201 | Created | 创建成功 |
| 204 | No Content | 删除成功 |
| 400 | Bad Request | 参数错误 |
| 401 | Unauthorized | 未认证 |
| 403 | Forbidden | 无权限 |
| 404 | Not Found | 资源不存在 |
| 500 | Internal Error | 服务器错误 |

## Go API 实现模板

### Handler 模板
```go
// CreateUserRequest 创建用户请求
type CreateUserRequest struct {
    Name  string `json:"name" binding:"required"`
    Email string `json:"email" binding:"required,email"`
}

// CreateUserResponse 创建用户响应
type CreateUserResponse struct {
    ID        int64     `json:"id"`
    Name      string    `json:"name"`
    Email     string    `json:"email"`
    CreatedAt time.Time `json:"created_at"`
}

// CreateUser 创建用户
// @Summary 创建用户
// @Tags 用户管理
// @Accept json
// @Produce json
// @Param request body CreateUserRequest true "请求参数"
// @Success 200 {object} Response{data=CreateUserResponse}
// @Router /api/v1/users [post]
func (h *Handler) CreateUser(c *gin.Context) {
    var req CreateUserRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(400, Response{Code: 10001, Message: "参数错误"})
        return
    }

    user, err := h.service.CreateUser(c.Request.Context(), req)
    if err != nil {
        c.JSON(500, Response{Code: 50001, Message: "创建失败"})
        return
    }

    c.JSON(200, Response{Code: 0, Data: user})
}
```

### 路由注册
```go
func RegisterRoutes(r *gin.Engine, h *Handler) {
    v1 := r.Group("/api/v1")
    {
        users := v1.Group("/users")
        {
            users.GET("", h.ListUsers)
            users.GET("/:id", h.GetUser)
            users.POST("", h.CreateUser)
            users.PUT("/:id", h.UpdateUser)
            users.DELETE("/:id", h.DeleteUser)
        }
    }
}
```

## 使用方式

- `/api design` - 交互式设计新 API
- `/api create /users` - 创建用户相关 API
- `/api docs` - 生成 API 文档
- `/api validate` - 验证 API 设计规范
