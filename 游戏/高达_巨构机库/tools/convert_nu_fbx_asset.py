"""CPU-only Nu Gundam conversion from the preserved original-format FBX."""
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
BASE = ROOT / 'source/external/nu_sketchfab'
SOURCE = BASE / 'original_fbx/source/rx-93 nu gundam 28 web 1.fbx'
DERIVED = BASE / 'derived'
PREVIEW = ROOT / 'previews/refined_nu'
TARGET = ROOT / 'assets/models/nu_refined.glb'
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == '8cdb1d15f773efe4116f63643e1c6bfb7cbc04bb49f83a65ab0361b2045b0f6a', 'Reinspect changed FBX before converting.'
assert hashlib.sha256((DERIVED / 'nu_source_textures_2k.glb').read_bytes()).hexdigest() == '61003f661f8f8d3ba03cf56a8d3bffcb798360687293c409436aabe8e0f3f116', 'Reinspect changed PBR source before converting.'
parser = argparse.ArgumentParser()
parser.add_argument('--inspect', action='store_true')
parser.add_argument('--render', action='store_true')
parser.add_argument('--open-preview', action='store_true')
parser.add_argument('--sample-poses', action='store_true')
parser.add_argument('--park-legs', action='store_true')
args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
bpy.ops.wm.read_factory_settings(use_empty=True)
# Retain the same author's portable PBR material graphs. Their geometry is
# rejected, but texture/material payloads were independently validated.
bpy.ops.import_scene.gltf(filepath=str(DERIVED / 'nu_source_textures_2k.glb'))
portable_materials = {m.name: m for m in bpy.data.materials}
gltf_uv_samples = {}
for o in bpy.context.scene.objects:
    if o.type == 'MESH' and o.name in ('Object_164','Object_186','Object_187'):
        evaluated=o.evaluated_get(bpy.context.evaluated_depsgraph_get());mesh=evaluated.to_mesh()
        mapping={}
        for poly in mesh.polygons:
            for index in poly.loop_indices:
                p=o.matrix_world@mesh.vertices[mesh.loops[index].vertex_index].co
                mapping.setdefault(tuple(round(c/7.935752868652344,3) for c in p),[]).append(list(mesh.uv_layers[0].data[index].uv))
        gltf_uv_samples[o.name]=mapping
        evaluated.to_mesh_clear()
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.fbx(filepath=str(SOURCE), use_image_search=False)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 12
scene.render.threads_mode = 'FIXED'
scene.render.threads = 4
pose_report = {'mode':'author default action frame 1'}
if args.park_legs or not (args.inspect or args.sample_poses):
    rig=next(o for o in scene.objects if o.type=='ARMATURE')
    scene.frame_set(1)
    right_matrices={name:rig.pose.bones[name].matrix.copy() for name in ('Hip.R','Knee.R','Shin.R','foot.R','Toe.R')}
    plane_x=(rig.data.bones['Hip.L'].head_local.x+rig.data.bones['Hip.R'].head_local.x)*.5
    mirror=Matrix.Identity(4);mirror[0][0]=-1;mirror[0][3]=plane_x*2
    rig.animation_data_clear()
    for right_name in ('Hip.R','Knee.R','Shin.R','foot.R','Toe.R'):
        left_name=right_name[:-1]+'L'
        right_deformation=right_matrices[right_name]@rig.data.bones[right_name].matrix_local.inverted()
        rig.pose.bones[left_name].matrix=mirror@right_deformation@mirror@rig.data.bones[left_name].matrix_local
        bpy.context.view_layer.update()
    foot_source=bpy.data.objects['Plane.045'];evaluated=foot_source.evaluated_get(bpy.context.evaluated_depsgraph_get());foot_mesh=evaluated.to_mesh()
    minima={}
    for side in ('.L','.R'):
        ids=[v.index for v in foot_source.data.vertices if sum(g.weight for g in v.groups if foot_source.vertex_groups[g.group].name.endswith(side))>.5]
        minima[side]=min((foot_source.matrix_world@foot_mesh.vertices[index].co).z for index in ids)
    evaluated.to_mesh_clear()
    delta_z=minima['.R']-minima['.L']
    # The source left/right rest meshes are not exact mirror copies. A small
    # rigid correction through the hip control plants the sole without scaling
    # the leg, changing bone lengths, or moving the torso/cockpit geometry.
    local_delta=rig.matrix_world.inverted().to_3x3()@Vector((0,0,delta_z))
    rig.pose.bones['Hip.L'].matrix=Matrix.Translation(local_delta)@rig.pose.bones['Hip.L'].matrix
    bpy.context.view_layer.update()
    pose_report={'mode':'parked: original grounded right-leg skeletal deformation mirrored to corresponding left leg, then rigid sole placement through hip control; upper-body pose and limb scale unchanged','mirrored_bones':['Hip.L','Knee.L','Shin.L','foot.L','Toe.L'],'armature_local_mirror_plane_x':plane_x,'left_hip_rigid_vertical_correction_source':delta_z}
