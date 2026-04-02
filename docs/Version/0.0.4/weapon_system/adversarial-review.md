# 方案红蓝对抗报告

## 轮次记录

### Round 1
- 红队发现: 12 条（2C/7H/3L）
- 蓝队修复:
  - [CRITICAL] DrawWeaponReq 无服务端状态校验 → 新增死亡/上车/被控状态校验
  - [CRITICAL] 射速无上限 → 新增 RPM 射速校验
  - [HIGH] InHandIndex 越界 → 操作前做边界检查
  - [HIGH] 辅助瞄准无目标回退 → 明确回退自由视角
  - [HIGH] DrawWeaponReq 字段未定义 → Req 携带 weapon_id，Res 含 result_code
  - [HIGH] 掏枪/收枪重入 → _isTransitioning 状态锁
  - [HIGH] 客户端伪造 HitData → CheckManager 增加视线遮挡校验
  - [HIGH] 载具扣血未定义 → 已在待细化，保持
  - [HIGH] WeaponBagNtf 无增量同步 → 本期仅登录同步，降级 LOW
  - [LOW] 3 条移入待细化

### Round 2
- 红队发现: 6 条（2H/3M/1L）
- 蓝队修复:
  - [HIGH] RPM 拒绝无反馈 → 改为返回 rate_limit 错误码
  - [HIGH] 服务端无法做物理 Raycast → 降级为方向角度校验
  - [MEDIUM] 3 条移入待细化（掏枪回滚竞态/状态锁超时/瞄准回退过渡）
  - [LOW] scene_server 消息串行 → 驳回（Go 实体消息确实是单线程串行）

### Round 3
- 红队发现: 0 条
- 结论: 修复质量通过

## 最终状态
- 总发现: 18 条
- 已修复: 9 条（idea.md 锁定决策已更新）
- 待细化: 6 条（移入 ### 待细化）
- 驳回: 2 条（WeaponBagNtf 降级、scene_server 串行非问题）
- 已有覆盖: 1 条（载具扣血已在待细化）
