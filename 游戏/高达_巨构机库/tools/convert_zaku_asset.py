"""CPU-only glTF adaptation. The source is never modified.

Run with Blender --background --factory-startup --threads 4 --python this_file.
17.5 m is a provisional exhibition helmet-crown height, not an official spec.
"""
import argparse
import hashlib
import json
import math
import struct
import sys
from pathlib import Path
import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'source/external/zaku_desert_blendkit/Zaku_Desert_AnonmalyFound.blend'
DERIVED = SOURCE.parent / 'derived'
PREVIEW = ROOT / 'previews/refined_zaku'
DEST = ROOT / 'assets/models/zaku_desert_refined.glb'
for folder in (DERIVED, PREVIEW, DEST.parent):
    folder.mkdir(parents=True, exist_ok=True)
parser = argparse.ArgumentParser()
parser.add_argument('--reuse-bakes', action='store_true')
parser.add_argument('--no-render', action='store_true')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
bpy.ops.wm.open_mainfile(filepath=str(SOURCE), use_scripts=False)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 8
scene.render.threads_mode = 'FIXED'
scene.render.threads = 4
scene.render.bake.margin = 8
scene.render.bake.use_clear = True
scene.render.bake.use_selected_to_active = False
obj = next(o for o in scene.objects if o.type == 'MESH')
bpy.ops.object.select_all(action='DESELECT')
obj.select_set(True)
bpy.context.view_layer.objects.active = obj
bpy.ops.object.convert(target='MESH')
obj = bpy.context.object
obj.parent = None
obj.name = 'Zaku_Desert_Refined'
glass_faces = [p.index for p in obj.data.polygons if obj.data.materials[p.material_index].name.startswith('Fake Glass')]
for other in list(scene.objects):
    if other != obj:
        bpy.data.objects.remove(other, do_unlink=True)
obj.data.uv_layers[0].name = 'SourceUV'
seen_trees = set()
def bind_source_uv(tree):
    if tree.as_pointer() in seen_trees:
        return
    seen_trees.add(tree.as_pointer())
    for node in list(tree.nodes):
        if node.type == 'TEX_COORD':
            uv_links = list(node.outputs['UV'].links)
            if uv_links:
                uv = tree.nodes.new('ShaderNodeUVMap')
                uv.uv_map = 'SourceUV'
                for link in uv_links:
                    tree.links.new(uv.outputs['UV'], link.to_socket)
        elif node.type == 'GROUP' and node.node_tree:
            bind_source_uv(node.node_tree)
for mat in obj.data.materials:
    bind_source_uv(mat.node_tree)
obj.data.uv_layers.new(name='RuntimeUV')
obj.data.uv_layers.active_index = 1
obj.data.uv_layers[1].active_render = True
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=.003,
                         area_weight=.2, correct_aspect=True, scale_to_bounds=False)
bpy.ops.object.mode_set(mode='OBJECT')
surfaces = {}
for mat in obj.data.materials:
    out = next(n for n in mat.node_tree.nodes if n.type == 'OUTPUT_MATERIAL')
    surfaces[mat.name] = (out, out.inputs['Surface'].links[0].from_socket)
def constant(tree, value):
    if isinstance(value, (int, float)):
        n = tree.nodes.new('ShaderNodeValue')
    else:
        n = tree.nodes.new('ShaderNodeRGB')
    n.outputs[0].default_value = value
    return n.outputs[0]
def input_source(tree, socket):
    return socket.links[0].from_socket if socket.is_linked else constant(tree, socket.default_value)
def channel_source(tree, output, channel):
    node = output.node
    if node.type == 'MIX_SHADER':
        mix = tree.nodes.new('ShaderNodeMixRGB')
        tree.links.new(input_source(tree, node.inputs[0]), mix.inputs[0])
        for src_idx, dst_idx in ((1, 1), (2, 2)):
            branch = channel_source(tree, node.inputs[src_idx].links[0].from_socket, channel)
            tree.links.new(branch, mix.inputs[dst_idx])
        return mix.outputs[0]
    if node.type == 'BSDF_PRINCIPLED':
        key = {'color': 'Base Color', 'metallic': 'Metallic', 'roughness': 'Roughness', 'emission': 'Emission Color'}[channel]
        return input_source(tree, node.inputs[key])
    if node.type == 'EMISSION':
        if channel in ('emission', 'color'):
            return input_source(tree, node.inputs['Color'])
        return constant(tree, .35 if channel == 'roughness' else 0.)
    if node.type == 'BSDF_GLASS':
        if channel == 'color':
            return input_source(tree, node.inputs['Color'])
        return constant(tree, .18 if channel == 'roughness' else 0.)
    raise RuntimeError(f'Unsupported source shader: {node.type}')