depsgraph = bpy.context.evaluated_depsgraph_get()
objects = [o for o in scene.objects if o.type == 'MESH']
report = []
positions = []
for obj in objects:
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh()
    points = [obj.matrix_world @ v.co for v in mesh.vertices]
    positions.extend(points)
    used_vertices = set(i for p in mesh.polygons for i in p.vertices)
    used_points = [obj.matrix_world @ mesh.vertices[i].co for i in used_vertices]
    report.append({'name': obj.name, 'mesh': obj.data.name, 'vertices': len(mesh.vertices), 'loose_vertices': len(mesh.vertices) - len(used_vertices), 'bounds': [[min(p[i] for p in points) for i in range(3)], [max(p[i] for p in points) for i in range(3)]], 'surface_bounds': [[min(p[i] for p in used_points) for i in range(3)], [max(p[i] for p in used_points) for i in range(3)]], 'materials': [m.name if m else None for m in mesh.materials]})
    if obj.name=='Plane.045':
        side_min={}
        for side in ('.L','.R'):
            ids=[v.index for v in obj.data.vertices if sum(g.weight for g in v.groups if obj.vertex_groups[g.group].name.endswith(side))>.5]
            side_min[side]=min((obj.matrix_world@mesh.vertices[index].co).z for index in ids)
        pose_report['feet_min_z']=side_min
    evaluated.to_mesh_clear()
