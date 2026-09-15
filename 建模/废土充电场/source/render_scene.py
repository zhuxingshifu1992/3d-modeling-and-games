import bpy,sys,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'废土充电场.blend'))
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else ['01_总览']
scene=bpy.context.scene
engine='CYCLES'
if '--eevee' in args:engine='BLENDER_EEVEE';args.remove('--eevee')
preview='--draft' in args
if preview:args.remove('--draft')
scene.render.engine=engine
scene.render.resolution_x=1000 if preview else 1920
scene.render.resolution_y=625 if preview else 1200
if engine=='CYCLES':scene.cycles.samples=12 if preview else 32;scene.cycles.use_denoising=True
for key in args:
    scene.camera=bpy.data.objects[key]
    scene.render.filepath=str(ROOT/'renders'/((key+'_draft' if preview else key)+'.png'))
    print('RENDER '+key,flush=True);bpy.ops.render.render(write_still=True)
print('RENDER COMPLETE',flush=True)
