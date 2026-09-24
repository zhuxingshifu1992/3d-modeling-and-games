"""Immutable kurojishi OBJ -> 21.7 m parked Destroy Mode with boarding hatch."""
from pathlib import Path
import bpy,bmesh,json,hashlib,sys
from mathutils import Matrix,Vector
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from unicorn_materials import configure_materials
BASE=ROOT/'source/external/unicorn_sketchfab';DERIVED=BASE/'derived';DERIVED.mkdir(parents=True,exist_ok=True)
SOURCE=BASE/'author_source/UNICORN_GUNDAM_OBJ.obj';TARGET=ROOT/'assets/models/unicorn_refined.glb'
SOURCE_HASH='90aa3a9ed97bd7b7a0722b4ea70b99197821be974e167e044514950d5e8e785b'
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==SOURCE_HASH
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=str(SOURCE),use_split_objects=True,use_split_groups=False)
scene=bpy.context.scene;body=next(o for o in scene.objects if o.type=='MESH');mesh=body.data
assert len(mesh.polygons)==189593 and len(mesh.vertices)==198660
# Source audit confirms only these three mirrored left head-armor shells are
# reversed. Preserve the author's correct custom normals by corner identity.
bad_faces=set(range(6566,7175));old_normals=[tuple(n.vector) for n in mesh.corner_normals]
corners={i:{mesh.loops[l].vertex_index:old_normals[l] for l in mesh.polygons[i].loop_indices} for i in bad_faces}
uvs={i:{mesh.loops[l].vertex_index:tuple(mesh.uv_layers.active.data[l].uv) for l in mesh.polygons[i].loop_indices} for i in bad_faces}
assert all(mesh.materials[mesh.polygons[i].material_index].name=='blinn1SG' for i in bad_faces)
for i in sorted(bad_faces):mesh.polygons[i].flip()
mesh.update();restore=list(old_normals)
for i in bad_faces:
    for l in mesh.polygons[i].loop_indices:
        restore[l]=corners[i][mesh.loops[l].vertex_index]
        assert tuple(mesh.uv_layers.active.data[l].uv)==uvs[i][mesh.loops[l].vertex_index]
mesh.normals_split_custom_set(restore);mesh.update()
assert all(sum(mesh.polygons[i].normal.dot(mesh.corner_normals[l].vector) for l in mesh.polygons[i].loop_indices)>0 for i in bad_faces)
head_ids={i for p in mesh.polygons if mesh.materials[p.material_index].name in ['blinn1SG','blinn2SG','blinn4SG'] for i in p.vertices}
points=[body.matrix_world@v.co for v in mesh.vertices]
floor=min(v.z for v in points);landmark=max(points[i].z for i in head_ids);scale=21.7/(landmark-floor)
normalization=Matrix.Diagonal(Vector((-scale,-scale,scale,1)))@Matrix.Translation((0,0,-floor))
mesh.transform(normalization@body.matrix_world);body.matrix_world=Matrix.Identity(4);mesh.update()
# Connected authored components are identified before any topology edits.
parent=list(range(len(mesh.vertices)))
def find(i):
    while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
    return i
def union(a,b):
    a=find(a);b=find(b)
    if a!=b:parent[b]=a
positions={}
for v in mesh.vertices:
    key=tuple(round(c,5) for c in v.co)
    if key in positions:union(v.index,positions[key])
    else:positions[key]=v.index
for edge in mesh.edges:union(*edge.vertices)
groups={}
for v in mesh.vertices:groups.setdefault(find(v.index),[]).append(v.index)
faces={}
for p in mesh.polygons:faces.setdefault(find(p.vertices[0]),[]).append(p.index)
hatch_faces=set();parts=[]
for key,ids in groups.items():
    pts=[mesh.vertices[i].co for i in ids];lo=[min(v[a] for v in pts) for a in range(3)];hi=[max(v[a] for v in pts) for a in range(3)]
    fids=faces.get(key,[]);mats={mesh.materials[mesh.polygons[i].material_index].name for i in fids}
    if mats and mats<={'blinn5SG','blinn7SG'} and lo[0]>-.85 and hi[0]<.85 and lo[1]>.78 and lo[2]>15.30 and hi[2]<17.82:
        hatch_faces.update(fids);parts.append({'component':key,'bounds':[lo,hi],'faces':len(fids),'materials':sorted(mats)})
assert 2000<len(hatch_faces)<5000,(len(hatch_faces),parts)
material_report=configure_materials(objects=[body])
hatch=body.copy();hatch.data=mesh.copy();hatch.name='CockpitHatch';scene.collection.objects.link(hatch)
def retain_faces(obj,keep):
    bm=bmesh.new();bm.from_mesh(obj.data);bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.index not in keep],context='FACES')
    bm.to_mesh(obj.data);bm.free();obj.data.update()