overall = [[min(v[i] for v in positions) for i in range(3)], [max(v[i] for v in positions) for i in range(3)]]
(PREVIEW / 'original_fbx_inspection.json').write_text(json.dumps({'source': str(SOURCE), 'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(), 'bounds': overall, 'objects': report, 'images': [{'name': i.name, 'filepath': i.filepath} for i in bpy.data.images], 'actions': [a.name for a in bpy.data.actions], 'armatures': [{'name':o.name, 'bones': len(o.data.bones)} for o in scene.objects if o.type=='ARMATURE']}, ensure_ascii=False, indent=2), encoding='utf-8')
print('FBX_SOURCE_BOUNDS', overall, flush=True)
print('POSE_REPORT',pose_report,flush=True)
for item in report:
    if '119' in item['name'] or 'WINGS' in item['mesh']:
        print('WING_BOUNDS', item, flush=True)
if args.sample_poses:
    rig=next(o for o in scene.objects if o.type=='ARMATURE')
    foot=bpy.data.objects['Plane.045']; head=bpy.data.objects['Plane.003']; chest_source=bpy.data.objects['Plane.018']
    side_ids={'.L':[],'.R':[]}
    for vertex in foot.data.vertices:
        weights={side:sum(g.weight for g in vertex.groups if foot.vertex_groups[g.group].name.endswith(side)) for side in side_ids}
        side=max(weights,key=weights.get)
        assert weights[side]>.5,(vertex.index,weights)
        side_ids[side].append(vertex.index)
    def center_eval(obj):
        evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get());m=evaluated.to_mesh();p=[obj.matrix_world@v.co for v in m.vertices];result=sum(p,Vector())/len(p);evaluated.to_mesh_clear();return result
    baseline_chest=center_eval(chest_source)
    samples=[]
    for action in list(bpy.data.actions):
        if not action.name.startswith('Armature|Armature|') or 'Camera' in action.name: continue
        rig.animation_data.action=action;rig.animation_data.action_slot=action.slots[0]
        for frame in sorted(set([1,int(action.frame_range[1])] + list(range(1,int(action.frame_range[1])+1,10)))):
            scene.frame_set(frame)
            evaluated=foot.evaluated_get(bpy.context.evaluated_depsgraph_get());m=evaluated.to_mesh()
            foot_min=[min((foot.matrix_world@m.vertices[index].co).z for index in side_ids[side]) for side in ('.L','.R')]
            evaluated.to_mesh_clear()
            samples.append({'action':action.name,'frame':frame,'foot_min_z':foot_min,'height_difference':abs(foot_min[0]-foot_min[1]),'chest_center':list(center_eval(chest_source)),'chest_displacement':(center_eval(chest_source)-baseline_chest).length,'head_center':list(center_eval(head))})
    samples.sort(key=lambda s:s['height_difference']+s['chest_displacement']*10)
    (PREVIEW/'fbx_pose_samples.json').write_text(json.dumps(samples,indent=2),encoding='utf-8')
    print('BEST_POSES',samples[:8],flush=True)
    sys.exit(0)
if args.inspect:
    extra={}
    for o in objects:
        if o.name not in ('Plane.003','Plane.018'):continue
        eval_o=o.evaluated_get(depsgraph);mesh=eval_o.to_mesh()
        candidates=gltf_uv_samples['Object_164'] if o.name=='Plane.003' else {**gltf_uv_samples['Object_186'],**gltf_uv_samples['Object_187']}
        scores=[]
        for layer in mesh.uv_layers:
            errors=[]
            for loop in mesh.loops:
                p=o.matrix_world@mesh.vertices[loop.vertex_index].co
                key=tuple(round(c,3) for c in p)
                if key in candidates:
                    uv=layer.data[loop.index].uv
                    errors.append(min((uv-Vector(candidate)).length for candidate in candidates[key]))
            scores.append({'name':layer.name,'active_render':layer.active_render,'matched_corner_count':len(errors),'mean_uv_error_vs_glb':sum(errors)/len(errors) if errors else None})
        extra[o.name]=scores
        eval_o.to_mesh_clear()
    extra['actions']=[{'name':a.name,'range':list(a.frame_range),'slots':[s.identifier for s in a.slots]} for a in bpy.data.actions]
    extra['bones']=[b.name for o in scene.objects if o.type=='ARMATURE' for b in o.pose.bones]
    (PREVIEW/'fbx_uv_animation_inspection.json').write_text(json.dumps(extra,ensure_ascii=False,indent=2),encoding='utf-8')
    print('FBX_INSPECT_COMPLETE', flush=True)
    sys.exit(0)

# The original FBX retains a valid fin-funnel mesh. A few loose, unrendered
# vertices in another chest object must not define the feet/height reference.
surface_floor = min(item['surface_bounds'][0][2] for item in report)
crown_z = next(item['surface_bounds'][1][2] for item in report if item['name'] == 'Plane.003')
scale = 22.0 / (crown_z - surface_floor)
center_x = -.69261234998703
center_y = -1.0
conversion_matrix = Matrix((( -scale, 0, 0, center_x * scale), (0, -scale, 0, center_y * scale), (0, 0, scale, -surface_floor * scale), (0,0,0,1)))
material_map = {}
static_objects = []
loose_removed = 0
for old in objects:
    mesh = bpy.data.meshes.new_from_object(old.evaluated_get(depsgraph), preserve_all_data_layers=True, depsgraph=depsgraph)
    mesh.transform(conversion_matrix @ old.matrix_world)
    # The platform material payload vertically flips the original FBX images
    # (and inverts the normal-map green channel); match its UV orientation.
    for uv_layer in mesh.uv_layers:
        for loop_uv in uv_layer.data:
            loop_uv.uv.y = 1.0 - loop_uv.uv.y
    obj = bpy.data.objects.new('Static_' + old.name, mesh)
    scene.collection.objects.link(obj)
    for i, mat in enumerate(mesh.materials):
        original_name = mat.name
        key = '_'.join(original_name.strip().split())
        if original_name.strip() == 'Jet':
            key = 'material'
        assert key in portable_materials, (original_name, key, list(portable_materials))
        mesh.materials[i] = portable_materials[key]
        material_map[original_name] = key
    used = set(i for poly in mesh.polygons for i in poly.vertices)
    if len(used) != len(mesh.vertices):
        bm = bmesh.new(); bm.from_mesh(mesh); bm.verts.ensure_lookup_table()
        loose = [v for v in bm.verts if not v.link_faces]
        loose_removed += len(loose)
        bmesh.ops.delete(bm, geom=loose, context='VERTS')
        bm.to_mesh(mesh); bm.free()
    static_objects.append(obj)
for old in list(scene.objects):
    if old not in static_objects:
        bpy.data.objects.remove(old, do_unlink=True)

chest = bpy.data.objects['Static_Plane.018']
# Preserve the ring around the neck; split only the lower central armor plate.
# Bisecting retains the closed shape and original UV interpolation.
hatch_top = 18.405
hatch_back_y = 1.50
bm = bmesh.new(); bm.from_mesh(chest.data)
for axis, value in [(2,hatch_top),(1,hatch_back_y)]:
    point = Vector((0,0,0)); point[axis] = value
    normal = Vector((0,0,0)); normal[axis] = 1
    bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces), dist=1e-6, plane_co=point, plane_no=normal, clear_inner=False, clear_outer=False)
