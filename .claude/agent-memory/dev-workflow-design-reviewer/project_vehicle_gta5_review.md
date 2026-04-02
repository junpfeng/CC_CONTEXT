---
name: vehicle_gta5_review
description: 载具系统GTA5级提升设计审查（2026-04-01），CRITICAL：损伤上报链路不存在（SendDamageInfo是本地采集非网络发送）、VehicleDataUpdate缺损伤字段导致新玩家无损伤表现
type: project
---

## 审查结果: CONDITIONAL PASS

### CRITICAL (2)
1. VehicleHashDamageInfo.SendDamageInfo() 实际仅调用 PlayerManager.CollectLocalCrashData() 做本地数据采集，非网络协议。服务端无损伤接收handler。需新增 VehicleDamageReq 协议
2. VehicleDataUpdate proto 未包含损伤字段，新玩家进入 AOI 无法获取已损伤车辆状态。需在快照中加入损伤信息

### HIGH (4)
1. 服务端无物理引擎但需校验碰撞，反作弊策略未明确
2. DamagePerformanceModifier.SteerOffsetDeg 使用 Random 导致多端不一致
3. VehicleFlipNtf 应拆分为 Res（给请求者）+ Ntf（给AOI），翻正用协程非单次Impulse
4. 爆胎轮 Random.Range(0,4) 多端不一致

### 审查模式发现
- 第4次发现"设计文档声称已有xxx但实际不存在"的问题模式（此前：FieldAccessor未注册、BtTickSystem未在大世界注册等）
- 涉及"已有链路复用"的描述必须验证实际代码

**Why:** 设计基于"激活已有功能"的策略，但对已有功能的现状判断有误差，导致核心链路缺失。

**How to apply:** 后续审查中，凡设计声称"复用已有xxx"或"已有xxx调用链"，必须 grep 验证实际存在性。
