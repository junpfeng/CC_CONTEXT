---
name: npc-component
description: 创建或修改 NPC 相关组件
---

# NPC 组件开发助手

当用户需要创建或修改 NPC 相关组件时，执行以下步骤：

## 步骤

### 1. 确定组件类型和位置

NPC 相关组件位于：
- `servers/scene_server/internal/ecs/com/cnpc/` - NPC 核心组件
- `servers/scene_server/internal/ecs/com/cvision/` - 视野组件
- `servers/scene_server/internal/ecs/com/caidecision/` - 决策组件

### 2. 组件模板

```go
package cnpc

import (
    "mp/servers/scene_server/internal/common"
)

var _ common.Component = (*MyNpcComp)(nil)

type MyNpcComp struct {
    common.ComponentBase
    // 数据字段
    Field1 int32
    Field2 string
}

func NewMyNpcComp() *MyNpcComp {
    return &MyNpcComp{}
}

func (c *MyNpcComp) Type() common.ComponentType {
    return common.ComponentType_MyNpc
}

// 可选：从数据初始化
func (c *MyNpcComp) InitFromData(data proto_code.IProto) bool {
    // 反序列化数据
    return true
}

// 可选：保存数据
func (c *MyNpcComp) SaveData() (proto_code.IProto, bool) {
    // 序列化数据
    return nil, false
}

// 可选：同步脏数据
func (c *MyNpcComp) SyncDirtyData() (proto_code.IProto, bool) {
    if !c.IsDirtySync() {
        return nil, false
    }
    c.ClearDirtySync()
    // 返回需要同步的数据
    return nil, true
}
```

### 3. 注册组件类型

在 `servers/scene_server/internal/common/ecs.go` 中添加：
```go
const (
    // ...
    ComponentType_MyNpc ComponentType = xxx
)
```

### 4. 在工厂中注册

在 `servers/scene_server/internal/ecs/com/factory.go` 中添加创建逻辑。

## 关键文件参考

- @servers/scene_server/internal/ecs/com/cnpc/npc_comp.go
- @servers/scene_server/internal/ecs/com/cnpc/npc_move.go
- @servers/scene_server/internal/ecs/com/cvision/vision_comp.go
- @servers/scene_server/internal/common/ecs.go

## 使用方式

- `/npc-component create <name>` - 创建新组件
- `/npc-component modify <file>` - 修改现有组件
- `/npc-component add-field <component> <field>` - 添加字段
