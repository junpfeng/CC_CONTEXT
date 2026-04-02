---
name: REQ-008 击中反应动画
status: completed
---

## 范围
- 修改: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcAnimationComp.cs
  — 新增字段：`private bool _isInHitReaction; private float _hitReactionTimer; private bool _isDead`
  — 新增接口：`public void OnHit(HitData hitData)` — 检查 `_isDead`（死亡则直接返回）；设 `_isInHitReaction=true`；UpperBody 层(index=2) CrossFade 播放击中 Clip；`_hitReactionTimer=1f`
  — Update() 中追加：`if (_isInHitReaction) { _hitReactionTimer -= Time.deltaTime; if (_hitReactionTimer <= 0) { _isInHitReaction=false; RestoreUpperBodyAnim(); } }`
  — 新增私有方法 `RestoreUpperBodyAnim()`：`animancer.Layers[AnimancerLayers.UpperBody].StartFade(0, 0.2f)`（Weight 淡出归零，与 TownNpcAnimationComp 一致）
  — NpcState=Death 时设 `_isDead=true`
  — ResetForPool() 中补充：`_isDead=false; _isInHitReaction=false; _hitReactionTimer=0f`（_faceClips 和 _replaceTimelines 资源缓存保留，不重新加载）
  — 击中动画资源缺失时静默跳过，不影响其他层

## 验证标准
- 客户端无 CS 编译错误
- MCP 脚本调用 `OnHit(HitData)`，截图确认 UpperBody 层播放击中动画
- 约 1s 后确认 UpperBody 层恢复（MCP 反射 _isInHitReaction = false）
- 死亡状态（NpcState.Death）下调用 OnHit，确认不触发击中动画
- 击中动画资源缺失时静默跳过，其他层动画不受影响
- 对象池复用后 _isDead / _isInHitReaction 均为初始值（MCP 反射验证）

## 依赖
- 依赖 task-07（AnimationComp 在 task-07 已追加战斗状态接口，task-08 继续追加 OnHit 逻辑）
