"""Prepare exact clothing UV edit masks; does not modify the playable game.
Run with Blender --background --python tools/prepare_image_uv_inputs.py.
The black/white coverage is geometry data, not a generated visual asset.
"""
from pathlib import Path
import bpy
import hashlib
import json
import numpy as np
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'source/image_optimization'
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'source/rider/rider_realistic.blend'))
jobs = []
for name, texture, slug in [('CroppedCottonTee','CottonTee','cotton_tee'),('TailoredGreenShorts','GreenDenim','green_shorts')]:
    source = ROOT/'assets/rider_realistic'/f'rider_{texture}_albedo.png'
    original = OUT/f'{slug}_original.png'
    if not original.exists():shutil.copy2(source, original)
    assert hashlib.sha256(source.read_bytes()).digest() == hashlib.sha256(original.read_bytes()).digest()
    image=bpy.data.images.load(str(original));width,height=image.size
    mesh=bpy.data.objects[name].data;mesh.calc_loop_triangles();uvs=mesh.uv_layers.active.data
    coverage=np.zeros((height,width),dtype=bool)
    for triangle in mesh.loop_triangles:
        p=np.array([uvs[index].uv[:] for index in triangle.loops]) * np.array([width-1,height-1])
        x0,y0=np.maximum(np.floor(p.min(axis=0)).astype(int),0)
        x1,y1=np.minimum(np.ceil(p.max(axis=0)).astype(int),[width-1,height-1])
        if x1<x0 or y1<y0:continue
        y,x=np.mgrid[y0:y1+1,x0:x1+1];x=x+.5;y=y+.5
        area=(p[1,0]-p[0,0])*(p[2,1]-p[0,1])-(p[1,1]-p[0,1])*(p[2,0]-p[0,0])
        if abs(area)<1e-8:continue
        a=((p[1,0]-x)*(p[2,1]-y)-(p[1,1]-y)*(p[2,0]-x))/area
        b=((p[2,0]-x)*(p[0,1]-y)-(p[2,1]-y)*(p[0,0]-x))/area
        c=1-a-b
        coverage[y0:y1+1,x0:x1+1] |= (a>=-1e-5)&(b>=-1e-5)&(c>=-1e-5)
    # Extend eight texels around the UV islands to retain safe filtering gutters.
    for _ in range(8):
        padded=np.pad(coverage,1)
        coverage=(padded[1:-1,1:-1]|padded[:-2,1:-1]|padded[2:,1:-1]|padded[1:-1,:-2]|padded[1:-1,2:])
    mask=bpy.data.images.new(slug+'_edit_mask',width=width,height=height,alpha=True)
    rgba=np.ones((height,width,4),dtype=np.float32)
    rgba[:,:,3]=(~coverage).astype(np.float32)
    mask.pixels.foreach_set(rgba.ravel());mask.file_format='PNG';mask.filepath_raw=str(OUT/f'{slug}_edit_mask.png');mask.save()
    guide=bpy.data.images.new(slug+'_coverage',width=width,height=height,alpha=True)
    rgba[:,:,:3]=coverage[:,:,None].astype(np.float32);rgba[:,:,3]=1
    guide.pixels.foreach_set(rgba.ravel());guide.file_format='PNG';guide.filepath_raw=str(OUT/f'{slug}_coverage.png');guide.save()
    jobs.append({'id':slug,'object':name,'original':str(original),'mask':mask.filepath_raw,'coverage_fraction':float(coverage.mean()),'size':[width,height],'original_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'target_model':'gpt-image-2.5-sunburst-2026-09-08','status':'inputs_prepared_no_generation'})
(OUT/'jobs.json').write_text(json.dumps(jobs,ensure_ascii=False,indent=2),encoding='utf-8')
print('UV_EDIT_INPUTS_PREPARED',json.dumps(jobs,ensure_ascii=True))
