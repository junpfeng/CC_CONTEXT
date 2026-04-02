---
name: project_animal_system_review
description: 动物系统技术设计审查（2026-03-23），严重问题：BtTickSystem 单管线无法路由Animal/NPC共存、客户端模块路径S1Town与BigWorld矛盾
type: project
---

动物系统（Dog/Bird/Crocodile/Chicken）技术设计审查，有条件通过。

**严重问题（2个）**:
1. BtTickSystem 持有单一 orthogonalPipeline，大世界中动物和人形NPC共存需要按ExtType路由到不同管线，当前架构不支持
2. client.md 路径写 S1Town，technical_design.md 写 BigWorld，互相矛盾

**建议改进（4个）**:
1. follow_target_id 下发与"内部状态不下发"描述矛盾
2. 错误码 10005→14001 跳段过大
3. Chicken 纯静态但仍注册感知系统浪费
4. 食物物品校验规则未定义

**Why:** 动物系统是首次在大世界场景中引入非人形NPC ExtType，BtTickSystem 的管线路由是架构级问题。

**How to apply:** 后续涉及多ExtType共存的设计都需关注管线路由和同步分叉。