retain_faces(hatch,hatch_faces);retain_faces(body,set(range(len(mesh.polygons)))-hatch_faces);body.name='UnicornBody'
def clear_volume(obj,lower,upper):
    bm=bmesh.new();bm.from_mesh(obj.data)
    for axis in range(3):
        n=Vector((0,0,0));n[axis]=1
        for bound in [lower[axis],upper[axis]]:
            p=Vector((0,0,0));p[axis]=bound
            bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-6,plane_co=p,plane_no=n,clear_inner=False,clear_outer=False)
    discard=[f for f in bm.faces if all(lower[i]-1e-5<=f.calc_center_median()[i]<=upper[i]+1e-5 for i in range(3))]
    count=len(discard);bmesh.ops.delete(bm,geom=discard,context='FACES');bm.to_mesh(obj.data);bm.free();obj.data.update();return count
volumes={'entry':[(-.43,.90,15.37),(.43,2.55,17.41)],'interior':[(-.66,-1.13,15.37),(.66,.90,17.41)],
         # The source chest is a static interlocking assembly. Recess only the
         # central hatch travel envelope to release its rear/side overlaps.
         'sliding_cover_recess':[(-.83,.75,15.29),(.83,3.85,17.85)]}
counts={key:clear_volume(body,*box) for key,box in volumes.items()}
hinge=Vector((0,.78,17.83))
for v in hatch.data.vertices:v.co-=hinge
hatch.location=hinge
for obj in [body,hatch]:
    bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.triangulate(bm,faces=list(bm.faces))
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
    bm.to_mesh(obj.data);bm.free();obj.data.update();assert not obj.data.validate()
marker=bpy.data.objects.new('TotalHeightReference',None);scene.collection.objects.link(marker);marker.location=(0,0,21.7)
marker['basis']='Official Destroy Mode total height 21.7m; sole-to-authored-helmet-antenna is game calibration, official endpoint unspecified.'
body['source']='kurojishi / Gundam Unicorn / CC BY-NC 4.0';body['source_url']='https://sketchfab.com/3d-models/gundam-unicorn-1410ff9dd1c94807a00b8a0936170196'
hatch['adaptation']='Original central chest armor and fittings; slide and raise for human boarding, game adaptation rather than verified official mechanism.'
profile={'floor_y':15.25,'portal_z':-2.45,'bridge_end_z':-4.87,'interior_front_z':-.88,'rear_z':1.05,'seat_offset_z':-.18,'screen_z':-.50,'wait_z':-5.23,'gate_z':-4.87,
         'console_offset_z':.30,'console_x':.48,'screen_side_x':.35,'screen_fold_yaw_zero':True,'screen_fold_height':1.96,'hatch_travel':1.35,'hatch_angle':90.0,'docking_width':.73,'entry_half_width':.06,
         'head_clearance_min_y':18.55,'head_clearance_max_y':21.75,'head_clearance_half_width':1.9,'head_clearance_min_z':-1.65,'head_clearance_max_z':1.65,
         'clearance_entry_min_z':-2.30,'clearance_entry_max_z':-.90}
bpy.ops.object.select_all(action='SELECT');bpy.context.view_layer.objects.active=body
bpy.ops.export_scene.gltf(filepath=str(TARGET),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_animations=False,export_skins=False,export_cameras=False,export_lights=False,export_extras=True)
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(TARGET))
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];pts=[o.matrix_world@v.co for o in meshes for v in o.data.vertices]
lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
for o in meshes:o.data.calc_loop_triangles()
assert abs(lo[2])<.001 and abs(hi[2]-21.7)<.025
report={'status':'exported_reimport_verified','source_obj_sha256':SOURCE_HASH,'target_sha256':hashlib.sha256(TARGET.read_bytes()).hexdigest(),'target_bytes':TARGET.stat().st_size,
        'source_triangles':377328,'triangles':sum(len(o.data.loop_triangles) for o in meshes),'scale':scale,'source_floor':floor,'source_head_landmark':landmark,
        'total_height_reference_m':21.7,'calibration_convention':'sole to authored helmet antenna, game convention; official total-height endpoint unspecified',
        'bounds_blender':[lo,hi],'normal_fix':{'source_face_range_inclusive':[6566,7174],'faces':609,'uv_preserved':True,'custom_normals_preserved_by_corner_identity':True,'full_audit':'previews/refined_unicorn/normals_geometry_audit.json'},
        'hatch_parts':parts,'source_hatch_face_count':len(hatch_faces),'hatch_pivot_godot':[0,17.83,-.78],'cavity_bounds_blender':volumes,'cavity_removed_faces':counts,'suggested_cockpit':profile,
        'materials_report':'source/external/unicorn_sketchfab/derived/materials_manifest.json','material_module_sha256':hashlib.sha256((ROOT/'tools/unicorn_materials.py').read_bytes()).hexdigest(),
        'meshes':[{'name':o.name,'triangles':len(o.data.loop_triangles),'surfaces':len(o.data.materials)} for o in meshes]}
(DERIVED/'conversion_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('UNICORN_EXPORTED',report['target_bytes'],report['triangles'],report['target_sha256'],'BOUNDS',lo,hi,flush=True)
