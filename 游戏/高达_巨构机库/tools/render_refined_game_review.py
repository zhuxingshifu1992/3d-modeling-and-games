"""CPU structural previews from real Godot-exported bay geometry.

Run only after export_refined_game_review.gd has exported the final game model.
Blender --background --factory-startup --threads 4 --python this_file.
No original game/asset files are changed. These are not game screenshots.
"""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'previews/refined_game'
parser = argparse.ArgumentParser()
parser.add_argument('--view', choices=['all', 'closed-pair', 'closed', 'open', 'cockpit'], default='all')
parser.add_argument('--machine', choices=['rx78', 'nu', 'exia', 'freedom', 'unicorn', 'wing'], default='rx78')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
if args.machine != 'rx78':
    OUT = ROOT / f'previews/refined_{args.machine}_game'
manifest_path = OUT / 'export_manifest.json'
manifest = json.loads(manifest_path.read_text(encoding='utf8'))
if manifest.get('machine_id') != args.machine:
    raise RuntimeError('Export manifest does not match the selected machine.')
report = {'purpose': 'Actual game geometry CPU structural review, not a gameplay screenshot.',
          'export_manifest_sha256': hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
          'additions': ['Neutral studio floor and lighting.', '1.75 m orange scale witness in full exterior view.'],
          'omissions': manifest['omissions'], 'views': {}}
previous_report = OUT / 'cpu_render_report.json'
if previous_report.exists():
    previous = json.loads(previous_report.read_text(encoding='utf8'))
    if previous.get('export_manifest_sha256') == report['export_manifest_sha256']:
        report['views'] = previous.get('views', {})

def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()

def area(name, xyz, target, energy, size, color):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy, data.shape, data.size, data.color = energy, 'DISK', size, color
    obj = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(obj)
    obj.location = xyz
    aim(obj, target)
    return obj

def simple_material(name, color, roughness=.65):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = color
    mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = roughness
    return mat

for view in ['closed', 'open', 'cockpit']:
    if args.view == 'closed-pair' and view == 'open':
        continue
    if args.view not in ('all', 'closed-pair', view):
        continue
    state_name = 'open' if view == 'open' else 'closed'
    source = ROOT / manifest['states'][state_name]['glb_path'].removeprefix('res://')
    assert hashlib.sha256(source.read_bytes()).hexdigest() == manifest['states'][state_name]['glb_sha256']
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 4
    scene.render.resolution_x, scene.render.resolution_y = 800, 720
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = 'AgX'
    scene.render.image_settings.file_format = 'PNG'
    scene.world = bpy.data.worlds.new('CPU_Review_Studio')
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes['Background']
    background.inputs['Color'].default_value = (.12, .16, .22, 1)
    background.inputs['Strength'].default_value = .25 if view == 'cockpit' else .5
    imported_meshes = [o for o in scene.objects if o.type == 'MESH']
    triangles = 0
    for obj in imported_meshes:
        obj.data.calc_loop_triangles()
        triangles += len(obj.data.loop_triangles)
    top_y = float(manifest['cockpit']['floor_y'])
    if view == 'cockpit':
        camera = bpy.data.objects.get('ActualSeatedCamera')
        if camera is None or camera.type != 'CAMERA':
            raise RuntimeError('Actual game seated camera was not exported.')
        scene.camera = camera
        # Source cabin light is retained. Small fill permits structural inspection
        # in a closed shell without changing or removing any game geometry.
        area('Review_Cabin_Fill', (0, .25, top_y + 1.92), (0, 1.3, top_y + .9), 14, .5, (.65, .81, 1))
        area('Review_Cabin_Front', (0, 1.30, top_y + 1.85), (0, .3, top_y + .9), 8, .4, (1, .85, .65))
    else:
        for name, loc, energy, size, color in (
            ('Studio_Key', (-7, 15, 28), 14000, 15, (1, .94, .85)),
            ('Studio_Fill', (15, 10, 16), 8000, 12, (.64, .79, 1)),
            ('Studio_Rim', (-6, -13, 23), 14000, 10, (.7, .83, 1))):
            area(name, loc, (0, 0, 10), energy, size, color)
        bpy.ops.mesh.primitive_plane_add(size=180, location=(0, 0, -.025))
        bpy.context.object.data.materials.append(simple_material('Review_Floor', (.055, .07, .1, 1)))
        data = bpy.data.cameras.new('Review_External_Camera')
        camera = bpy.data.objects.new('Review_External_Camera', data)
        scene.collection.objects.link(camera)
        scene.camera = camera
        if view == 'closed':
            camera.location = (-28, 45, 25)
            camera.data.type = 'ORTHO'
            exterior_frames = {
                'rx78': (25.5, 9.5), 'nu': (40.0, 13.0), 'exia': (25.5, 9.5),
                'freedom': (32.0, 9.5), 'unicorn': (30.0, 10.8), 'wing': (28.0, 10.0),
            }
            camera.data.ortho_scale, aim_height = exterior_frames[args.machine]
            aim(camera, (0, 2.0, aim_height))
            human_mat = simple_material('ScaleWitness_1_75m', (.95, .45, .05, 1))
            for loc, size in [((-4.4, 5, .5), (.18, .12, .5)), ((-4.4, 5, 1.23), (.25, .14, .28))]:
                bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, location=loc)
                bpy.context.object.scale = size
                bpy.context.object.data.materials.append(human_mat)
            bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=.14, location=(-4.4, 5, 1.61))
            bpy.context.object.data.materials.append(human_mat)
        else:
            camera.location = (-4.6, 9.7, top_y + 3.1)
            camera.data.lens = 42
            aim(camera, (0, 1.6, top_y + 1.0))
            area('Review_Open_Cabin_Fill', (0, 3.2, top_y + 1.7), (0, .3, top_y + 1), 60, 1.2, (.65, .81, 1))
    scene.render.filepath = str(OUT / f'{args.machine}_{view}_cpu.png')
    bpy.ops.render.render(write_still=True)
    report['views'][view] = {
        'source_glb': source.name, 'game_meshes': len(imported_meshes), 'game_triangles': triangles,
        'source_glb_sha256': manifest['states'][state_name]['glb_sha256'],
        'camera_blender_xyz': list(camera.location), 'image': scene.render.filepath,
        'camera_basis': 'Actual game seated camera' if view == 'cockpit' else 'External structural review camera',
    }
    print('ACTUAL_GAME_CPU_REVIEW_RENDERED', view, scene.render.filepath, flush=True)
(OUT / 'cpu_render_report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
