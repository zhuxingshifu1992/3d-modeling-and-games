"""Render a saved city without rebuilding its geometry."""
import argparse
import json
from pathlib import Path
import sys
import bpy

args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
p=argparse.ArgumentParser()
p.add_argument('--width',type=int,default=1800)
p.add_argument('--height',type=int,default=1400)
p.add_argument('--samples',type=int,default=56)
p.add_argument('--views',type=int,default=2)
p.add_argument('--start-view',type=int,default=0)
p.add_argument('--save-settings',action='store_true')
opt=p.parse_args(args)
out=Path(__file__).resolve().parent.parent
sc=bpy.context.scene
assert len(sc.objects)>500,'Expected the generated city to be opened first'
sc.render.engine='CYCLES';sc.cycles.device='CPU';sc.cycles.samples=opt.samples;sc.cycles.use_denoising=True
sc.render.resolution_x=opt.width;sc.render.resolution_y=opt.height;sc.render.resolution_percentage=100
sc.render.threads_mode='FIXED';sc.render.threads=12
sc.frame_set(1)
for marker in sc.timeline_markers:marker.camera=None
cameras=sorted([o for o in sc.objects if o.type=='CAMERA'],key=lambda c:c.name)
names=['预览_城市全景.png','预览_大运河.png','预览_广场.png']
print('REOPEN_VALIDATED',json.dumps({'objects':len(sc.objects),'cameras':[o.name for o in cameras],'materials':len(bpy.data.materials)}),flush=True)
for i,cam in enumerate(cameras[:opt.views]):
    if i<opt.start_view:continue
    sc.camera=cam
    sc.render.filepath=str(out/names[i])
    print('RENDER_CAMERA',cam.name,flush=True)
    bpy.ops.render.render(write_still=True)
sc.camera=cameras[0]
if opt.save_settings:
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath,compress=True)
print('RENDER_COMPLETE',flush=True)
