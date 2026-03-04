---
name: mock
description: 生成 Mock 数据和测试替身
---

# Mock 生成助手

当用户调用此 skill 时，帮助生成 Mock 代码和测试数据。

## Mock 类型

### 1. 接口 Mock

使用 mockgen 生成：
```bash
# 安装 mockgen
go install github.com/golang/mock/mockgen@latest

# 生成 mock
mockgen -source=interface.go -destination=mock_interface.go -package=mocks
```

手动创建 Mock：
```go
type MockUserRepository struct {
    mock.Mock
}

func (m *MockUserRepository) GetByID(ctx context.Context, id int64) (*User, error) {
    args := m.Called(ctx, id)
    if args.Get(0) == nil {
        return nil, args.Error(1)
    }
    return args.Get(0).(*User), args.Error(1)
}

func (m *MockUserRepository) Create(ctx context.Context, user *User) error {
    args := m.Called(ctx, user)
    return args.Error(0)
}

// 使用示例
func TestUserService_GetUser(t *testing.T) {
    mockRepo := new(MockUserRepository)

    expectedUser := &User{ID: 1, Name: "Test"}
    mockRepo.On("GetByID", mock.Anything, int64(1)).Return(expectedUser, nil)

    service := NewUserService(mockRepo)
    user, err := service.GetUser(context.Background(), 1)

    assert.NoError(t, err)
    assert.Equal(t, expectedUser, user)
    mockRepo.AssertExpectations(t)
}
```

### 2. HTTP Mock

```go
// 使用 httptest
func TestHTTPHandler(t *testing.T) {
    // 创建请求
    req := httptest.NewRequest("GET", "/users/1", nil)
    rec := httptest.NewRecorder()

    // 调用处理器
    handler.ServeHTTP(rec, req)

    // 断言
    assert.Equal(t, http.StatusOK, rec.Code)
}

// Mock 外部 HTTP 服务
func TestExternalAPI(t *testing.T) {
    server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.WriteHeader(http.StatusOK)
        w.Write([]byte(`{"status": "ok"}`))
    }))
    defer server.Close()

    client := NewClient(server.URL)
    result, err := client.Call()

    assert.NoError(t, err)
    assert.Equal(t, "ok", result.Status)
}
```

### 3. 数据库 Mock

```go
// 使用 sqlmock
import "github.com/DATA-DOG/go-sqlmock"

func TestQuery(t *testing.T) {
    db, mock, err := sqlmock.New()
    require.NoError(t, err)
    defer db.Close()

    rows := sqlmock.NewRows([]string{"id", "name"}).
        AddRow(1, "Test User")

    mock.ExpectQuery("SELECT id, name FROM users").
        WillReturnRows(rows)

    // 执行测试
    repo := NewRepository(db)
    users, err := repo.List()

    assert.NoError(t, err)
    assert.Len(t, users, 1)
    assert.NoError(t, mock.ExpectationsWereMet())
}
```

### 4. Redis Mock

```go
// 使用 miniredis
import "github.com/alicebob/miniredis/v2"

func TestRedisCache(t *testing.T) {
    mr, err := miniredis.Run()
    require.NoError(t, err)
    defer mr.Close()

    client := redis.NewClient(&redis.Options{
        Addr: mr.Addr(),
    })

    cache := NewCache(client)

    // 测试
    err = cache.Set("key", "value", time.Hour)
    assert.NoError(t, err)

    value, err := cache.Get("key")
    assert.NoError(t, err)
    assert.Equal(t, "value", value)
}
```

### 5. 测试数据生成

```go
// 使用 faker
import "github.com/bxcodec/faker/v3"

type User struct {
    ID    int64  `faker:"-"`
    Name  string `faker:"name"`
    Email string `faker:"email"`
    Phone string `faker:"phone_number"`
}

func GenerateTestUser() *User {
    var user User
    faker.FakeData(&user)
    return &user
}

// 或手动构建
func NewTestUser(opts ...func(*User)) *User {
    user := &User{
        ID:    1,
        Name:  "Test User",
        Email: "test@example.com",
    }
    for _, opt := range opts {
        opt(user)
    }
    return user
}

func WithName(name string) func(*User) {
    return func(u *User) {
        u.Name = name
    }
}
```

## 使用方式

- `/mock interface.go` - 为接口生成 Mock
- `/mock http` - 生成 HTTP Mock
- `/mock db` - 生成数据库 Mock
- `/mock data User` - 生成测试数据