def bake(name, size, channel=None, normal=False):
    path = DERIVED / f'{name}.png'
    if args.reuse_bakes and path.exists():
        result = bpy.data.images.load(str(path), check_existing=False)
        result.colorspace_settings.name = 'sRGB' if channel == 'color' else 'Non-Color'
        return result
    result = bpy.data.images.new(name, width=size, height=size, alpha=False)
    result.colorspace_settings.name = 'sRGB' if channel == 'color' else 'Non-Color'
    for mat in obj.data.materials:
        tree = mat.node_tree
        out, original = surfaces[mat.name]
        if normal:
            tree.links.new(original, out.inputs['Surface'])
        else:
            emit = tree.nodes.new('ShaderNodeEmission')
            tree.links.new(channel_source(tree, original, channel), emit.inputs['Color'])
            tree.links.new(emit.outputs[0], out.inputs['Surface'])
        texture = tree.nodes.new('ShaderNodeTexImage')
        texture.image = result
        for node in tree.nodes:
            node.select = False
        texture.select = True
        tree.nodes.active = texture
    print('BAKE_START', name, flush=True)
    bpy.ops.object.bake(type='NORMAL' if normal else 'EMIT', normal_space='TANGENT')
    result.filepath_raw = str(path)
    result.file_format = 'PNG'
    result.save()
    print('BAKE_DONE', name, flush=True)
    return result
color = bake('zaku_base_color', 2048, channel='color')
rough = bake('zaku_roughness', 1024, channel='roughness')
metal = bake('zaku_metallic', 1024, channel='metallic')
normal = bake('zaku_normal', 1024, normal=True)
emission = bake('zaku_emission', 512, channel='emission')
orm = bpy.data.images.new('zaku_orm', width=1024, height=1024, alpha=False)
orm.colorspace_settings.name = 'Non-Color'
pixels = np.ones((1024 * 1024, 4), dtype=np.float32)
pixels[:, 1] = np.asarray(rough.pixels[:]).reshape(-1, 4)[:, 0]
pixels[:, 2] = np.asarray(metal.pixels[:]).reshape(-1, 4)[:, 0]
orm.pixels.foreach_set(pixels.ravel())
orm.filepath_raw = str(DERIVED / 'zaku_orm.png')
orm.file_format = 'PNG'
orm.save()
mat = bpy.data.materials.new('Zaku_Desert_Baked_PBR')
mat.use_nodes = True
nodes, links = mat.node_tree.nodes, mat.node_tree.links
bsdf = nodes.get('Principled BSDF')
uv = nodes.new('ShaderNodeUVMap')
uv.uv_map = 'RuntimeUV'
def texture(image):
    tex = nodes.new('ShaderNodeTexImage')
    tex.image = image
    links.new(uv.outputs['UV'], tex.inputs['Vector'])
    return tex.outputs['Color']
links.new(texture(color), bsdf.inputs['Base Color'])
separate = nodes.new('ShaderNodeSeparateColor')
links.new(texture(orm), separate.inputs['Color'])
links.new(separate.outputs['Green'], bsdf.inputs['Roughness'])
links.new(separate.outputs['Blue'], bsdf.inputs['Metallic'])
normal_map = nodes.new('ShaderNodeNormalMap')
normal_map.uv_map = 'RuntimeUV'
links.new(texture(normal), normal_map.inputs['Color'])
links.new(normal_map.outputs['Normal'], bsdf.inputs['Normal'])
links.new(texture(emission), bsdf.inputs['Emission Color'])
bsdf.inputs['Emission Strength'].default_value = 1.0
obj.data.uv_layers.remove(obj.data.uv_layers['SourceUV'])
obj.data.uv_layers.active_index = 0
obj.data.uv_layers[0].active_render = True
obj.data.materials.clear()
obj.data.materials.append(mat)
for polygon in obj.data.polygons:
    polygon.material_index = 0
