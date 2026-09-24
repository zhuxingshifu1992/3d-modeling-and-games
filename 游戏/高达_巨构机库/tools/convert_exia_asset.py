"""Reproducible Exia conversion. Run only in background Blender, CPU rendering.

The acquired original is immutable. The game adaptation retains source armor,
vertex colors and emission, separates the existing central hatch, and clears
only the central internal entry volume for a full-sized pilot.
"""
from pathlib import Path
import argparse, hashlib, json, math, sys
import bpy, bmesh
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'source/external/exia_sketchfab'
SOURCE=BASE/'original/source/Untitled.glb'
DERIVED=BASE/'derived'
OUT=ROOT/'previews/refined_exia'
TARGET=ROOT/'assets/models/exia_refined.glb'
SOURCE_HASH='50d18230471b7704b846d43c0106852ecf99f64e386d50d4a9304edbd807e0c7'
parser=argparse.ArgumentParser()
parser.add_argument('--render',action='store_true')
parser.add_argument('--open-preview',action='store_true')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
for d in [DERIVED,OUT]:d.mkdir(parents=True,exist_ok=True)
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==SOURCE_HASH
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
scene=bpy.context.scene
original=[o for o in scene.objects if o.type=='MESH']
points=[o.matrix_world@o.data.vertices[i].co for o in original for i in set(v for p in o.data.polygons for v in p.vertices)]
floor=min(v.z for v in points);top=max(v.z for v in points)
scale=18.3/(top-floor)
normalization=Matrix.Diagonal(Vector((-scale,-scale,scale,1)))@Matrix.Translation((0,0,-floor))
names=['Sphere.028','Sphere.027','Sphere.025','Sphere.071','Sphere.074','Sphere.031','Sphere.037']
assert all(bpy.data.objects.get(n) is not None for n in names)
source_vertex_layers=set()
for o in original:
    o.data=o.data.copy()
    matrix=normalization@o.matrix_world
    o.parent=None;o.matrix_world=Matrix.Identity(4)
    o.data.transform(matrix);o.data.update()
    # Keep an identical color-layer layout when joining: missing color attributes
    # must be white, otherwise previously uncolored armor can become black.
    for layer in o.data.color_attributes:source_vertex_layers.add(layer.name)
for o in original:
    for name in sorted(source_vertex_layers):
        if name not in o.data.color_attributes:
            layer=o.data.color_attributes.new(name=name,type='FLOAT_COLOR',domain='CORNER')
            layer.data.foreach_set('color',[1.0]*(len(layer.data)*4))
    if 'Color' in o.data.color_attributes:
        o.data.color_attributes.active_color=o.data.color_attributes['Color']
        o.data.color_attributes.render_color_index=list(o.data.color_attributes).index(o.data.color_attributes['Color'])

# The authored miniature chair is retained in the original; the playable cabin
# uses the game's full-size seat and controls, so it must not be embedded twice.
removed=[]
chair=bpy.data.objects.get('Cockpit Chair.002')
if chair is not None:removed.append(chair.name);bpy.data.objects.remove(chair,do_unlink=True)
def join_parts(parts,name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:o.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    bpy.ops.object.join();o=parts[0];o.name=name
    return o
hatch=join_parts([bpy.data.objects[n] for n in names],'CockpitHatch')
body=join_parts([o for o in scene.objects if o.type=='MESH' and o!=hatch],'ExiaBody')
for o in list(scene.objects):
    if o not in [body,hatch]:bpy.data.objects.remove(o,do_unlink=True)

def clear_volume(obj,lower,upper):
    bm=bmesh.new();bm.from_mesh(obj.data)
    for axis in range(3):
        n=Vector((0,0,0));n[axis]=1
        for bound in [lower[axis],upper[axis]]:
            p=Vector((0,0,0));p[axis]=bound
            bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-6,plane_co=p,plane_no=n,clear_inner=False,clear_outer=False)
    faces=[f for f in bm.faces if all(lower[i]-1e-5<=f.calc_center_median()[i]<=upper[i]+1e-5 for i in range(3))]
    count=len(faces);bmesh.ops.delete(bm,geom=faces,context='FACES')
    bm.to_mesh(obj.data);bm.free();obj.data.update()
    return count

profile={'floor_y':12.08,'portal_z':-2.30,'bridge_end_z':-4.70,'interior_front_z':-.85,'rear_z':1.0,
         'seat_offset_z':-.18,'screen_z':-.45,'wait_z':-5.05,'gate_z':-4.70,
         'console_offset_z':.30,'console_x':.48,'screen_side_x':.35,
         'screen_fold_yaw_zero':True,'screen_fold_height':1.96,
         'hatch_travel':1.30,'hatch_angle':-100.0,'docking_width':.73,'entry_half_width':.06,
         'head_clearance_min_y':15.74,'head_clearance_max_y':18.35,'head_clearance_half_width':1.7,
         'head_clearance_min_z':-1.70,'head_clearance_max_z':1.20,
         'clearance_entry_min_z':-2.0,'clearance_entry_max_z':-.90}
narrow=[(-.40,.84,12.18),(.40,2.4,14.10)]
inner=[(-.62,-1.05,12.18),(.62,.84,14.19)]
counts={'narrow':clear_volume(body,*narrow),'inner':clear_volume(body,*inner)}
hinge=Vector((0,.60,12.10))
for v in hatch.data.vertices:v.co-=hinge
hatch.location=hinge
hatch['role']='Original central abdominal hatch parts; game hinge lowers forward after an outward slide.'
for o in [body,hatch]:
    bm=bmesh.new();bm.from_mesh(o.data)
    bmesh.ops.triangulate(bm,faces=list(bm.faces),quad_method='BEAUTY',ngon_method='BEAUTY')
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
    bm.to_mesh(o.data);bm.free();o.data.update()
    assert not o.data.validate(verbose=False)
