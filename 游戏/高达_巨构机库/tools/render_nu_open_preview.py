"""Inspect the actual exported Nu hatch, CPU-only; does not edit game assets."""
from pathlib import Path
import math
import bpy
from mathutils import Vector
root=Path(__file__).resolve().parents[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(root/'assets/models/nu_refined.glb'))
scene=bpy.context.scene
hatch=bpy.data.objects['CockpitHatch']
hatch.location.y+=.15
hatch.rotation_mode='XYZ'
hatch.rotation_euler.x=math.radians(120)
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=16;scene.render.threads_mode='FIXED';scene.render.threads=4
scene.world=bpy.data.worlds.new('Studio world');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.22,.26,.33,1);scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.45
target=Vector((0,1.3,17.3))
bpy.ops.object.camera_add(location=(8,19,19.8));camera=bpy.context.object;camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=8;scene.camera=camera
for loc,energy,size in [((5,18,35),18000,18),((-19,8,22),16000,16),((0,-15,30),24000,12)]:
    bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=energy;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(target-o.location).to_track_quat('-Z','Y').to_euler()
scene.render.resolution_x=1100;scene.render.resolution_y=1280;scene.render.resolution_percentage=100;scene.view_settings.view_transform='AgX';scene.render.image_settings.file_format='PNG'
scene.render.filepath=str(root/'previews/refined_nu/nu_open_hatch_cpu.png')
bpy.ops.render.render(write_still=True)
print('NU_OPEN_PREVIEW_COMPLETE',flush=True)
