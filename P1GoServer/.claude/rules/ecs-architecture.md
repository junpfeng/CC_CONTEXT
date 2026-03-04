---
paths:
  - "servers/scene_server/internal/ecs/**/*.go"
---

# ECS 架构开发规范

## 核心原则

1. **数据与逻辑分离**
   - Component 只存储数据，不包含业务逻辑
   - System 只处理逻辑，通过 Scene 接口访问 Component
   - Entity 是纯容器，不包含任何逻辑

2. **组件设计**
   - 每个 Component 必须实现 `common.Component` 接口
   - 使用 `common.ComponentBase` 作为基类
   - 组件类型必须在 `common.ComponentType` 中注册
   - 支持脏标记：`dirtyFlagSync`（同步）和 `dirtyFlagSave`（持久化）

3. **系统设计**
   - 每个 System 必须实现 `common.System` 接口
   - 使用 `system.SystemBase` 作为基类
   - 系统类型必须在 `common.SystemType` 中注册
   - 生命周期：`OnBeforeTick` → `Update` → `OnAfterTick`

## 组件模板

```go
type MyComp struct {
    common.ComponentBase
    // 数据字段
}

func NewMyComp() *MyComp {
    return &MyComp{}
}

func (c *MyComp) Type() common.ComponentType {
    return common.ComponentType_My
}

// 需要同步时调用 c.SetSync()
// 需要保存时调用 c.SetSave()
```

## 系统模板

```go
type MySystem struct {
    *system.SystemBase
}

func New(scene common.Scene) common.System {
    return &MySystem{
        SystemBase: system.New(scene),
    }
}

func (s *MySystem) Type() common.SystemType {
    return common.SystemType_My
}

func (s *MySystem) Update(dt time.Duration) {
    // 通过 s.Scene().ComList() 获取组件
    // 批量处理逻辑
}
```

## 禁止事项

- 禁止在 Component 中直接调用其他 Component 的方法
- 禁止在 Component 中修改其他 Entity 的状态
- 禁止绕过 Scene 接口直接操作 Entity
- 禁止在 System 中存储 Entity/Component 的引用（应每帧查询）
