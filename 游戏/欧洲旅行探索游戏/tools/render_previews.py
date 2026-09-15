"""Render actual Blender source views for visual inspection, without changing geometry."""
import bpy,sys,json,math
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'source/欧洲漫游_可进入建筑.blend'))
scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.samples=20;scene.cycles.use_denoising=True
scene.render.resolution_x=1280;scene.render.resolution_y=800;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.view_settings.view_transform='AgX'
scene.view_settings.exposure=.4
cam=scene.camera;cam.data.type='PERSP';cam.data.lens=35;cam.data.clip_end=2000
manifest=json.loads((ROOT/'assets/world_manifest.json').read_text(encoding='utf8'))
if not any(o.type=='LIGHT' and o.name.startswith('Room_Light') for o in scene.objects):
    for i,l in enumerate(manifest['lights']):
        ld=bpy.data.lights.new('Room_Light_'+str(i),'POINT');ld.energy=135;ld.color=l['color'];ld.shadow_soft_size=.25
        ob=bpy.data.objects.new(ld.name,ld);scene.collection.objects.link(ob);p=l['position'];ob.location=(p[0],-p[2],p[1])
views=[
 ('01_connected_world',(340,-425,365),(0,0,10),40),
 ('02_paris_street',(-130,106,6.5),(-109,134,7),31),
 ('03_paris_interior',(-138,131.6,1.92),(-149,138,1.35),21),
 ('04_rome',(135,33,13),(90,80,11),32),
 ('05_swiss_village',(-122,-130,6),(-89,-76,14),31),
 ('06_castle',(144,-142,43),(85,-68,31),34),
]
requested=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
for name,loc,target,lens in views:
    if requested and name not in requested:continue
    cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.lens=lens
    scene.render.filepath=str(ROOT/'previews'/(name+'.png'))
    print('RENDER '+name,flush=True);bpy.ops.render.render(write_still=True)
print('PREVIEWS_COMPLETE',flush=True)
