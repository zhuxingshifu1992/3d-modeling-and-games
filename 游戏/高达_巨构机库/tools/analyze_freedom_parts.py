import bpy,bmesh,json,hashlib
from pathlib import Path
from mathutils import Matrix,Vector
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'previews/refined_freedom'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'source/external/strike_freedom_sketchfab/strike_freedom_gundam_2k.glb'))
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
floor=min((o.matrix_world@v.co).z for o in objects for v in o.data.vertices)
top=max((bpy.data.objects['Object_4'].matrix_world@v.co).z for v in bpy.data.objects['Object_4'].data.vertices)
scale=18.88/(top-floor)
normalization=Matrix.Diagonal(Vector((-scale,-scale,scale,1)))@Matrix.Translation((-2955.30,80,-floor))
for o in objects:
    m=normalization@o.matrix_world;o.parent=None;o.matrix_world=Matrix.Identity(4);o.data.transform(m)
def fingerprint(o):
    return hashlib.sha256(str(([(tuple(v.co),tuple(v.normal)) for v in o.data.vertices],[tuple(p.vertices) for p in o.data.polygons],[[tuple(u.uv) for u in l.data] for l in o.data.uv_layers])).encode()).hexdigest()
print('DUPLICATE_ARMS',fingerprint(bpy.data.objects['Object_11']),fingerprint(bpy.data.objects['Object_12']),flush=True)
o=bpy.data.objects['Object_3'];bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001)
unseen=set(bm.verts);records=[]
while unseen:
    first=unseen.pop();component={first};stack=[first]
    while stack:
        v=stack.pop()
        for e in v.link_edges:
            w=e.other_vert(v)
            if w in unseen:unseen.remove(w);component.add(w);stack.append(w)
    pts=[v.co for v in component];faces=set(f for v in component for f in v.link_faces)
    records.append({'vertices':len(component),'faces':len(faces),'bounds':[[min(v[i] for v in pts) for i in range(3)],[max(v[i] for v in pts) for i in range(3)]]})
bm.free();records.sort(key=lambda x:-x['faces'])
(OUT/'chest_components.json').write_text(json.dumps(records,indent=2))
print('CHEST_COMPONENTS',json.dumps(records[:60]),flush=True)
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12;scene.cycles.use_denoising=True
scene.render.threads_mode='FIXED';scene.render.threads=4
scene.world=bpy.data.worlds.new('Review');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.6
def aim(o,t):o.rotation_euler=(Vector(t)-o.location).to_track_quat('-Z','Y').to_euler()
for loc,energy in [((-5,12,20),5000),((7,10,16),3000)]:
    bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=energy;o.data.size=8;aim(o,(0,0,15))
bpy.ops.object.camera_add(location=(0,14,15));cam=bpy.context.object;scene.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=6.2;aim(cam,(0,0,15))
scene.render.resolution_x=900;scene.render.resolution_y=900;scene.render.resolution_percentage=100;scene.view_settings.view_transform='AgX'
scene.render.filepath=str(OUT/'source_chest_cpu.png');bpy.ops.render.render(write_still=True)