bm.to_mesh(chest.data); bm.free(); chest.data.update()
hatch_faces = {p.index for p in chest.data.polygons if p.center.z <= hatch_top + 1e-5 and p.center.y >= hatch_back_y - 1e-5}
assert len(hatch_faces) > 10
hatch_mesh = chest.data.copy()
hatch = bpy.data.objects.new('CockpitHatch', hatch_mesh); scene.collection.objects.link(hatch)
for mesh, keep_hatch in [(chest.data,False),(hatch_mesh,True)]:
    bm=bmesh.new();bm.from_mesh(mesh);bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if ((f.index in hatch_faces) != keep_hatch)], context='FACES')
    bm.to_mesh(mesh);bm.free();mesh.update()

# Join all authored static body parts except the inspectable fin-funnel group
# and hatch. Blender retains material slots/UVs and emits one surface per mat.
funnels = bpy.data.objects['Static_Plane.119']; funnels.name='FinFunnels'
bpy.ops.object.select_all(action='DESELECT')
body_parts = [o for o in static_objects if o != funnels]
for obj in body_parts: obj.select_set(True)
bpy.context.view_layer.objects.active = chest
bpy.ops.object.join(); body=chest;body.name='NuBody'

def clear_volume(obj, lower, upper):
    bm=bmesh.new();bm.from_mesh(obj.data)
    for axis in range(3):
        normal=Vector((0,0,0));normal[axis]=1
        for bound in (lower[axis],upper[axis]):
            point=Vector((0,0,0));point[axis]=bound
            bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces), dist=1e-6, plane_co=point, plane_no=normal, clear_inner=False, clear_outer=False)
    faces=[f for f in bm.faces if all(lower[i]-1e-5 <= f.calc_center_median()[i] <= upper[i]+1e-5 for i in range(3))]
    removed=len(faces)
    bmesh.ops.delete(bm,geom=faces,context='FACES')
    bm.to_mesh(obj.data);bm.free();obj.data.update()
    return removed

# The entrance follows the authored 0.83 m central plate. The interior widens
# behind the yellow vent assemblies, rather than cutting through their fronts.
cavity_narrow = [(-.40,1.47,16.16),(.40,3.40,18.405)]
cavity_inner = [(-.61,-.58,16.16),(.61,1.47,18.48)]
removed_narrow=clear_volume(body,*cavity_narrow)
removed_inner=clear_volume(body,*cavity_inner)

