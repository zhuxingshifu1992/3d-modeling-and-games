"""Create a solid-viewport presentation copy; preserve the acquired source."""
from pathlib import Path
import bpy
from mathutils import Vector

root = Path(__file__).resolve().parents[1]
source = root / 'source/external/rx78_blendkit/Gundam_RX-78-2_AnonmalyFound.blend'
target = root / 'previews/external_rx78/RX78_观摩.blend'
bpy.ops.wm.open_mainfile(filepath=str(source), use_scripts=False)
# Viewport display colors only; authored shader node graphs remain unchanged.
palette = {'Blue': (.035, .10, .43, 1), 'Red': (.47, .025, .035, 1),
           'Yellow': (.83, .56, .09, 1), 'Green': (.07, .42, .22, 1),
           'White': (.77, .8, .83, 1), 'Black': (.025, .033, .045, 1),
           'Gray': (.16, .19, .22, 1), 'Silver': (.43, .48, .53, 1),
           'Copper': (.42, .19, .085, 1)}
for mat in bpy.data.materials:
    for prefix, color in palette.items():
        if mat.name.startswith(prefix):
            mat.diffuse_color = color
            break
for obj in bpy.context.scene.objects:
    obj.select_set(False)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == 'CONSOLE':
            area.type = 'VIEW_3D'
        if area.type != 'VIEW_3D':
            continue
        space = area.spaces.active
        space.shading.type = 'SOLID'
        space.shading.color_type = 'MATERIAL'
        space.shading.light = 'STUDIO'
        space.shading.show_shadows = True
        space.shading.show_cavity = True
        space.shading.cavity_type = 'BOTH'
        space.shading.background_type = 'VIEWPORT'
        space.shading.background_color = (.035, .045, .065)
        space.overlay.show_overlays = False
        space.clip_end = 1000
        space.region_3d.view_location = (0, 0, 9.5)
        space.region_3d.view_distance = 33
        space.region_3d.view_rotation = Vector((20, -48, 13)).to_track_quat('Z', 'Y')
        space.region_3d.view_perspective = 'ORTHO'
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(target), check_existing=False)
print('DEMO_COPY_READY', target)
