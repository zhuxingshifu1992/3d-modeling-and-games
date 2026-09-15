# 废土充电场 · 公开版

工业院落、集装箱办公室、充电设备、车辆、围界和生活设施组成的废土风格场景。

## 打开与编辑

使用 Blender 5.2.1 打开 [废土充电场.blend](废土充电场.blend)。模型贴图已打包；编辑前可另存一个工作版本。

原始参考照片、内嵌照片、照片 UV 面板与识别性标签已处理。当前面板使用普通材质，标记使用通用文字，字体使用随附的 Noto Sans SC。

## 预览

![废土充电场 · 公开版](renders/public-preview.png)

## 重新生成

在本项目目录运行：

```console
blender --background --python source/build_scene.py
```

重建会更新本目录下的生成文件。

导出 GLB：`blender --background --python source/export_scene.py`。本地浏览器查看：`python source/serve_viewer.py`，访问 `http://127.0.0.1:8766/viewer/`。

[第三方资源与许可](../../THIRD_PARTY.md) · [公开版处理](../../PUBLICATION.md) · [返回建模索引](../README.md)
