"""Reproducible K0077 GLB adaptation; immutable source, background Blender only."""
import bpy,bmesh,json,hashlib,math
from pathlib import Path
from mathutils import Matrix,Vector
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'source/external/strike_freedom_sketchfab';DERIVED=BASE/'derived';DERIVED.mkdir(parents=True,exist_ok=True)
SOURCE=BASE/'strike_freedom_gundam_2k.glb';TARGET=ROOT/'assets/models/freedom_refined.glb'
SOURCE_HASH='80815c3dc77ab86ac28bde2352e4e73991094c6e6a5628df5cc94e3ed5566b04'
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==SOURCE_HASH
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE));scene=bpy.context.scene
objects=[o for o in scene.objects if o.type=='MESH']
floor=min((o.matrix_world@v.co).z for o in objects for v in o.data.vertices)
head=bpy.data.objects['Object_4'];landmark=max((head.matrix_world@v.co).z for v in head.data.vertices)
scale=18.88/(landmark-floor)
normalization=Matrix.Diagonal(Vector((-scale,-scale,scale,1)))@Matrix.Translation((-2955.30,80,-floor))
for o in objects:
    o.data=o.data.copy();m=normalization@o.matrix_world;o.parent=None;o.matrix_world=Matrix.Identity(4);o.data.transform(m);o.data.update()
# Source contains two overlapping left-arm meshes. Verify topology, UVs and
# sub-millimeter position equivalence before omitting exactly one copy.
a=bpy.data.objects['Object_11'];b=bpy.data.objects['Object_12']
assert len(a.data.vertices)==len(b.data.vertices)
assert [tuple(p.vertices) for p in a.data.polygons]==[tuple(p.vertices) for p in b.data.polygons]
arm_delta=max((v.co-w.co).length for v,w in zip(a.data.vertices,b.data.vertices))
assert arm_delta<.0004
assert all((u.uv-v.uv).length<1e-7 for la,lb in zip(a.data.uv_layers,b.data.uv_layers) for u,v in zip(la.data,lb.data))
bpy.data.objects.remove(b,do_unlink=True)
chest=bpy.data.objects['Object_3'];mesh=chest.data
# Resolve authored connected parts through split UV vertices without welding
# the exported mesh, then separate the complete central front pieces.
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
selected=set();parts=[]
for ids in groups.values():
    pts=[mesh.vertices[i].co for i in ids]
    lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
    if lo[0]>-.60 and hi[0]<.60 and lo[1]>.85:
        selected.update(ids);parts.append({'bounds':[lo,hi],'vertices':len(ids)})
hatch_faces={p.index for p in mesh.polygons if all(i in selected for i in p.vertices)}
assert 900<len(hatch_faces)<2500,(len(hatch_faces),parts)
hatch=chest.copy();hatch.data=chest.data.copy();hatch.name='CockpitHatch';scene.collection.objects.link(hatch)
def retain_faces(o,keep):
    bm=bmesh.new();bm.from_mesh(o.data);bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.index not in keep],context='FACES')
    bm.to_mesh(o.data);bm.free();o.data.update()
retain_faces(hatch,hatch_faces);retain_faces(chest,set(range(len(mesh.polygons)))-hatch_faces)
# Keep the lower abdominal plates fixed: moving the complete merged source
# front assembly would sweep through the waist armor below the pilot doorway.
lower_panel=hatch.copy();lower_panel.data=hatch.data.copy();lower_panel.name='FixedAbdominalPanels';scene.collection.objects.link(lower_panel)
for piece,keep_upper in [(hatch,True),(lower_panel,False)]:
    bm=bmesh.new();bm.from_mesh(piece.data)
    bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=1e-6,plane_co=(0,0,13.80),plane_no=(0,0,1),clear_inner=False,clear_outer=False)
    discard=[f for f in bm.faces if (f.calc_center_median().z<13.80-1e-5 if keep_upper else f.calc_center_median().z>13.80+1e-5)]
    bmesh.ops.delete(bm,geom=discard,context='FACES');bm.to_mesh(piece.data);bm.free();piece.data.update()
