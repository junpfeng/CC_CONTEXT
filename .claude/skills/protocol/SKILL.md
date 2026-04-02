---
name: protocol
description: "协议设计规范：自定义proto格式定义、消息序列化。当涉及协议定义、消息格式、proto文件时使用。"
user-invocable: false
---

# 协议设计规范

## 概述

项目使用**自定义 proto 格式**（非标准 protobuf）定义协议，协议目录位于 `../Proto`（相对于 Server）。

**重要提示**：这不是标准的 Protocol Buffers 格式，只能使用本文档中列出的关键字和语法。

## 注意事项

1. **字段编号**：一旦发布不要修改已有字段的编号
2. **向后兼容**：新增字段使用新编号，不要删除旧字段
3. **注释规范**：每个字段都应添加中文注释说明用途
4. **包名规范**：
   - 客户端协议使用服务名作为包名（如 `lobby`, `room`）
   - 内部协议使用 `xxx_inner` 格式（如 `room_inner`）

@references/detail.md
