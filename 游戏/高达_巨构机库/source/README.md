# 模型源文件

| 文件 | 内容 |
| --- | --- |
| [机体模型.blend](机体模型.blend) | 六台风格化程序机械模型；公开版 B2 使用其中的飞翼 |
| [RX78_game_asset.blend](external/rx78_blendkit/derived/RX78_game_asset.blend) | RX-78-2 游戏派生模型，含活动胸盖与打包贴图 |
| [Zaku_Desert_GameReady.blend](external/zaku_desert_blendkit/derived/Zaku_Desert_GameReady.blend) | 沙漠扎古游戏派生模型和打包贴图 |
| [build_models.py](build_models.py) | 六台程序模型的 Blender 生成脚本 |
| [build_audio.py](build_audio.py) | 程序音效生成脚本 |

制作与验证使用 Blender 5.2.1。其他机体的最终模型保存在 [assets/models](../assets/models)，可通过 Blender 的 glTF 2.0 导入器编辑。独角兽 GLB 引用同目录外置图片，移动时必须一起携带。

`tools/convert_*_asset.py`、`unicorn_materials.py` 等保留实际制作方法，重新运行需要从 [素材来源](../assets/机体素材来源.txt) 取得上游原件，并放入脚本 `SOURCE` 常量或输入参数要求的位置；本仓库不镜像重复下载原包。转换报告记录制作时的文件哈希，公开版清理或拆图后哈希可能变化。

生成程序模型可在项目副本中运行：

```powershell
blender --background --factory-startup --disable-autoexec --python source/build_models.py
python source/build_audio.py
```

该生成脚本会重建六台程序模型与预览，请在单独副本中使用。模型作者、第三方许可与游戏适配改动详见素材来源文件。
