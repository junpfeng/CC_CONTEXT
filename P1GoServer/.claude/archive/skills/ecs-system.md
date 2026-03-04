---
name: ecs-system
description: 创建 ECS System（系统）
---

# ECS System 开发助手

当用户需要创建新的 ECS System 时使用。

## System 模板

```go
// servers/scene_server/internal/ecs/system/mysystem/mysystem.go
package mysystem

import (
    "time"

    "mp/servers/scene_server/internal/common"
    "mp/servers/scene_server/internal/ecs/system"
)

type MySystem struct {
    *system.SystemBase
    // 系统私有状态
    lastUpdateTime int64
}

func New(scene common.Scene) common.System {
    return &MySystem{
        SystemBase: system.New(scene),
    }
}

func (s *MySystem) Type() common.SystemType {
    return common.SystemType_My
}

// OnBeforeTick 每帧开始前调用
func (s *MySystem) OnBeforeTick(dt time.Duration) {
    // 准备工作
}

// Update 每帧主逻辑
func (s *MySystem) Update(dt time.Duration) {
    // 获取相关组件
    comList := s.Scene().ComList(common.ComponentType_My)

    for _, com := range comList {
        myCom := com.(*mycom.MyComp)
        // 处理逻辑
    }
}

// OnAfterTick 每帧结束后调用
func (s *MySystem) OnAfterTick(dt time.Duration) {
    // 清理工作
}

// OnMsg 处理消息
func (s *MySystem) OnMsg(msg any) error {
    switch m := msg.(type) {
    case *MyMessage:
        return s.handleMyMessage(m)
    }
    return nil
}

// OnRpc 处理 RPC 调用
func (s *MySystem) OnRpc(msg any) (any, error) {
    return nil, nil
}

// OnDestroy 销毁时调用
func (s *MySystem) OnDestroy() {
    // 清理资源
}
```

## 注册步骤

### 1. 添加系统类型

```go
// servers/scene_server/internal/common/ecs.go
const (
    // ...
    SystemType_My SystemType = xxx
)
```

### 2. 在 Scene 初始化时添加

```go
// servers/scene_server/internal/ecs/scene/scene.go
func (s *scene) initSystems() {
    // ...
    s.AddSystem(mysystem.New(s))
}
```

## 系统设计原则

1. **单一职责**：每个系统只处理一类逻辑
2. **无状态优先**：尽量不在系统中存储状态，状态应在组件中
3. **批量处理**：通过 ComList 批量获取组件，减少查询次数
4. **帧间隔控制**：对于不需要每帧执行的逻辑，使用时间间隔控制

```go
const updateInterval = 500 * time.Millisecond

func (s *MySystem) Update(dt time.Duration) {
    now := time.Now().UnixMilli()
    if now - s.lastUpdateTime < int64(updateInterval.Milliseconds()) {
        return
    }
    s.lastUpdateTime = now

    // 执行逻辑
}
```

## 关键文件

- @servers/scene_server/internal/ecs/system/system.go
- @servers/scene_server/internal/common/ecs.go
- @servers/scene_server/internal/ecs/scene/scene.go

## 使用方式

- `/ecs-system create <name>` - 创建新系统
- `/ecs-system list` - 列出所有系统
