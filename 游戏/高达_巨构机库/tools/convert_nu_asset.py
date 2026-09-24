"""Prepare the acquired Nu Gundam without changing the original GLB.

Stage one runs in ordinary Python with Pillow and resizes embedded PBR maps
before Blender ever decodes them. Stage two uses background Blender, CPU only.
"""
from pathlib import Path
import argparse
import hashlib
import io
import json
import math
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'source/external/nu_sketchfab/RX93_Nu_TrashCG_4k_original.glb'
DERIVED = SOURCE.parent / 'derived'
PREVIEW = ROOT / 'previews/refined_nu'
REDUCED = DERIVED / 'nu_source_textures_2k.glb'
TARGET = ROOT / 'assets/models/nu_refined.glb'
SOURCE_HASH = '5ee12a3303a09170c0564fab15d4d258b5ede269aa186efcb4bae8b6d277b42f'
parser = argparse.ArgumentParser()
parser.add_argument('--prepare-textures', action='store_true')
parser.add_argument('--inspect', action='store_true')
parser.add_argument('--render', action='store_true')
parser.add_argument('--rest', action='store_true')
parser.add_argument('--native-pose', action='store_true')
parser.add_argument('--isolate-body', action='store_true')
parser.add_argument('--chest', action='store_true')
script_argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [] if '--python' in sys.argv else sys.argv[1:]
args = parser.parse_args(script_argv)
DERIVED.mkdir(parents=True, exist_ok=True)
PREVIEW.mkdir(parents=True, exist_ok=True)


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