bpy.ops.object.select_all(action='DESELECT')
rest=[o for o in scene.objects if o.type=='MESH' and o!=hatch]
for o in rest:o.select_set(True)
bpy.context.view_layer.objects.active=chest;bpy.ops.object.join();body=chest;body.name='FreedomBody'
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
    count=len(faces);bmesh.ops.delete(bm,geom=faces,context='FACES');bm.to_mesh(obj.data);bm.free();obj.data.update();return count
volumes={'entry':[(-.43,.90,13.87),(.43,3.25,15.91)],'interior':[(-.66,-1.13,13.87),(.66,.90,15.91)],
         # Original merged cover side flanges overlap adjacent source chest
         # structure. A 4 cm side recess clears the forward sliding stroke,
         # including the lower seam, instead of exempting that phase in tests.
         'sliding_cover_recess':[(-.61,.84,13.78),(.61,4.56,16.05)]}
counts={k:clear_volume(body,*v) for k,v in volumes.items()}
hinge=Vector((0,.90,16.05))
for v in hatch.data.vertices:v.co-=hinge
hatch.location=hinge
hatch['adaptation']='Original central chest parts: forward disengagement then raised cover for human boarding; game adaptation, not an exact MGEX mechanism.'
for o in [body,hatch]:
    bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.triangulate(bm,faces=list(bm.faces));bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS');bm.to_mesh(o.data);bm.free();o.data.update();assert not o.data.validate()
marker=bpy.data.objects.new('TotalHeightReference',None);scene.collection.objects.link(marker);marker.location=(0,0,18.88)
marker['basis']='Official TOTAL HEIGHT 18.88m; game calibration convention is authored sole to helmet antenna tip. Wing equipment bounds measured separately; official endpoint not specified.'
body['source']='K0077 / Sketchfab / CC BY 4.0';body['source_url']='https://sketchfab.com/3d-models/strike-freedom-gundam-0d5a236cdb164c5094a8d296d9352943';body['game_front']='-Z'
profile={'floor_y':13.75,'portal_z':-3.12,'bridge_end_z':-5.40,'interior_front_z':-.88,'rear_z':1.05,'seat_offset_z':-.18,'screen_z':-.50,'wait_z':-5.76,'gate_z':-5.40,
         'console_offset_z':.30,'console_x':.48,'screen_side_x':.35,'screen_fold_yaw_zero':True,'screen_fold_height':1.96,'hatch_travel':1.40,'hatch_angle':90.0,'docking_width':.73,'entry_half_width':.06,
         'head_clearance_min_y':15.95,'head_clearance_max_y':18.90,'head_clearance_half_width':1.70,'head_clearance_min_z':-1.35,'head_clearance_max_z':1.15,'clearance_entry_min_z':-2.90,'clearance_entry_max_z':-.90}
for o in scene.objects:o.select_set(True)
bpy.context.view_layer.objects.active=body
bpy.ops.export_scene.gltf(filepath=str(TARGET),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_animations=False,export_skins=False,export_cameras=False,export_lights=False,export_extras=True)
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(TARGET));meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
pts=[o.matrix_world@v.co for o in meshes for v in o.data.vertices];lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
assert abs(lo[2])<.0002
for o in meshes:o.data.calc_loop_triangles()
report={'status':'exported_reimport_verified','source_sha256':SOURCE_HASH,'target_sha256':hashlib.sha256(TARGET.read_bytes()).hexdigest(),'target_bytes':TARGET.stat().st_size,'scale':scale,'source_floor':floor,'source_body_landmark':landmark,
        'total_height_reference_m':18.88,'calibration_convention':'sole to authored helmet antenna; not asserted as official endpoint','equipped_bounds_blender':[lo,hi],
        'triangles':sum(len(o.data.loop_triangles) for o in meshes),'removed_overlap_object':'Object_12','overlap_max_vertex_distance_m':arm_delta,'source_hatch_components':parts,'source_hatch_face_count':len(hatch_faces),
        'cavity_bounds_blender':volumes,'cavity_removed_faces':counts,'fixed_abdominal_below_y_m':13.80,'hatch_pivot_godot':[0,16.05,-.90],'suggested_cockpit':profile,
        'meshes':[{'name':o.name,'triangles':len(o.data.loop_triangles),'surfaces':len(o.data.materials)} for o in meshes]}
(DERIVED/'conversion_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('FREEDOM_EXPORTED',report['target_bytes'],report['triangles'],report['target_sha256'],'BOUNDS',lo,hi,flush=True)
