# 需求文档：扩展交通载具功能支持樱花校园

## 1. 需求概述

将现有的交通载具生成功能（OnTrafficVehicleReq 协议）从大世界场景扩展到樱花校园场景。

## 2. 背景

**当前状态**：
- `OnTrafficVehicleReq` 协议在 Rust 大世界场景中已实现
- 用于生成 NPC 驾驶的环境载具（交通系统载具）
- Go 服务器中该协议处于未实现状态（temp/external.go）

**业务需求**：
- 樱花校园需要环境交通载具增强场景氛围
- 需要与大世界保持一致的载具生成体验

## 3. 功能说明

### 3.1 OnTrafficVehicleReq 协议功能

**用途**：在场景中动态生成 NPC 驾驶的交通载具

**参数**：
- `vehicle_cfg_id`：载具配置ID
- `location`：生成位置（Vector3）
- `rotation`：生成旋转角度（Vector3）
- `target_seat`：目标座位
- `color_list`：载具颜色列表

**特性**：
- 载具标记为交通系统载具（`is_traffic_system = true`）
- 自动消失机制（`need_auto_vanish = true`）
- 触碰时间戳管理

### 3.2 扩展目标

**实现范围**：
1. ✅ Go 服务器实现 OnTrafficVehicleReq 处理逻辑
2. ✅ 支持大世界场景（CitySceneInfo）
3. ✅ 支持樱花校园场景（SakuraSceneInfo）
4. ✅ 场景隔离：不同场景的载具互不干扰

## 4. 验收标准

- [ ] Go 服务器正确处理 OnTrafficVehicleReq 请求
- [ ] 大世界场景可以生成交通载具
- [ ] 樱花校园场景可以生成交通载具
- [ ] 副本场景不支持交通载具（安全限制）
- [ ] 载具自动消失机制正常工作
- [ ] 构建和测试通过

## 5. 技术约束

### 5.1 场景类型支持

| 场景类型 | 是否支持 | 说明 |
|---------|---------|------|
| CitySceneInfo（大世界） | ✅ | 主要使用场景 |
| SakuraSceneInfo（樱花校园） | ✅ | 新增支持 |
| TownSceneInfo（小镇） | ❓ | 待确认 |
| DungeonSceneInfo（副本） | ❌ | 安全考虑，不支持 |

### 5.2 依赖系统

- VehicleSpawnInfo：载具生成信息
- VehicleStatusComp：载具状态组件
- ECS 系统：实体创建和组件管理

## 6. 涉及工程

- **业务工程（P1GoServer）**：实现协议处理逻辑
- **协议工程**：无需修改（协议已存在）
- **配置工程**：无需修改（使用现有载具配置）
- **Rust 遗留工程**：仅作参考

## 7. 优先级

**P1 - 高优先级**

理由：樱花校园场景完善的必要功能，影响场景氛围和玩家体验。

## 8. 风险点

| 风险 | 严重性 | 缓解措施 |
|------|--------|----------|
| 载具生成逻辑 Go/Rust 不一致 | 中 | 参考 Rust 实现，确保行为一致 |
| 场景切换时载具状态 | 低 | 交通载具自动消失，无需跨场景同步 |
| 载具配置ID在不同场景下兼容性 | 低 | 使用统一的载具配置表 |

## 9. 参考资料

- Rust 实现：`server_old/servers/scene/src/scene_service/service_for_scene.rs`
- 协议定义：`proto/old_proto/scene/scene.proto`
- 场景隔离模式：参考时间系统的扩展方式
