# 环境真实材质与建模来源

本轮环境将纯色 / 程序噪声表面更换为摄影 PBR 材质；树木以逐段收细、弯曲的树干与分叉支撑摄影叶片簇，灌木和野草使用真实叶片 / 草叶的透明遮罩。岩石为连续的多尺度侵蚀曲面，地形为路线驱动、无折返的坡面与台阶。天空全景由主环境加载，旧平面云已移除。

## 素材与授权

Powered by Poly Haven. 所有下载素材均来自 [Poly Haven 官方资源](https://polyhaven.com/)，按其 [CC0 授权](https://polyhaven.com/license) 使用，可随项目再分发。逐文件原始 URL、作者、原始 MD5、下载 SHA-256、像素规格、物理尺寸记录在 `assets/environment/provenance.json`。下载日期为 2026-09-09。

| 资源 | 用途 | 保留规格 |
|---|---|---|
| [Asphalt 02](https://polyhaven.com/a/asphalt_02) | 3 米实测沥青纹理、法线与 AO / Roughness / Metallic | 2K |
| [Rock Face](https://polyhaven.com/a/rock_face) | 岩壁、岩块与路肩的摄影裂隙、矿物颗粒、法线及粗糙度 | 2K |
| [Aerial Grass Rock](https://polyhaven.com/a/aerial_grass_rock) | 15 米摄影地表覆盖，绿色岩坡 / 草地的主要颜色与法线 | 2K |
| [Leafy Grass](https://polyhaven.com/a/leafy_grass) | 同组地面摄影源资料，当前已由 Aerial Grass Rock 替换 | 1K |
| [Bark Willow](https://polyhaven.com/a/bark_willow) | 树干与细分叉的树皮颜色和法线 | 1K |
| [Tree Small 02](https://polyhaven.com/a/tree_small_02) | 叶片摄影图集和单独透明遮罩，裁取原图的枝叶区域用于几何卡片 | 1K |
| [Grass Medium 01](https://polyhaven.com/a/grass_medium_01) | 野草摄影图集与透明遮罩 | 1K |
| [Kloofendal 48d Partly Cloudy — Pure Sky](https://polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky) | 推荐的摄影天空与云层，无周围地形干扰，由主场景加载 | 2K HDR |
| [Chapmans Drive](https://polyhaven.com/a/chapmans_drive) | 初版沿海道路摄影 HDR 全景，保留来源资料，不再推荐作为背景 | 2K HDR |

原始摄影文件未修改。叶 / 草透明遮罩在材质中直接读取，未用生成图替代摄影纹理。已下载的岩石高度、地面 ARM、叶片法线保留作为同一组来源资料，目前运行材质仅使用明确接入的通道。摄影材质的来源制作标准见 [Poly Haven Texture Requirements](https://docs.polyhaven.com/en/technical-standards/textures)。

## 实现边界与性能

- `Route.sample()`、`ROAD_HALF = 4.8`、`CHUNK = 160`、`world.update_view(s)` 均保留；道路的可见边界与仿真共用同一路线。
- 道路使用 3 米纹理实尺，地形以世界坐标三向投影，减少陡坡纹理拉伸。所有照片色图使用 `source_color`，数据贴图不做伽马转换，兼容 Forward+ 与 Compatibility。
- 共享岩石、枝干、叶片、灌木、草丛原型；每个 160 米区块五个环境 MultiMesh 批次。路肩草关闭投影阴影并设置 380 米显示范围，灌木为 820 米；树木和岩石随已有分块范围隐藏。
- 近景岩块采用 28 × 18 曲面网格、多频率风化扰动和连续法线，放置时按旋转缩放后的横向包围半径避开公路。地形近公路处增加采样以形成连续侵蚀凹凸，降低原版巨型平滑壁面的高度。
- 树木含 10 面基干、7 / 6 面主枝和 5 面细枝，叶簇保留空隙和透明轮廓。模型不是扫描树干，树干结构为本项目程序建模；叶片、树皮和地表细节来自摄影素材。
- 天空源文件为 `res://assets/environment/kloofendal_48d_partly_cloudy_puresky_2k.hdr`，主场景负责曝光、旋转、雾与太阳。水面改为接受天空反射和太阳高光的粗糙度 / 法线材质。

## 复现和验证

`python tools/fetch_environment_assets.py` 只下载清单中列出的免费素材，已有文件校验 MD5，不覆盖用户修改的文件。下载器使用明确的 User-Agent，最多三个并行文件请求。

Godot 导入后运行 `--headless --script res://tests/world_probe.gd`，验证路线连续性、坡面无折返、岩石法线 / 接缝、岩石与可行驶道路间距、摄影纹理是否实际加载、分块接口及全路线三角面预算。最终光照和 GPU 帧率需在主场景实机验证；无界面测试不代表最终画面和帧率通过。

已通过的本轮无界面结果：`WORLD_PROBE_OK samples=2601 nodes=32 triangles=1169098 min_rock_clearance=1.511m`。23 个官方源文件完整性校验通过；运行贴图开启 mipmaps 和 GPU 压缩，减少远景闪烁及显存占用。

实机复核后的调整：岩石照片做去暖色的灰褐矿物调色，坡面绿色覆盖增加，山体高度降低；沿岸树木增加至 342 株、靠近路肩并放大，远岸地形轮廓改为 40 × 110 平滑网格。海面波长加大、远距离细波提前淡出，减少细条纹。天空显像与环境反射仍由主场景负责。

纯天空文件：`assets/environment/kloofendal_48d_partly_cloudy_puresky_2k.hdr`，5,451,493 字节，官方 MD5 `2eba3a4d7eeb23cbfbeca364c97e7980`，SHA-256 `5244534e9cf5b606f2ff513aa00ddb161b0a4826ffd88a0d3bd03ac29247d198`。Greg Zaal 原始摄影，Jarod Guest 制作纯天空版本。文件完整性已按官方 API 记录验证。

第二次实机复核：修正远岸遗留的朝下三角形绕序，使用解析坡面法线与连续世界高度 / 噪声 / 摄影底色着色器，移除顶点条带色。海面改用两组旋转平移的非周期噪声梯度，完全移除周期正弦波列。植被照片按绿色通道的植被遮罩校正黄绿色，灰色石粒保留；全路线三角面数不增加。