# Source vertex 15021 is the helmet's round crown; 21023..21028 are antenna tip.
source_helmet = obj.matrix_world @ obj.data.vertices[15021].co
points = [obj.matrix_world @ v.co for v in obj.data.vertices]
floor_z = min(p.z for p in points)
foot_points = [p for p in points if p.z < floor_z + .7]
center_x = (min(p.x for p in foot_points) + max(p.x for p in foot_points)) / 2
center_y = (min(p.y for p in foot_points) + max(p.y for p in foot_points)) / 2
scale = 17.5 / (source_helmet.z - floor_z)
transform = (Matrix.Rotation(math.pi, 4, 'Z') @ Matrix.Scale(scale, 4)
             @ Matrix.Translation((-center_x, -center_y, -floor_z)))
obj.data.transform(transform @ obj.matrix_world)
obj.matrix_world = Matrix.Identity(4)
obj.data.update()
head = bpy.data.objects.new('HeadHeightReference', None)
scene.collection.objects.link(head)
head.location = transform @ source_helmet
head['height_m'] = 17.5
head['basis'] = 'Provisional exhibition helmet crown; not official specification'
floor = bpy.data.objects.new('FeetGroundReference', None)
scene.collection.objects.link(floor)
obj['source'] = 'AnonmalyFound / BlenderKit / CC0'
obj['configuration'] = 'Author desert variation; static posed exhibit'
obj['scale_basis'] = '17.5 m provisional helmet crown; crest excluded'
bm = bmesh.new()
bm.from_mesh(obj.data)
bm.faces.ensure_lookup_table()
bmesh.ops.delete(bm, geom=[bm.faces[index] for index in glass_faces], context='FACES')
bm.to_mesh(obj.data)
bm.free()
mesh_cleaned = obj.data.validate(clean_customdata=False)
obj.vertex_groups.clear()
godot = [Vector((v.co.x, v.co.z, -v.co.y)) for v in obj.data.vertices]
obj.data.calc_loop_triangles()
report = {
    'source': str(SOURCE), 'source_sha256': source_hash, 'author': 'AnonmalyFound', 'license': 'CC0',
    'source_url': 'https://www.blendkit.com/asset-gallery-detail/ebee94b8-5e10-4b96-947b-7788145feaf5/',
    'height_note': '作者沙漠改型；头盔圆顶展陈暂定17.5米，并非经证实的官方机型参数；天线不计入头顶高。',
    'helmet_source_vertex': 15021, 'helmet_source_point': list(source_helmet),
    'floor_source_z': floor_z, 'source_ground_center_xy': [center_x, center_y],
    'uniform_scale': scale, 'head_height_m': float(head.location.z),
    'vertices_before_gltf_seam_splits': len(obj.data.vertices), 'triangles': len(obj.data.loop_triangles),
    'forward_axis': 'Godot -Z',
    'glass_faces_omitted': len(glass_faces), 'mesh_validation_changed_data': mesh_cleaned,
    'godot_bounds_min': [min(p[i] for p in godot) for i in range(3)],
    'godot_bounds_max': [max(p[i] for p in godot) for i in range(3)],
    'maps': {'base_color': [2048, 2048], 'metallic_roughness': [1024, 1024], 'normal': [1024, 1024], 'emission': [512, 512]},
    'limitations': ['Static pose; rig preserved in untouched source only.',
                    'Paint/wear channels and bump normals baked to new atlas; no studio lighting baked.',
                    'Transparent visor lens surfaces omitted so the geometric red mono-eye remains visible without refraction.',
                    'No cockpit, collision mesh, LOD or game rig included.']}
bpy.ops.object.select_all(action='DESELECT')
for item in (obj, head, floor):
    item.select_set(True)
bpy.context.view_layer.objects.active = obj
bpy.ops.export_scene.gltf(filepath=str(DEST), export_format='GLB', use_selection=True,
                          export_animations=False, export_yup=True, export_extras=True,
                          export_texcoords=True, export_normals=True, export_materials='EXPORT')