if args.prepare_textures:
    from PIL import Image
    assert sha256(SOURCE) == SOURCE_HASH
    raw = SOURCE.read_bytes()
    length, kind = struct.unpack_from('<II', raw, 12)
    document = json.loads(raw[20:20 + length])
    binary = memoryview(raw)[28 + length:]
    image_views = {image['bufferView']: index for index, image in enumerate(document['images'])}
    roles = {}
    for material in document['materials']:
        pbr = material.get('pbrMetallicRoughness', {})
        for role, spec in [('basecolor', pbr.get('baseColorTexture')), ('metal_rough', pbr.get('metallicRoughnessTexture')), ('normal', material.get('normalTexture')), ('occlusion', material.get('occlusionTexture')), ('emission', material.get('emissiveTexture'))]:
            if spec:
                index = document['textures'][spec['index']]['source']
                roles.setdefault(index, set()).add(role)
    output = bytearray()
    image_report = []
    for view_index, view in enumerate(document['bufferViews']):
        data = bytes(binary[view.get('byteOffset', 0):view.get('byteOffset', 0) + view['byteLength']])
        if view_index in image_views:
            image_index = image_views[view_index]
            role = roles.get(image_index, set())
            resolution = 2048 if role.intersection(('basecolor', 'normal', 'emission')) else 1024
            with Image.open(io.BytesIO(data)) as original:
                old_size = list(original.size)
                resized = original.resize((resolution, resolution), Image.Resampling.LANCZOS)
                encoded = io.BytesIO()
                resized.save(encoded, format='PNG', compress_level=5)
                data = encoded.getvalue()
                resized.close()
            document['images'][image_index]['mimeType'] = 'image/png'
            image_report.append({'image_index': image_index, 'roles': sorted(role), 'source_size': old_size, 'derived_size': [resolution, resolution], 'bytes': len(data)})
            print('RESIZED', image_index, sorted(role), resolution, flush=True)
        while len(output) % 4:
            output.append(0)
        view['byteOffset'] = len(output)
        view['byteLength'] = len(data)
        output.extend(data)
    while len(output) % 4:
        output.append(0)
    document['buffers'][0]['byteLength'] = len(output)
    encoded_json = json.dumps(document, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    encoded_json += b' ' * ((-len(encoded_json)) % 4)
    with REDUCED.open('wb') as stream:
        stream.write(struct.pack('<III', 0x46546C67, 2, 28 + len(encoded_json) + len(output)))
        stream.write(struct.pack('<II', len(encoded_json), 0x4E4F534A))
        stream.write(encoded_json)
        stream.write(struct.pack('<II', len(output), 0x004E4942))
        stream.write(output)
    (DERIVED / 'texture_conversion.json').write_text(json.dumps({'source_sha256': SOURCE_HASH, 'derived_sha256': sha256(REDUCED), 'source_bytes': SOURCE.stat().st_size, 'derived_bytes': REDUCED.stat().st_size, 'images': image_report, 'method': 'Sequential Lanczos reduction of authored embedded PBR maps; no material rebake.'}, indent=2), encoding='utf-8')
    print('TEXTURES_COMPLETE', REDUCED.stat().st_size, flush=True)
    sys.exit(0)

# Source inspection found a malformed fin-funnel mesh. Do not silently hide or
# resize that one component: doing so would invent the artist's intended setup.
# An original-format FBX or another independently valid source is needed before
# completing the game export. Fail before decoding textures in ordinary mode.
if not args.inspect:
    raise RuntimeError('CONVERSION_BLOCKED: Nu source fin-funnel mesh has unverified extreme coordinates. Inspect the original-format asset before changing geometry.')

import bpy
import numpy as np
from mathutils import Matrix, Vector

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(REDUCED))
if args.native_pose:
    source_bytes = REDUCED.read_bytes()
    json_length = struct.unpack_from('<I', source_bytes, 12)[0]
    gltf = json.loads(source_bytes[20:20 + json_length])
    source_binary = memoryview(source_bytes)[28 + json_length:]
    def accessor(index):
        a = gltf['accessors'][index]
        v = gltf['bufferViews'][a['bufferView']]
        dtype = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}[a['componentType']]
        columns = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
        return np.ndarray((a['count'], columns), dtype=dtype, buffer=source_binary, offset=v.get('byteOffset', 0) + a.get('byteOffset', 0)).copy()
    matrices = {}
    def gather(index, parent):
        node = gltf['nodes'][index]
        if 'matrix' in node:
            local = np.array(node['matrix']).reshape(4, 4).T
        else:
            from mathutils import Quaternion
            rotation = node.get('rotation', [0, 0, 0, 1])
            local = np.array(Matrix.LocRotScale(Vector(node.get('translation', [0, 0, 0])), Quaternion((rotation[3], *rotation[:3])), Vector(node.get('scale', [1, 1, 1]))))
        world = parent @ local
        matrices[index] = world
        for child in node.get('children', []):
            gather(child, world)
    for index in gltf['scenes'][gltf.get('scene', 0)]['nodes']:
        gather(index, np.eye(4))
    skin = gltf['skins'][0]
    ibms = accessor(skin['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
    joint_matrices = np.stack([matrices[joint] @ ibm for joint, ibm in zip(skin['joints'], ibms)])
    native_report = []
    for index, node in enumerate(gltf['nodes']):
        if 'mesh' not in node:
            continue
        mesh_desc = gltf['meshes'][node['mesh']]
        primitive = mesh_desc['primitives'][0]
        attributes = primitive['attributes']
        positions = accessor(attributes['POSITION'])
        homogeneous = np.column_stack((positions, np.ones(len(positions))))
        weights = accessor(attributes['WEIGHTS_0'])
        joints = accessor(attributes['JOINTS_0'])
        transformed = np.einsum('vbij,vj,vb->vi', joint_matrices[joints], homogeneous, weights)[:, :3]
        # glTF world +Y up -> Blender +Z up.
        converted = transformed[:, [0, 2, 1]]
        converted[:, 1] *= -1
        obj = bpy.data.objects[node['name']]
        assert len(obj.data.vertices) == len(converted), (obj.name, len(obj.data.vertices), len(converted))
        obj.modifiers.clear()
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
        obj.data.vertices.foreach_set('co', converted.astype(np.float32).ravel())
        obj.data.update()
        native_report.append({'name': obj.name, 'mesh': mesh_desc['name'], 'bounds': [converted.min(axis=0).tolist(), converted.max(axis=0).tolist()], 'joint_indices': sorted(set(joints[weights > 0].tolist()))})
    for obj in list(bpy.context.scene.objects):
        if obj.type != 'MESH' or obj.name == 'Icosphere':
            bpy.data.objects.remove(obj, do_unlink=True)
    (PREVIEW / 'native_pose.json').write_text(json.dumps(native_report, indent=2), encoding='utf-8')
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 12
scene.render.threads_mode = 'FIXED'
scene.render.threads = 4
if args.rest:
    for o in scene.objects:
        if o.animation_data:
            o.animation_data_clear()
        if o.type == 'ARMATURE':
            o.data.pose_position = 'REST'
    scene.frame_set(0)
objects = [o for o in scene.objects if o.type == 'MESH' and not o.hide_render]
if args.isolate_body:
    for o in objects:
        if o.name in ('Object_333', 'Icosphere'):
            o.hide_render = True
    objects = [o for o in objects if not o.hide_render]
depsgraph = bpy.context.evaluated_depsgraph_get()
report = []
positions = []
for obj in objects:
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    world = [obj.matrix_world @ v.co for v in mesh.vertices]
    positions.extend(world)
    rawworld = [obj.matrix_world @ v.co for v in obj.data.vertices]
    report.append({'name': obj.name, 'mesh_name': obj.data.name, 'vertices': len(mesh.vertices), 'bounds': [[min(v[i] for v in world) for i in range(3)], [max(v[i] for v in world) for i in range(3)]], 'raw_bounds': [[min(v[i] for v in rawworld) for i in range(3)], [max(v[i] for v in rawworld) for i in range(3)]], 'materials': [m.name if m else None for m in mesh.materials]})
    evaluated.to_mesh_clear()
overall = [[min(v[i] for v in positions) for i in range(3)], [max(v[i] for v in positions) for i in range(3)]]
(PREVIEW / 'source_geometry.json').write_text(json.dumps({'bounds_blender': overall, 'objects': report}, indent=2), encoding='utf-8')
print('SOURCE_BOUNDS', overall, flush=True)
component_report = []
for obj in objects:
    if obj.name not in ('Object_186', 'Object_187', 'Object_333'):
        continue
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    adjacency = [[] for v in mesh.vertices]
    for edge in mesh.edges:
        a, b = edge.vertices
        adjacency[a].append(b)
        adjacency[b].append(a)
    remaining = set(range(len(mesh.vertices)))
    components = []
    while remaining:
        start = min(remaining)
        remaining.remove(start)
        stack, ids = [start], []
        while stack:
            index = stack.pop()
            ids.append(index)
            for neighbor in adjacency[index]:
                if neighbor in remaining:
                    remaining.remove(neighbor)
                    stack.append(neighbor)
        points = [obj.matrix_world @ mesh.vertices[i].co for i in ids]
        components.append({'vertices': len(ids), 'vertex_indices': sorted(ids), 'bounds': [[min(p[i] for p in points) for i in range(3)], [max(p[i] for p in points) for i in range(3)]]})
    component_report.append({'object': obj.name, 'mesh': obj.data.name, 'components': components})
    evaluated.to_mesh_clear()
(PREVIEW / 'source_components.json').write_text(json.dumps(component_report, indent=2), encoding='utf-8')


def plain_material(name, rgba, metallic=0, roughness=.6):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = rgba
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    return mat


def render_view(target, extent, filename, direction=(.28, -1, .20), caption=None):
    if not scene.world:
        scene.world = bpy.data.worlds.new('Studio World')
    scene.world.color = (.16, .16, .16)
    bpy.ops.object.camera_add(location=Vector(target) + Vector(direction).normalized() * extent * 2)
    camera = bpy.context.object
    camera.rotation_euler = (Vector(target) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = extent
    camera.data.clip_end = 5000
    scene.camera = camera
    if caption:
        caption_material = plain_material('Diagnostic caption', (.95, .72, .18, 1))
        bsdf = caption_material.node_tree.nodes['Principled BSDF']
        bsdf.inputs['Emission Color'].default_value = (.95, .72, .18, 1)
        bsdf.inputs['Emission Strength'].default_value = 1
        for line, line_text in enumerate(caption):
            text_data = bpy.data.curves.new('DiagnosticCaption', 'FONT')
            text_data.body = line_text
            text_data.align_x = 'CENTER'
            text_data.size = extent * (.017 if line == 0 else .012)
            text_obj = bpy.data.objects.new('DiagnosticCaption', text_data)
            scene.collection.objects.link(text_obj)
            text_obj.parent = camera
            text_obj.location = (0, extent * (.465 - line * .024), -extent)
            text_data.materials.append(caption_material)
    for location, energy, size in [((1, -1, 1.5), 1800, 1), ((-1, -.2, .8), 1300, 1), ((0, 1, 1.5), 2200, .8)]:
        bpy.ops.object.light_add(type='AREA', location=Vector(target) + Vector(location) * extent * .6)
        light = bpy.context.object
        light.data.energy = energy * extent * extent / 400
        light.data.shape = 'DISK'
        light.data.size = extent * size * .5
        light.rotation_euler = (Vector(target) - light.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.resolution_x = 960
    scene.render.resolution_y = 1120
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = str(PREVIEW / filename)
    scene.view_settings.view_transform = 'AgX'
    bpy.ops.render.render(write_still=True)
    for obj in list(scene.objects):
        if obj.type in ('LIGHT', 'CAMERA', 'FONT'):
            bpy.data.objects.remove(obj, do_unlink=True)


if args.inspect:
    if args.render:
        center = (Vector(overall[0]) + Vector(overall[1])) * .5
        extent = overall[1][2] - overall[0][2]
        if args.chest:
            for obj in objects:
                obj.hide_render = obj.name not in ('Object_186', 'Object_187')
            render_view((-5.5, -8.4, 31.2), 4.2, 'chest_cover_cpu.png', (.35, -1, .3))
        else:
            render_view(center, extent * 1.14, 'diagnostic_body_excluding_funnels_cpu.png', caption=['INSPECTION ONLY - FIN-FUNNEL MESH EXCLUDED', 'The downloaded GLB has malformed wing coordinates. Not game-ready.'])
    print('INSPECT_COMPLETE', flush=True)
    sys.exit(0)
