"""CPU-only inspection render of the downloaded RX-78; no source-file changes."""
import bpy
import argparse
import sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=ROOT / 'source/external/rx78_blendkit/Gundam_RX-78-2_AnonmalyFound.blend')
parser.add_argument('--output-dir', type=Path, default=ROOT / 'previews/external_rx78')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
OUT = args.output_dir
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(args.source), use_scripts=False)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 24
scene.cycles.use_denoising = True
scene.render.resolution_x = 960
scene.render.resolution_y = 1080
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.film_transparent = False
scene.use_nodes = False
scene.world = bpy.data.worlds.new('Inspection_Studio')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (.16, .2, .28, 1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = .4
scene.view_settings.view_transform = 'AgX'

def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()

def area(name, loc, energy, size, color):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy, data.shape, data.size, data.color = energy, 'DISK', size, color
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = loc
    aim(obj, (0, 0, 10))

area('Studio_Key', (5, -15, 28), 13000, 15, (1, .94, .85))
area('Studio_Fill', (-14, -8, 17), 6500, 12, (.64, .79, 1))
area('Studio_Rim', (5, 12, 24), 15000, 10, (.7, .83, 1))
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.2))
floor = bpy.context.object
mat = bpy.data.materials.new('Inspection_Floor')
mat.diffuse_color = (.075, .09, .12, 1)
mat.use_nodes = True
mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (.075, .09, .12, 1)
mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = .72
floor.data.materials.append(mat)
cam_data = bpy.data.cameras.new('Inspection_Camera')
cam = bpy.data.objects.new('Inspection_Camera', cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
cam.location = (25, -48, 24)
cam.data.type = 'ORTHO'
cam.data.ortho_scale = 25
aim(cam, (-.5, 0, 9.5))
scene.render.filepath = str(OUT / 'original_model.png')
bpy.ops.render.render(write_still=True)
print('ASSET_PREVIEW_COMPLETE', scene.render.filepath)
