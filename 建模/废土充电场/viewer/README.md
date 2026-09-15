# 废土充电场本地三维查看器

在项目目录运行：

```powershell
python .\source\serve_viewer.py
```

浏览器会打开 http://127.0.0.1:8766/viewer/。保持终端运行，关闭时按 `Ctrl+C`。
如果不需要自动打开浏览器，运行 `python .\source\serve_viewer.py --no-browser`。

模型来自 `exports/废土充电场.glb`。总览会依据实际几何范围自动取景；其余按钮分别查看入口、充电区和工程车。鼠标拖动旋转，右键拖动平移，滚轮缩放；触屏可单指旋转、双指平移与缩放。

页面、模型和 JavaScript 均从本机读取，运行时没有外部网络依赖。请通过上述本地服务打开，直接双击 HTML 会受到浏览器模块加载限制。服务固定绑定 `127.0.0.1:8766`，不会向局域网开放。

`vendor/three-r170/` 保存 Three.js **0.170.0 / r170** 的官方原始文件与 MIT 许可证。`UPSTREAM.json` 记录固定版本下载地址、文件大小和 SHA-256。r170 的 `three.module.js` 为独立完整模块，不需要额外的 `three.core.js`。其他依赖为 `OrbitControls.js`、`GLTFLoader.js`、`BufferGeometryUtils.js`，均来自同一官方版本，未修改供应商文件。

查看器最高使用 1.5 倍设备像素比，采用单盏太阳光阴影及离线生成的环境光，无后期特效。模型静止时停止重复绘制。建议使用支持 WebGL 2 的近期桌面浏览器。
