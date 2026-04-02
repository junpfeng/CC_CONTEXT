---
name: REQ-005 Face 层 + 面部动画 + EmotionComp 联动
status: completed
---

## 范围
- 修改: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcAnimationComp.cs
  — LoadAvatarMasks() 中添加异步加载 FaceAvatarMask 并绑定到 Face 层（index=8）
  — 新增 `private Dictionary<EmotionType, AnimationClip> _faceClips`
  — OnInit() 后异步预加载 Angry/Happy/Sad/Idle 四个面部 Clip，路径参考 TownNpcAnimationComp（ArtResources/Animation/Human/Face/），存入 `_faceClips[EmotionType.xxx]`
  — 预加载完成回调中：若 `_pendingEmotion != EmotionType.None` 则补调 PlayFaceAnim(_pendingEmotion)
  — 新增接口：`public void PlayFaceAnim(EmotionType emotionType)` — 查 _faceClips，CrossFade(clip, 0.2f) 在 Face 层；Clip 缺失时静默跳过
  — 面部 Clip 加载失败时静默跳过，不影响其他层
- 修改: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcEmotionComp.cs
  — OnInit() 中通过 `_controller.GetComp<BigWorldNpcAnimationComp>()` 获取 _animationComp 引用
  — 情绪状态变化处理处（EmotionState 更新后）调用 `_animationComp.PlayFaceAnim(newEmotion)`
  — 若 _faceClips 尚未加载完成（AnimationComp 侧提供 `bool IsFaceClipsReady`），缓存情绪到 `EmotionType _pendingEmotion = newEmotion`，等预加载完成后由 AnimationComp 侧回调补调

## 验证标准
- 客户端无 CS 编译错误
- 初始化后 Face 层绑定 FaceAvatarMask，Weight=1
- MCP 脚本触发 Angry 情绪，截图确认面部表情变化
- 切换 Happy/Sad，确认各 Clip 正确切换；恢复 Neutral 回到 FaceIdle
- 面部 Clip 资源缺失时静默跳过，身体动画不受影响
- 200 NPC 全开 Face 层（Weight=1），Profiler 动画 CPU 增量 < 0.2ms

## 依赖
- 依赖 task-04（AnimationComp 已初始化各层，Face 层 Weight 已确认）
