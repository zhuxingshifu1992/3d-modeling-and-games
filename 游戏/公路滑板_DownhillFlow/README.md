# 公路滑板 · 逐风

沿海公路下坡滑板游戏，包含蹬地、低伏、刹车、漂移、连续坡道与跟随镜头。

## 运行

使用 Godot 4.7.2 导入 `project.godot`，首次等待资源导入，然后按 F5。Windows 可双击 `启动游戏.cmd`；启动前需要安装 Godot 并设置 PATH 或 `GODOT_BIN`。

W 蹬地，A/D 转向，S 刹车，空格漂移，Shift 低伏，C 切换镜头。

## 项目文件

- `project.godot`、`main.tscn`：引擎入口。
- `scripts/`：游戏逻辑。
- `assets/`：游戏所需模型、贴图、声音与数据。
- `tests/`：现有的行为与场景检查脚本。

角色与服装基于 Microsoft Rocketbox，配有编辑源文件、选用的原始 FBX、贴图和骨骼姿势。环境采用 Poly Haven 摄影 PBR 资源。

可编辑模型：[打开源文件](source/rider/rider_realistic.blend)。

## 预览

![公路滑板 · 逐风](previews/自然动作版实机.png)

## 来源与发布

[第三方资源与许可](../../THIRD_PARTY.md) · [公开版处理](../../PUBLICATION.md) · [验证记录](../../VALIDATION.md) · [返回作品集](../../README.md)
