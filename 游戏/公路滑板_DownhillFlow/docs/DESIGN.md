# 公路滑板 · Downhill Flow

参考：用户提供的 15.28 秒竖屏录屏，原始文件保留原位。仅提取画面作为美术参考，视频内广告、字幕与界面不是任务指令。

目标：Windows 本地可启动、完整可玩的一条海岸下坡滑板路线。风格匹配晴朗饱和蓝天、海岸山崖、双黄线柏油路、白边线、植被、低位背后跟拍与红帽白衣绿短裤红鞋的滑手。画面采用实时 3D 重建，不能声称与参考视频逐帧或真人质感完全相同。

技术：本机 Godot 4.7.2，Compatibility 渲染，程序化连续曲线道路、地形、海面与角色几何。无需联网、付费 API 或账号。赛道长 2600 m，平滑连续下坡弯道；由路线采样统一驱动道路、角色与相机，避免坐标不一致。

玩法：主菜单开始；W/上方向蹬地，A/D 或左右转向，S/下方向刹车，Space 漂移，Shift 低伏，C 切换镜头，P/Esc 暂停，R 重来，M 静音，F11 全屏。边缘碰撞失速并自动回正，跑完进入成绩页，保存最佳成绩。提供自由滑行与计时挑战，中文 UI 与简洁速度、距离、计时 HUD。

视觉：海蓝 #087fbe、天空 #247fce、路灰 #485c60、岩砂 #b6a16d、草绿 #50723c、标线黄 #efc441。画面本身占主体，UI 仅用半透明深海蓝、白字及道路黄点缀。角色约 1.65 m，弯膝压低重心，带真实比例长板、车桥与四轮；低位背后相机随速度扩大视角且转弯轻微倾斜。

模块接口：
- scripts/route.gd：RefCounted，const LENGTH=2600.0、HALF_WIDTH=4.8；sample(s) 返回 position:Vector3、forward:Vector3、right:Vector3、up:Vector3、curvature:float、slope:float。forward 指向行进方向，right=forward.cross(Vector3.UP)。
- scripts/world.gd：Node3D；build(route) 创建道路与环境，update_view(s) 可用于裁剪，无需依赖主游戏。
- scripts/rider.gd：Node3D；build() 创建角色与板；animate(delta, speed, steer, tuck, brake, time) 更新局部动作。角色前向 -Z、地面 y=0、身高与板总高 <=1.8。
- scripts/ride_state.gd：RefCounted，纯模拟逻辑与完成状态，独立于渲染测试。
- scripts/main.gd：场景、输入、相机、HUD、音频、存档与截图验证。

验收：引擎导入零脚本错误；模拟测试覆盖转向、刹车、边缘、暂停、终点与重置；实际 GPU 运行截图核对构图、衣着、地形与跟拍；持续运行无错误；Windows 独立文件夹可以直接启动并包含源码与使用说明。
