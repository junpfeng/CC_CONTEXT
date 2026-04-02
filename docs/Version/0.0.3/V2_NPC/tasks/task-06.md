---
name: REQ-006 Timeline 动画支持
status: completed
---

## 范围
- 修改: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcAnimationComp.cs
  — 新增字段：`private Dictionary<ConfigEnum.TransitionKey, TimelineAsset> _replaceTimelines`
  — ChangeAnimationsByGroup() 中同步加载该动画组的 Timeline 替换表，填充 `_replaceTimelines`；加载失败时字段为空/不填，不抛异常
  — 新增接口：`public void PlayTimeline(ConfigEnum.TransitionKey key)` — 查 `_replaceTimelines`，存在则获取或初始化 PlayableDirector 并触发播放；不存在则降级调用 `Play(key)`
  — 新增接口：`public void StopTimeline()` — 停止 PlayableDirector，恢复 Animancer 控制（参考 TownNpcAnimationComp 的 StopTimeline 实现）
  — OnClear()/ResetForPool() 中停止并清理 PlayableDirector 引用

## 验证标准
- 客户端无 CS 编译错误
- MCP 反射确认 `_replaceTimelines` 字段存在
- 调用 `PlayTimeline(existingKey)` 触发 Timeline 播放（MCP 截图确认）
- 调用 `StopTimeline()` 停止后 Animancer 恢复控制
- `PlayTimeline(nonExistingKey)` 降级到 Transition 播放，不抛异常

## 依赖
- 依赖 task-05（AnimationComp 同文件，task-05 已完成层扩展和面部动画，task-06 继续追加 Timeline 逻辑）
