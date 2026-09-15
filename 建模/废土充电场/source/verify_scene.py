"""Fresh artifact audit: native geometry, references, packed dependencies, and GLB."""
import bpy,sys,json,struct,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'废土充电场.blend'))
scene=bpy.context.scene
missing=[];unpacked=[]
for im in bpy.data.images:
    if im.source=='FILE' and not im.packed_file:
        unpacked.append(im.name)
        if not Path(bpy.path.abspath(im.filepath)).exists():missing.append(im.filepath)
for fo in bpy.data.fonts:
    if fo.filepath and fo.filepath!='<builtin>' and not fo.packed_file:unpacked.append('FONT '+fo.name)
invalid=[]
for ob in scene.objects:
    if ob.type=='MESH':
        for v in ob.data.vertices:
            if not all(math.isfinite(a) for a in v.co):invalid.append(ob.name);break
assert not missing,missing
assert not unpacked,unpacked
assert not invalid,invalid
assert len([o for o in scene.objects if o.type=='CAMERA'])>=5
assert not list((ROOT/'assets'/'reference').glob('ref_*.jpg'))
assert not any(i.name.startswith('ref_') for i in bpy.data.images)
glb=ROOT/'exports'/'废土充电场.glb'
with glb.open('rb') as f:
    magic,version,total=struct.unpack('<4sII',f.read(12));n,kind=struct.unpack('<II',f.read(8));doc=json.loads(f.read(n))
assert magic==b'glTF' and version==2 and total==glb.stat().st_size
assert len(doc.get('meshes',[]))>0
assert not any('uri' in im and not im['uri'].startswith('data:') for im in doc.get('images',[]))
native={'objects':len(scene.objects),'mesh_objects':sum(o.type=='MESH' for o in scene.objects),'faces':sum(len(o.data.polygons) for o in scene.objects if o.type=='MESH')}
report={'native':native,'packed_images':sum(bool(i.packed_file) for i in bpy.data.images),'missing_resources':missing,'unpacked_resources':unpacked,'invalid_geometry':invalid,'glb_bytes':total,'glb_meshes':len(doc['meshes']),'glb_materials':len(doc.get('materials',[])),'glb_embedded_images':len(doc.get('images',[])),'renders':[p.name for p in (ROOT/'renders').glob('*.png') if 'draft' not in p.name and 'probe' not in p.name]}
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(glb))
report['glb_reimport_meshes']=sum(o.type=='MESH' for o in bpy.context.scene.objects)
assert report['glb_reimport_meshes']>0
(ROOT/'docs'/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('VERIFICATION_OK',json.dumps(report,ensure_ascii=False),flush=True)
