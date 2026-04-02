---
name: REQ-004 RightArm + AdditiveBodyExtra 动画层补齐
status: completed
---

## 范围
- 修改: freelifeclient/Assets/Scripts/Gameplay/Modules/BigWorld/Entity/NPC/Comp/BigWorldNpcAnimationComp.cs
  — 读取 OnInit()/CreateLayers()，确认 AnimancerLayers.RightArm(index=1) 是否已初始化；若未初始化则补：`animancer.Layers[AnimancerLayers.RightArm].SetMask(rightArmMask); Weight=0`
  — 确认 AnimancerLayers.AdditiveBodyExtra(index=5) 是否已初始化；若未初始化则补：`animancer.Layers[AnimancerLayers.AdditiveBodyExtra].IsAdditive=true; Weight=0`
  — LoadAvatarMasks() 扩展：异步加载 RightArmAvatarMask 存入 `_rightArmMask`；加载失败时打 Warning（+ 拼接）并层降级无 Mask 运行
  — 确认 Face 层(index=8) 初始 Weight=1（始终激活）
  — 注意：枚举值在 HoldItemData.cs（AnimancerLayers 枚举）中已存在，不要重建层，只补初始化代码

## 验证标准
- 客户端无 CS 编译错误
- MCP 反射读取 `animancer.Layers[1]` Weight=0，`IsAdditive=false`（Override）
- MCP 反射读取 `animancer.Layers[5]` Weight=0，`IsAdditive=true`
- MCP 反射读取 `animancer.Layers[8]` Weight=1
- 调用 `AnimationComp.Play(key, AnimancerLayers.RightArm)` 不抛异常
- RightArmAvatarMask 加载失败时层仍存在（无 Mask 运行），不抛异常

## 依赖
- 无（AnimationComp 首次修改，独立改动）