reference=bpy.data.objects.new('TotalHeightReference',None);scene.collection.objects.link(reference)
reference.location=(0,0,18.3);reference['basis']='Bandai GN-001 specification TOTAL HEIGHT 18.3m; top of complete authored helmet, not a head-height assumption.'
body['source']='yqms / Sketchfab / CC BY 4.0'
body['source_url']='https://sketchfab.com/3d-models/gundam-exia-de3a7fec6d9347108720e0e816c40985'
body['variant_note']='PG-style author model, parked without handheld weapons; exact original authorship unconfirmed.'
body['total_height_m']=18.3;body['game_front']='-Z'
for o in scene.objects:o.select_set(o in [body,hatch,reference])
bpy.context.view_layer.objects.active=body
bpy.ops.export_scene.gltf(filepath=str(TARGET),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_animations=False,export_skins=False,export_cameras=False,export_lights=False,export_extras=True,export_materials='EXPORT')

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(TARGET));scene=bpy.context.scene
body=bpy.data.objects['ExiaBody'];hatch=bpy.data.objects['CockpitHatch']
meshes=[o for o in scene.objects if o.type=='MESH']
points=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
minimum=[min(v[i] for v in points) for i in range(3)]
maximum=[max(v[i] for v in points) for i in range(3)]
assert abs(minimum[2])<.0002 and abs(maximum[2]-18.3)<.0002
for o in meshes:o.data.calc_loop_triangles()
report={'status':'exported_reimport_verified','source_sha256':SOURCE_HASH,'target_sha256':hashlib.sha256(TARGET.read_bytes()).hexdigest(),
        'target_bytes':TARGET.stat().st_size,'total_height_m':18.3,'source_floor':floor,'source_top':top,'scale':scale,
        'bounds_blender':[minimum,maximum],'triangles':sum(len(o.data.loop_triangles) for o in meshes),
        'source_hatch_parts':names,'removed_source_objects':removed,'cavity_removed_faces':counts,
        'cavity_bounds_blender':{'narrow':narrow,'inner':inner},'hatch_pivot_godot':[0,12.10,-.60],
        'suggested_cockpit':profile,'vertex_color_layers':sorted(source_vertex_layers),
        'meshes':[{'name':o.name,'triangles':len(o.data.loop_triangles),'surfaces':len(o.data.materials)} for o in meshes]}
(DERIVED/'conversion_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('EXIA_ASSET_EXPORTED',report['target_bytes'],report['triangles'],report['target_sha256'],flush=True)

if args.render:
    def mat(name,color):
        m=bpy.data.materials.new(name);m.use_nodes=True
        p=m.node_tree.nodes['Principled BSDF'];p.inputs['Base Color'].default_value=color;p.inputs['Roughness'].default_value=.65
        return m
    def cube(name,at,size,material):
        bpy.ops.mesh.primitive_cube_add(size=1,location=at);o=bpy.context.object;o.name=name;o.dimensions=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(material);return o
    floor_mat=mat('StudioFloor',(.045,.065,.085,1));cube('StudioFloor',(0,0,-.13),(70,70,.25),floor_mat)
    suit=mat('HumanScaleOrange',(.9,.23,.035,1));dark=mat('HumanScaleDark',(.025,.035,.045,1))
    cube('HumanTorso',(3.6,4,1.1),(.44,.26,.60),suit)
    for x in [3.48,3.72]:cube('HumanLeg',(x,4,.43),(.16,.19,.86),dark)
    for x in [3.31,3.89]:cube('HumanArm',(x,4,1.10),(.13,.15,.65),suit)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,radius=1,location=(3.6,4,1.58));o=bpy.context.object;o.scale=(.145,.145,.17);o.data.materials.append(suit)
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=16;scene.cycles.use_denoising=True;scene.render.threads_mode='FIXED';scene.render.threads=4
    scene.world=bpy.data.worlds.new('CPUStudio');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.13,.17,.22,1);scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.5
    def aim(o,t):o.rotation_euler=(Vector(t)-o.location).to_track_quat('-Z','Y').to_euler()
    for loc,energy,size in [((-12,18,25),13000,12),((14,10,14),8500,10),((-5,-15,22),14000,10)]:
        bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=energy;o.data.shape='DISK';o.data.size=size;aim(o,(0,0,10))
    bpy.ops.object.camera_add(location=(-23,42,21));camera=bpy.context.object;scene.camera=camera;camera.data.type='ORTHO';camera.data.ortho_scale=22;aim(camera,(0,0,9.5))
    scene.render.resolution_x=935;scene.render.resolution_y=1100;scene.render.resolution_percentage=100;scene.view_settings.view_transform='AgX';scene.render.image_settings.file_format='PNG'
    scene.render.filepath=str(OUT/'exia_complete_closed_cpu.png');bpy.ops.render.render(write_still=True)
    if args.open_preview:
        hatch.location.y+=profile['hatch_travel'];hatch.rotation_mode='XYZ';hatch.rotation_euler.x=math.radians(profile['hatch_angle'])
        camera.location=(-4.2,13,15.1);aim(camera,(0,.25,13.2));camera.data.ortho_scale=6.2
        scene.render.filepath=str(OUT/'exia_open_hatch_cpu.png');bpy.ops.render.render(write_still=True)
