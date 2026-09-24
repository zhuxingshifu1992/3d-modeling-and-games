"""Audit original connected armor parts in adopted meter coordinates."""
import bpy,json
from pathlib import Path
from mathutils import Matrix,Vector
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'previews/refined_unicorn'
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=str(ROOT/'source/external/unicorn_sketchfab/author_source/UNICORN_GUNDAM_OBJ.obj'))
o=next(o for o in bpy.context.scene.objects if o.type=='MESH');mesh=o.data
mesh.transform(o.matrix_world);o.matrix_world=Matrix.Identity(4);mesh.update()
head_ids={i for p in mesh.polygons if mesh.materials[p.material_index].name in ['blinn1SG','blinn2SG','blinn4SG'] for i in p.vertices}
floor=min(v.co.z for v in mesh.vertices);landmark=max(mesh.vertices[i].co.z for i in head_ids)
scale=21.7/(landmark-floor);m=Matrix.Diagonal(Vector((-scale,-scale,scale,1)))@Matrix.Translation((0,0,-floor))
mesh.transform(m);mesh.update()
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
rows=[]
for key,ids in groups.items():
    pts=[mesh.vertices[i].co for i in ids];fids=faces.get(key,[])
    lo=[min(v[i] for v in pts) for i in range(3)];hi=[max(v[i] for v in pts) for i in range(3)]
    mats=sorted({mesh.materials[mesh.polygons[i].material_index].name for i in fids})
    rows.append({'component':key,'vertices':len(ids),'faces':len(fids),'bounds':[lo,hi],'materials':mats})
report={'source_floor':floor,'source_head_landmark':landmark,'scale':scale,'normalization':'(-x,-y,z), source z floor to head geometry top 21.7m','parts':sorted(rows,key=lambda x:(x['bounds'][0][2],x['component']))}
(OUT/'source_parts.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('PARTS',len(rows),'FLOOR_HEAD_SCALE',floor,landmark,scale)
for x in rows:
    lo,hi=x['bounds']
    if hi[2]>12 and lo[2]<18.5 and lo[0]>-2 and hi[0]<2 and hi[1]>.4:print('CENTRAL',json.dumps(x))