hinge=Vector((0,2.96,hatch_top))
for v in hatch.data.vertices: v.co-=hinge
hatch.location=hinge
hatch['role']='Original lower central chest plate and red hatch; upper ring and vents remain fixed.'
for obj in (body,hatch,funnels):
    bm=bmesh.new();bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm,faces=list(bm.faces),quad_method='BEAUTY',ngon_method='BEAUTY')
    bm.to_mesh(obj.data);bm.free();obj.data.update()
    assert not obj.data.validate(verbose=False)

reference=bpy.data.objects.new('HeadHeightReference',None);reference.location=(0,0,22);scene.collection.objects.link(reference)
reference['basis']='Top of original white central helmet crest Plane.003; excludes yellow V antenna and fin-funnels.'
reference['source_feet_z']=surface_floor;reference['source_head_z']=crown_z;reference['uniform_scale']=scale
body['source']='Ryanwill679 / TrashCG / Sketchfab / CC BY 4.0'
body['source_url']='https://sketchfab.com/3d-models/rx-93-nu-gundam-85c329a2565043c58999afd43506c9a9'
body['geometry_source']='Original FBX; platform GLB fin-funnel geometry rejected.'
body['head_height_m']=22.0;body['game_front']='-Z'
for obj in scene.objects:obj.select_set(obj in (body,hatch,funnels,reference))
bpy.context.view_layer.objects.active=body
bpy.data.orphans_purge(do_local_ids=True,do_linked_ids=True,do_recursive=True)
bpy.ops.export_scene.gltf(filepath=str(TARGET),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_animations=False,export_skins=False,export_cameras=False,export_lights=False,export_extras=True,export_materials='EXPORT')

