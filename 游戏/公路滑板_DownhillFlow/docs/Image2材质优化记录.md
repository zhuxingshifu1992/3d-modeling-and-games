# Image 2 服装材质优化

日期：2026-09-09。用户选择“先用内置 image2”。本轮实际使用内置 image_gen 工具，未使用 API / CLI，也未指定 Image 2.5。

## 实际接入的素材

| 材质 | 选用文件（相对工程） | 实际尺寸 | 处理 |
| --- | --- | --- | --- |
| 白色 T 恤 | source/image_optimization/generated/cotton_tee_image2_v1.png | 1254×1254 | 补充细微棉布颗粒和接缝，柔化原图部分明暗 |
| 绿色短裤 | source/image_optimization/generated/green_shorts_image2_v2.png | 1254×1254 | 增加织物细节，第二次编辑减轻腰部黑色与亮绿色色带 |

共调用三次：T 恤一次、短裤初版一次、短裤局部修订一次。提示词请求 2048 方图，但工具实际返回 1254 方图；按实际尺寸使用，没有放大后声称为原生 2K。

## 输入、提示词与构建

输入是当前游戏衣物的原始 UV 色图与从实际 Blender 网格导出的覆盖图。覆盖图作为视觉约束参考传入内置工具，并非 API 的强制遮罩；生成结果未逐像素保留所有未使用区域。实际衣物区域经过三角度引擎画面检查。

完整提示词保留在 source/image_optimization/：

- cotton_tee_prompt.txt
- green_shorts_prompt.txt
- green_shorts_refinement_prompt.txt

原始 PNG、覆盖图、三张生成原图与 jobs.json 均保留。approved_overrides.json 选择两个最终素材；tools/rider_build.py 直接加载选用颜色图，避免重复染色，重新写入可编辑 Blender 工程及游戏 GLB。原始法线、骨骼、网格和动作保持不变。导出清单记录选用文件、尺寸与 SHA-256。

## 视觉结果与限度

三角度实时检查没有发现新增胸前圆环、双领口或明显 UV 错位。短裤细节与腰部色带改善更容易看出；白衣改动较轻，远景差异有限。当前腰部轮廓和肩部褶皱仍由原几何及法线决定，图像编辑不能替代这些建模工作。

对比原图在 previews/image2/before/，本轮日志和最终实机画面在 previews/image2/。这些画面来自 Godot 实时渲染，不是经过图像模型修饰的游戏截图。
