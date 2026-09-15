# 角色模型与贴图来源

本项目使用 [Microsoft Rocketbox Avatar Library](https://github.com/microsoft/Microsoft-Rocketbox) 的原始人物网格、骨骼和贴图，经裁剪、服装配色、配件建模和滑板姿势制作后导出为 `assets/rider_realistic/rider.glb`。

采用的仓库提交为 `0943055db6ec570bcef9f2c8b41c9e5467c808f9`，本地上游仓库为 `source/rider/rocketbox_upstream`。此处记录实际使用的资产，不将原参考影片中的人物视为本模型的来源或授权方。

## 原始资产

以下路径均相对于官方仓库的 `Assets/Avatars`；本项目保留的制作原件位于 `source/rider/originals` 对应子目录。

| 资产 | 原始模型 | 本项目用途 |
| --- | --- | --- |
| Sports Female 01 | `Professions/Sports_Female_01/Export/Sports_Female_01.fbx` | 人体网格、主骨骼、皮肤与面部贴图 |
| Female Adult 17 | `Adults/Female_Adult_17/Export/Female_Adult_17.fbx` | T 恤网格与服装纹理，经裁剪和重新配色 |
| Female Adult 12 | `Adults/Female_Adult_12/Export/Female_Adult_12.fbx` | 短裤、鞋子的原始拓扑与纹理，经裁剪和重新配色 |

原始贴图在各人物的 `Textures` 子目录，使用了 `f021`、`f006`、`f012` 的 body / head color 与 normal 资源。制作中保留 TGA 原件，并生成 PNG 供 Blender 和游戏使用。资产网格及贴图来自已建模的角色库；不声称它们是本项目的人体扫描或实拍演员。

## 修改与输出

- 人体和衣物保留原人物网格与绑定，按滑板服装裁剪，并进行表面细分。
- T 恤、短裤和鞋子调整颜色。2026-09-09 再用内置 Image 2 编辑 T 恤与短裤颜色图，选用 1254×1254 输出，保留原法线；短裤经过一次腰部色带修订。具体输入、提示词与选用记录见 Image2材质优化记录.md。
- 红帽、帽缝、马尾和袜子由本项目脚本添加。
- Ride、Tuck、Brake、Push 由本项目制作骨骼姿势，游戏执行姿势切换；这些姿势不是上游动作库的动捕片段。
- 人物动作修订采用连续的父级旋转、分段脊柱和肩带朝向、弯曲手臂及放松手指。游戏另用脚部接触反解、重心调整和输入触发的连续蹬地循环，见 动作优化记录.md。
- 可编辑源文件为 `source/rider/rider_realistic.blend`，构建脚本为 `tools/rider_build.py`。实际导出的网格和动作清单见 `assets/rider_realistic/manifest.json`，需结合实机画面检查变形与接触。

## 许可随包保留

官方仓库在此提交采用 [MIT License](https://github.com/microsoft/Microsoft-Rocketbox/blob/0943055db6ec570bcef9f2c8b41c9e5467c808f9/LICENSE.md)，版权所有声明为 `Copyright (c) 2020 Microsoft`。完整许可原文保留在 `assets/rider_realistic/LICENSE_MICROSOFT_ROCKETBOX.md`，与上游 LICENSE.md 的 SHA-256 一致：

`a388bf32e3c2f6b02c30228c0896893c82aa678a00b96614a848e358c6da3a12`

Windows 独立包将完整许可和导出清单复制到 `第三方许可/assets/rider_realistic/`，并将本文复制至游戏目录。原 FBX、TGA、Blender 工程和下载仓库位于制作工程的 `source`，不进入运行时 PCK。
