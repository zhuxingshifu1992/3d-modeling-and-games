"""Reproducible CPU-only RX-78 source conversion; never saves the acquired blend.

Run Blender --background --disable-autoexec --python tools/convert_rx78_asset.py
No UI or pointer APIs. Output is a static hangar asset, not a combat rig.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'source/external/rx78_blendkit/Gundam_RX-78-2_AnonmalyFound.blend'
DERIVED = SOURCE.parent / 'derived'
PREVIEW = ROOT / 'previews/refined_rx78'
TARGET = ROOT / 'assets/models/rx78_refined.glb'
SOURCE_HASH = 'c67450570c53c6de39bee12b0d5e1bd366761efd4572e1e8e1fa26a5f4a4bdb8'
parser = argparse.ArgumentParser()
parser.add_argument('--render', action='store_true')
parser.add_argument('--reuse-bake', action='store_true')
parser.add_argument('--open-cavity', action='store_true')
parser.add_argument('--hatch-forward', type=float, default=.55, help='Preview-only forward travel before opening; meters.')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
DERIVED.mkdir(parents=True, exist_ok=True)
PREVIEW.mkdir(parents=True, exist_ok=True)
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == SOURCE_HASH, 'Reinspect changed source before converting.'
bpy.ops.wm.open_mainfile(filepath=str(SOURCE), use_scripts=False)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 8
scene.render.threads_mode = 'FIXED'
scene.render.threads = 4
source_obj = next(o for o in scene.objects if o.type == 'MESH')
source_mesh = source_obj.data
assert len(source_mesh.vertices) == 36215
depsgraph = bpy.context.evaluated_depsgraph_get()
mesh = bpy.data.meshes.new_from_object(source_obj.evaluated_get(depsgraph), preserve_all_data_layers=True, depsgraph=depsgraph)
obj = bpy.data.objects.new('RX78Body', mesh)
scene.collection.objects.link(obj)
obj.matrix_world = source_obj.matrix_world.copy()
for old in list(scene.objects):
    if old != obj:
        bpy.data.objects.remove(old, do_unlink=True)
bpy.context.view_layer.objects.active = obj
obj.select_set(True)

# Connected components were measured and visually identified in the source.
# 17541..18666 = helmet; 18667..18720 = central helmet crest;
# 18721..18891 = V antenna; 783..1284 = complete central blue chest cover.
foot_floor = min(v.co.z for v in mesh.vertices)
head_crown = max(mesh.vertices[i].co.z for i in range(18667, 18721))
scale = 18.0 / (head_crown - foot_floor)
center_x = .0093020200729
head_world = max((mesh.vertices[i].co.copy() for i in range(18667, 18721)), key=lambda v: v.z)
head_helmet = max(mesh.vertices[i].co.z for i in range(17541, 18667))
antenna_top = max(mesh.vertices[i].co.z for i in range(18721, 18892))
hatch_ids = set(range(783, 1285))

# Preserve the authored UV layer for procedural/grunge shader inputs; bake to
# a fresh nonoverlapping atlas. Shared source UVs must not be used as an atlas.
original_uv = mesh.uv_layers.active.name
atlas_uv = mesh.uv_layers.new(name='GameAtlas')
mesh.uv_layers.active = atlas_uv
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(70), island_margin=.0008, area_weight=.6, correct_aspect=True)
bpy.ops.object.mode_set(mode='OBJECT')
mesh.uv_layers[original_uv].active_render = True

palette_report = []
converted = []
valid_red = bpy.data.materials['Red Old Paint.001']
atlas_path = DERIVED / 'rx78_basecolor_2k.png'
atlas = bpy.data.images.load(str(atlas_path), check_existing=False) if args.reuse_bake and atlas_path.exists() else bpy.data.images.new('RX78_BaseColor_2K', width=2048, height=2048, alpha=False)
atlas.colorspace_settings.name = 'sRGB'
for index, oldmat in enumerate(list(mesh.materials)):
    original_name = oldmat.name if oldmat else '<empty>'
    # The missing linked library only affected this red paint assignment.
    template = valid_red if oldmat and oldmat.name in ('Red Old Paint.002', 'Red Old Paint.003') else oldmat
    if template:
        mat = template.copy()
    else:
        mat = bpy.data.materials.new('Recovered_White_EmptySlot')
        mat.use_nodes = True
        mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (.72, .75, .78, 1)
    mat.name = 'Bake_' + original_name.replace('<', '').replace('>', '')
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next((n for n in nodes if n.type == 'BSDF_PRINCIPLED'), None)
    original_emitter = next((n for n in nodes if n.type == 'EMISSION'), None)
    roughness = float(bsdf.inputs['Roughness'].default_value) if bsdf else .5
    is_paint = 'Old Paint' in original_name
    metallic = .22 if is_paint else float(bsdf.inputs['Metallic'].default_value) if bsdf else 0.0
    if 'Silver' in original_name or 'Copper' in original_name:
        metallic, roughness = .82, .36
    emission = list(bsdf.inputs['Emission Color'].default_value) if bsdf else [0, 0, 0, 1]
    if original_emitter:
        emission = list(original_emitter.inputs['Color'].default_value)
    output = next(n for n in nodes if n.type == 'OUTPUT_MATERIAL')
    emitter = nodes.new('ShaderNodeEmission')
    paint = nodes.get('Group.001')
    edge = nodes.get('Group')
    if paint and paint.type == 'GROUP' and paint.node_tree and 'Color' in paint.outputs:
        links.new(paint.outputs['Color'], emitter.inputs['Color'])
    elif bsdf:
        base = bsdf.inputs['Base Color']
        if base.is_linked:
            links.new(base.links[0].from_socket, emitter.inputs['Color'])
        else:
            emitter.inputs['Color'].default_value = base.default_value
        if original_name == 'Material.003':
            # Opaque smoked optical window replaces unsupported glass transmission.
            emitter.inputs['Color'].default_value = (.014, .028, .04, 1)
    elif original_emitter:
        emitter.inputs['Color'].default_value = original_emitter.inputs['Color'].default_value
    links.new(emitter.outputs[0], output.inputs['Surface'])
    image_node = nodes.new('ShaderNodeTexImage')
    image_node.image = atlas
    nodes.active = image_node
    mesh.materials[index] = mat
    converted.append((original_name, roughness, metallic, emission))
    palette_report.append({'slot': index, 'source': original_name, 'roughness_constant': roughness, 'metallic_constant': metallic, 'repair': 'valid red paint graph substituted' if template != oldmat else 'white recovery for empty slot' if oldmat is None else None})

if not (args.reuse_bake and atlas_path.exists()):
    scene.render.bake.margin = 12
    scene.render.bake.use_clear = True
    bpy.ops.object.bake(type='EMIT', uv_layer='GameAtlas')
    atlas.filepath_raw = str(atlas_path)
    atlas.file_format = 'PNG'
    atlas.save()
atlas.pack()

# Replace shader graphs with portable glTF metallic/roughness materials.
for index, (name, rough, metal, emission) in enumerate(converted):
    mat = bpy.data.materials.new('RX78_PBR_' + name.replace('<', '').replace('>', ''))
    mat.use_nodes = True
    mat.use_backface_culling = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes['Principled BSDF']
    bsdf.inputs['Roughness'].default_value = max(.3, min(.68, rough))
    bsdf.inputs['Metallic'].default_value = metal
    if max(emission[:3]) > .001:
        bsdf.inputs['Emission Color'].default_value = emission
        bsdf.inputs['Emission Strength'].default_value = 1
    texture = nodes.new('ShaderNodeTexImage')
    texture.image = atlas
    uv = nodes.new('ShaderNodeUVMap')
    uv.uv_map = 'GameAtlas'
    links.new(uv.outputs[0], texture.inputs['Vector'])
    links.new(texture.outputs['Color'], bsdf.inputs['Base Color'])
    mesh.materials[index] = mat
mesh.uv_layers.active = mesh.uv_layers['GameAtlas']
mesh.uv_layers['GameAtlas'].active_render = True

# Bake feet translation, exact non-antenna height and front orientation into
# vertices. Blender +Y becomes glTF/Godot -Z with the standard Y-up export.
for vertex in mesh.vertices:
    v = vertex.co
    vertex.co = (-(v.x - center_x) * scale, -v.y * scale, (v.z - foot_floor) * scale)
mesh.update()
hatch_face_ids = {p.index for p in mesh.polygons if all(i in hatch_ids for i in p.vertices)}
assert len(hatch_face_ids) == 421
hatch_mesh = mesh.copy()
hatch = bpy.data.objects.new('CockpitHatch', hatch_mesh)
scene.collection.objects.link(hatch)
for part_mesh, keep_hatch in ((mesh, False), (hatch_mesh, True)):
    bm = bmesh.new()
    bm.from_mesh(part_mesh)
    bm.faces.ensure_lookup_table()
    delete_faces = [face for face in bm.faces if ((face.index in hatch_face_ids) != keep_hatch)]
    bmesh.ops.delete(bm, geom=delete_faces, context='FACES')
    bm.to_mesh(part_mesh)
    bm.free()
    part_mesh.update()
hinge = Vector((0, .5162730217, 15.5236797333))
for v in hatch.data.vertices:
    v.co -= hinge
hatch.location = hinge
hatch['role'] = 'Original complete blue central chest cover; closed geometry unchanged.'

if args.open_cavity:
    # The authored mesh contains disconnected, non-watertight armor shells.
    # Boolean solid classification is therefore unreliable. Split its surfaces
    # at the six cavity boundaries, delete all inside fragments, and let the
    # game cockpit supply the inner walls. This creates no false end-cap faces.
    for part in (obj, hatch):
        front = 3.0 if part == obj else 1.45
        lower = Vector((-.61, -.45, 12.65)) - part.location
        upper = Vector((.61, front, 14.75)) - part.location
        bm = bmesh.new()
        bm.from_mesh(part.data)
        for axis in range(3):
            normal = Vector((0, 0, 0))
            normal[axis] = 1
            for bound in (lower[axis], upper[axis]):
                point = Vector((0, 0, 0))
                point[axis] = bound
                bmesh.ops.bisect_plane(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces), dist=.000001,
                                      plane_co=point, plane_no=normal, clear_inner=False, clear_outer=False)
        remove = [f for f in bm.faces if all(lower[i] - .000001 <= f.calc_center_median()[i] <= upper[i] + .000001 for i in range(3))]
        bmesh.ops.delete(bm, geom=remove, context='FACES')
        bm.to_mesh(part.data)
        bm.free()
        part.data.update()

# Boolean-generated ngon boundaries and legacy source topology are triangulated
# before export so exporter and Godot receive an identical triangle surface.
for part in (obj, hatch):
    part.data.validate(verbose=False, clean_customdata=False)
    bm = bmesh.new()
    bm.from_mesh(part.data)
    bmesh.ops.triangulate(bm, faces=list(bm.faces), quad_method='BEAUTY', ngon_method='BEAUTY')
    bm.to_mesh(part.data)
    bm.free()
    part.data.update()
    part.data.validate(verbose=False)
    assert not part.data.validate(verbose=False), 'Mesh validation must be stable before export.'

reference = bpy.data.objects.new('HeadHeightReference', None)
reference.location = (0, 0, 18)
scene.collection.objects.link(reference)
reference['basis'] = 'Top of central helmet crest, excluding V antenna and backpack equipment.'
reference['source_crest_z'] = head_crown
reference['source_feet_z'] = foot_floor
reference['uniform_scale'] = scale
obj['source'] = 'AnonmalyFound / BlenderKit / CC0'
obj['source_asset_id'] = 'a6a1000b-3b72-48bb-be81-6f4ab36fabda'
obj['game_front'] = '-Z'
obj['head_height_m'] = 18.0

for o in scene.objects:
    o.select_set(o in (obj, hatch, reference))
bpy.context.view_layer.objects.active = obj
bpy.context.preferences.filepaths.save_version = 0
bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
bpy.ops.wm.save_as_mainfile(filepath=str(DERIVED / 'RX78_game_asset.blend'), check_existing=False)
bpy.ops.export_scene.gltf(filepath=str(TARGET), export_format='GLB', use_selection=True,
                          export_yup=True, export_apply=True, export_animations=False,
                          export_skins=False, export_cameras=False, export_lights=False,
                          export_extras=True, export_materials='EXPORT')

# Reimport the shipped file and assert the coordinate/mesh contract.
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(TARGET))
imported = [o for o in scene.objects if o.type == 'MESH']
reference = bpy.data.objects['HeadHeightReference']
all_positions = [o.matrix_world @ v.co for o in imported for v in o.data.vertices]
minimum = [min(v[i] for v in all_positions) for i in range(3)]
maximum = [max(v[i] for v in all_positions) for i in range(3)]
assert abs(minimum[2]) < .0002
assert abs(reference.matrix_world.translation.z - 18) < .0002
triangles = 0
for o in imported:
    o.data.calc_loop_triangles()
    triangles += len(o.data.loop_triangles)
    assert len(o.data.uv_layers) > 0
assert 'CockpitHatch' in bpy.data.objects
assert {o.name for o in imported} == {'CockpitHatch', 'RX78Body'}
report = {'source_sha256': SOURCE_HASH, 'output_sha256': hashlib.sha256(TARGET.read_bytes()).hexdigest(),
          'output_bytes': TARGET.stat().st_size, 'source_foot_z': foot_floor,
          'source_helmet_z': head_helmet, 'source_central_crest_z': head_crown,
          'source_v_antenna_z': antenna_top, 'uniform_scale': scale,
          'head_height_m': 18.0, 'height_basis': 'central helmet crest; excludes V antenna and backpack',
          'front_godot': '-Z', 'reimported_blender_bounds_min': minimum,
          'reimported_blender_bounds_max': maximum,
          'reimported_triangles': triangles, 'mesh_nodes': [o.name for o in imported],
          'hatch_closed_godot_aabb_min': [-.743963, 12.317000, -2.350024],
          'hatch_closed_godot_aabb_max': [.743962, 15.523680, -.516273],
          'hatch_pivot_godot': [0, 15.5236797333, -.5162730217],
          'internal_cavity': {'enabled': args.open_cavity, 'width': 1.22, 'floor_y': 12.65, 'ceiling_y': 14.75, 'body_front_z': -3.0, 'hatch_inner_front_z': -1.45, 'rear_z': .45, 'method': 'six-plane surface clipping, no generated caps', 'hatch_inner_back_removed': args.open_cavity},
          'texture': {'basecolor': 'rx78_basecolor_2k.png', 'size': [2048, 2048], 'embedded_in_glb': True, 'bake': 'CPU emission bake of authored paint color output; fresh non-overlapping atlas'},
          'materials': palette_report,
          'limitations': ['Static posed mesh: rig intentionally not shipped.', 'Roughness and metallic are per-material constants; original bevel, bump and view-dependent undercoat shader effects are not preserved.', 'Atlas is 2K for current laptop memory budget, not a close-up cinematic texture set.', 'Missing external red material graph is repaired from the included red material; 22 empty-slot faces use neutral white.', 'Glass transmission window is approximated as opaque smoked glass for compatibility; eye and sensor emission color preserved.']}
(DERIVED / 'conversion_report.json').write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding='utf-8')
print('RX78_CONVERSION_VERIFIED', json.dumps({k: report[k] for k in ('output_bytes', 'reimported_triangles', 'head_height_m', 'mesh_nodes')}), flush=True)

if args.render:
    scene.cycles.samples = 16
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = 900, 1100
    scene.render.resolution_percentage = 100
    scene.world = bpy.data.worlds.new('RefinedStudio')
    scene.world.use_nodes = True
    scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (.1, .14, .21, 1)
    scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = .5
    scene.view_settings.view_transform = 'AgX'
    def aim(o, point):
        o.rotation_euler = (Vector(point) - o.location).to_track_quat('-Z', 'Y').to_euler()
    for name, location, energy, size, color in [('Key', (-8, 16, 26), 15000, 15, (1, .92, .83)), ('Fill', (12, 8, 16), 7000, 12, (.65, .8, 1)), ('Rim', (-8, -10, 22), 14000, 10, (.8, .9, 1))]:
        light = bpy.data.lights.new(name, 'AREA')
        light.energy, light.shape, light.size, light.color = energy, 'DISK', size, color
        ob = bpy.data.objects.new(name, light)
        scene.collection.objects.link(ob)
        ob.location = location
        aim(ob, (0, 0, 9))
    bpy.ops.mesh.primitive_plane_add(size=100, location=(0, 0, -.01))
    ground = bpy.data.materials.new('PreviewGround')
    ground.diffuse_color = (.05, .07, .1, 1)
    bpy.context.object.data.materials.append(ground)
    camera = bpy.data.objects.new('PreviewCamera', bpy.data.cameras.new('PreviewCamera'))
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.location = (-24, 47, 23)
    camera.data.type, camera.data.ortho_scale = 'ORTHO', 23
    aim(camera, (0, 0, 9))
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = str(PREVIEW / 'rx78_refined.png')
    bpy.ops.render.render(write_still=True)
    print('RX78_RENDER_VERIFIED', scene.render.filepath, flush=True)
    bpy.data.objects['CockpitHatch'].rotation_mode = 'XYZ'
    bpy.data.objects['CockpitHatch'].location.y += args.hatch_forward
    bpy.data.objects['CockpitHatch'].rotation_euler.x = math.radians(90)
    camera.location = (-9, 24, 17)
    camera.data.ortho_scale = 9
    aim(camera, (0, 0, 14.4))
    scene.render.filepath = str(PREVIEW / 'rx78_hatch_open.png')
    bpy.ops.render.render(write_still=True)
    print('RX78_OPEN_RENDER_VERIFIED', scene.render.filepath, flush=True)
