---
name: 巡逻路线 WalkZone 扩展与 V2Brain 大世界配置
status: discarded
---

## 范围
- 修改: P1GoServer/servers/scene_server/internal/common/ai/patrol/patrol_config.go — PatrolRoute 结构体新增 WalkZone string `json:"walkZone"` 字段，JSON 反序列化自动填充
- 新增: P1GoServer/bin/config/ai_decision_v2/bigworld_engagement.json — 大世界 engagement 维度决策配置
- 新增: P1GoServer/bin/config/ai_decision_v2/bigworld_expression.json — 大世界 expression 维度决策配置
- 新增: P1GoServer/bin/config/ai_decision_v2/bigworld_locomotion.json — 大世界 locomotion 维度决策配置（含 patrol 计划状态转移）
- 新增: P1GoServer/bin/config/ai_decision_v2/bigworld_navigation.json — 大世界 navigation 维度决策配置

## 验证标准
- 服务端 make build 编译通过
- PatrolRoute 可正确反序列化含 walkZone 字段的 JSON
- 4 个 bigworld_ 前缀配置文件格式符合 V2Brain BrainConfig 结构
- 小镇配置文件不受影响

## 依赖
- 无
