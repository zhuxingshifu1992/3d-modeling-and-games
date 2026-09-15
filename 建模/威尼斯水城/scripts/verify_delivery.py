"""Reopen verification and final deliverable inventory, run inside Blender."""
import json
from pathlib import Path
import struct
import hashlib
import bpy

out=Path(__file__).resolve().parent.parent
sc=bpy.context.scene
assert bpy.data.filepath, 'Open the saved .blend before verifying'
assert sc.camera and sc.camera.name.startswith('01'), 'Hero camera should be default'
assert sc.frame_start==1 and sc.frame_end==180 and sc.render.fps==24
meshes=[o for o in sc.objects if o.type=='MESH']
assert len(meshes)==5880, len(meshes)
assert len([o for o in sc.objects if o.type=='CAMERA'])==3
external=[i.filepath for i in bpy.data.images if i.source=='FILE' and not i.packed_file]
assert not external, external
previews=[]
hashes=set()
for name in ['预览_城市全景.png','预览_大运河.png','预览_广场.png']:
    path=out/name
    with path.open('rb') as f:header=f.read(24)
    assert header[:8]==b'\x89PNG\r\n\x1a\n',name
    width,height=struct.unpack('>II',header[16:24])
    assert (width,height)==(1800,1400),(name,width,height)
    previews.append({'file':name,'width':width,'height':height,'bytes':path.stat().st_size})
    hashes.add(hashlib.sha256(path.read_bytes()).hexdigest())
assert len(hashes)==3,'Each camera preview must be a different image'
for marker in sc.timeline_markers:marker.camera=None
sc.unit_settings.system='METRIC';sc.unit_settings.length_unit='METERS'
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath,compress=True)
report={'status':'PASS','blender':bpy.app.version_string,'objects':len(sc.objects),'meshes':len(meshes),'mesh_vertices':sum(len(o.data.vertices) for o in meshes),'materials':len(bpy.data.materials),'residential_buildings':len([o for o in sc.objects if o.type=='EMPTY' and o.name.startswith('House ')]),'cameras':[o.name for o in sc.objects if o.type=='CAMERA'],'external_images':external,'style':'Original stylized Venetian lagoon city','animation_frames':[1,180],'fps':24,'previews':previews,'blend_bytes':Path(bpy.data.filepath).stat().st_size}
(out/'scene_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('DELIVERY_VERIFIED',json.dumps(report,ensure_ascii=False),flush=True)