# Reimport the actual delivery, not the pre-export scene, for measurements and
# CPU preview. The preserved original FBX and GLB are never saved over.
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(TARGET))
scene=bpy.context.scene
meshes=[o for o in scene.objects if o.type=='MESH']
all_points=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
minimum=[min(v[i] for v in all_points) for i in range(3)]
maximum=[max(v[i] for v in all_points) for i in range(3)]
assert abs(minimum[2])<.0002
assert abs(bpy.data.objects['HeadHeightReference'].matrix_world.translation.z-22)<.0002
funnels=bpy.data.objects['FinFunnels'];assert len(funnels.data.vertices)>10000
wing_points=[funnels.matrix_world@v.co for v in funnels.data.vertices]
wing_bounds=[[min(v[i] for v in wing_points) for i in range(3)],[max(v[i] for v in wing_points) for i in range(3)]]
assert 5<wing_bounds[1][2]-wing_bounds[0][2]<30
conversion_report={'status':'exported_and_reimport_verified','source_fbx_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'source_zip_sha256':'a2fdfe58a258fa9574fda3b1bf01a857606925aec3de31defddfaf41dddd350a','target':str(TARGET),'target_bytes':TARGET.stat().st_size,'target_sha256':hashlib.sha256(TARGET.read_bytes()).hexdigest(),'source_feet_z':surface_floor,'source_crown_z':crown_z,'uniform_scale':scale,'center_xy':[center_x,center_y],'head_height_m':22,'loose_unrendered_vertices_removed':loose_removed,'bounds_blender':[minimum,maximum],'fin_funnels_bounds_blender':wing_bounds,'material_mapping':material_map,'material_source':'Same author platform GLB validated PBR graphs with 2K base/normal and 1K metallic/roughness; static geometry exclusively original FBX.','cavity_removed_faces':{'narrow':removed_narrow,'interior':removed_inner},'cavity_bounds_blender':{'narrow':cavity_narrow,'interior':cavity_inner},'hatch_pivot_godot':[0,hatch_top,-2.96],'suggested_cockpit':{'floor_y':16.04,'portal_z':-3.35,'interior_front_z':-1.45,'rear_z':.55,'seat_offset_z':-.20,'screen_z':-1.1,'hatch_travel':.15,'hatch_angle':120,'docking_width':.73,'entry_half_width':.06,'wait_z':-6.1,'gate_z':-5.7},'note':'Doorway is a narrow central passage; the full-sized cockpit widens behind side vent units.'}
conversion_report['suggested_cockpit'].update({'seat_offset_z':-.60,'console_offset_z':.15,'console_x':.48,'screen_side_x':.35,'fold_yaw':0})
conversion_report['suggested_cockpit'].update({'seat_offset_z': -.60, 'console_offset_z': .15, 'console_x': .48, 'screen_side_x': .35, 'screen_fold_yaw_zero': True, 'screen_fold_height': 1.96})
for obj in meshes:obj.data.calc_loop_triangles()
conversion_report['triangles']=sum(len(o.data.loop_triangles) for o in meshes)
conversion_report['pose']=pose_report
conversion_report['uv_conversion']='Flip UV.v to match the platform PBR texture payload: original FBX BaseColor images equal vertically flipped platform images; platform normal G is also inverted.'
conversion_report['meshes']=[{'name':o.name,'triangles':len(o.data.loop_triangles),'materials':len(o.data.materials)} for o in meshes]
(DERIVED/'fbx_conversion_report.json').write_text(json.dumps(conversion_report,ensure_ascii=False,indent=2),encoding='utf-8')
print('NU_ASSET_REIMPORT_VERIFIED',conversion_report['target_bytes'],conversion_report['triangles'],flush=True)

if args.render:
    # Studio context includes a 1.75 m human reference. This is a CPU asset
    # preview, not a captured game frame or a GPU-performance measurement.
    def material(name,color,emission=0):
        m=bpy.data.materials.new(name);m.use_nodes=True;p=m.node_tree.nodes['Principled BSDF'];p.inputs['Base Color'].default_value=color;p.inputs['Roughness'].default_value=.65
        if emission:p.inputs['Emission Color'].default_value=color;p.inputs['Emission Strength'].default_value=emission
        return m
    floor_mat=material('Studio floor',(.055,.065,.075,1))
    human_mat=material('Human reference suit',(.92,.35,.06,1))
    bpy.ops.mesh.primitive_plane_add(size=150);bpy.context.object.data.materials.append(floor_mat)
    def cube(name,location,dimensions,mat):
        bpy.ops.mesh.primitive_cube_add(size=1,location=location);o=bpy.context.object;o.name=name;o.dimensions=dimensions;o.data.materials.append(mat);return o
    cube('Human torso',(3.7,2.8,1.05),(.36,.21,.54),human_mat)
    cube('Human pelvis',(3.7,2.8,.72),(.32,.22,.18),human_mat)
    for side in (-1,1):
        cube('Human leg',(3.7+side*.11,2.8,.37),(.14,.15,.64),human_mat)
        cube('Human boot',(3.7+side*.11,2.89,.07),(.16,.30,.14),human_mat)
        cube('Human arm',(3.7+side*.25,2.8,1.0),(.12,.12,.58),human_mat)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,radius=1,location=(3.7,2.8,1.58));bpy.context.object.scale=(.13,.12,.17);bpy.context.object.data.materials.append(human_mat)
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=20;scene.render.threads_mode='FIXED';scene.render.threads=4
    scene.world=bpy.data.worlds.new('Studio world');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.22,.26,.33,1);scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.45
    target=Vector((0,0,14.3));bpy.ops.object.camera_add(location=(29,53,25));camera=bpy.context.object;camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=34;scene.camera=camera
    for loc,energy,size in [((5,18,35),18000,18),((-19,8,22),16000,16),((0,-15,30),24000,12)]:
        bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=energy;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(target-o.location).to_track_quat('-Z','Y').to_euler()
    scene.render.resolution_x=1100;scene.render.resolution_y=1280;scene.render.resolution_percentage=100;scene.view_settings.view_transform='AgX';scene.render.image_settings.file_format='PNG'
    scene.render.filepath=str(PREVIEW/'nu_complete_closed_cpu.png');bpy.ops.render.render(write_still=True)
    if args.open_preview:
        hatch=bpy.data.objects['CockpitHatch'];hatch.location.y+=.15;hatch.rotation_mode='XYZ';hatch.rotation_euler.x=math.radians(120)
        target=Vector((0,1.3,17.3));camera.location=(8,19,19.8);camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.ortho_scale=8
        scene.render.filepath=str(PREVIEW/'nu_open_hatch_cpu.png');bpy.ops.render.render(write_still=True)
    print('NU_CPU_PREVIEW_COMPLETE',flush=True)