report['glb_bytes'] = DEST.stat().st_size
report['glb_sha256'] = hashlib.sha256(DEST.read_bytes()).hexdigest()
raw = DEST.read_bytes()
gltf = json.loads(raw[20:20 + struct.unpack_from('<I', raw, 12)[0]])
report['gltf_summary'] = {key: len(gltf.get(key, [])) for key in ('meshes', 'materials', 'images', 'textures', 'skins', 'animations')}
report['gltf_material'] = gltf['materials']
bpy.ops.wm.save_as_mainfile(filepath=str(DERIVED / 'Zaku_Desert_GameReady.blend'))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(DEST))
scene = bpy.context.scene
meshes = [o for o in scene.objects if o.type == 'MESH']
reimport_points = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
for mesh in meshes:
    mesh.data.calc_loop_triangles()
ref = bpy.data.objects.get('HeadHeightReference')
report['reimport'] = {
    'mesh_count': len(meshes), 'materials': [m.name for m in bpy.data.materials],
    'images': [{'name': im.name, 'size': list(im.size)} for im in bpy.data.images if im.type == 'IMAGE'],
    'feet_z': min(p.z for p in reimport_points), 'head_z': float(ref.matrix_world.translation.z),
    'triangles': sum(len(o.data.loop_triangles) for o in meshes),
    'bounds_min_blender': [min(p[i] for p in reimport_points) for i in range(3)],
    'bounds_max_blender': [max(p[i] for p in reimport_points) for i in range(3)]}
assert abs(report['reimport']['feet_z']) < 1e-4
assert abs(report['reimport']['head_z'] - 17.5) < 1e-4
assert len(gltf['images']) >= 4
assert len(gltf['materials']) == 1
assert report['reimport']['triangles'] == report['triangles']
assert all(texture_info.get('texCoord', 0) == 0 for texture_info in (
    gltf['materials'][0]['pbrMetallicRoughness']['baseColorTexture'],
    gltf['materials'][0]['normalTexture']))
assert source_hash == hashlib.sha256(SOURCE.read_bytes()).hexdigest()
(DERIVED / 'conversion_report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
(PREVIEW / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
if not args.no_render:
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.threads_mode = 'FIXED'
    scene.render.threads = 4
    scene.render.resolution_x, scene.render.resolution_y = 660, 780
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = 'AgX'
    scene.world = bpy.data.worlds.new('CPU_Studio')
    scene.world.use_nodes = True
    scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (.12, .16, .22, 1)
    scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = .4
    def aim(o, target):
        o.rotation_euler = (Vector(target) - o.location).to_track_quat('-Z', 'Y').to_euler()
    for name, loc, energy, size, col in (
        ('Key', (-5, 15, 28), 12000, 15, (1, .94, .85)),
        ('Fill', (14, 8, 17), 6500, 12, (.64, .79, 1)),
        ('Rim', (-5, -12, 24), 15000, 10, (.7, .83, 1))):
        data = bpy.data.lights.new(name, 'AREA')
        data.energy, data.shape, data.size, data.color = energy, 'DISK', size, col
        light = bpy.data.objects.new(name, data)
        scene.collection.objects.link(light)
        light.location = loc
        aim(light, (0, 0, 9))
    bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.02))
    stage_mat = bpy.data.materials.new('Stage')
    stage_mat.use_nodes = True
    stage_mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (.06, .075, .1, 1)
    stage_mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = .7
    bpy.context.object.data.materials.append(stage_mat)
    human_mat = bpy.data.materials.new('ScaleWitness_1_75m')
    human_mat.use_nodes = True
    human_mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (.95, .45, .05, 1)
    for loc, scale_ in [((-5, 2, .5), (.18, .12, .5)), ((-5, 2, 1.23), (.25, .14, .28))]:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, location=loc)
        bpy.context.object.scale = scale_
        bpy.context.object.data.materials.append(human_mat)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=.14, location=(-5, 2, 1.61))
    bpy.context.object.data.materials.append(human_mat)
    camera_data = bpy.data.cameras.new('CPU_Camera')
    camera = bpy.data.objects.new('CPU_Camera', camera_data)
    scene.collection.objects.link(camera)
    camera.location = (-27, 48, 23)
    camera.data.type, camera.data.ortho_scale = 'ORTHO', 24.5
    aim(camera, (0, -.3, 9))
    scene.camera = camera
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = str(PREVIEW / 'zaku_game_ready.png')
    bpy.ops.render.render(write_still=True)
print('ZAKU_CONVERSION_VERIFIED', json.dumps(report['godot_bounds_min']), json.dumps(report['godot_bounds_max']), flush=True)
