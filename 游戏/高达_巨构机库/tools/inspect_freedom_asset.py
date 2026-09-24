"""Immutable-source geometry audit and CPU preview, never opens a window."""
import bpy, json, sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'previews/refined_freedom'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'source/external/strike_freedom_sketchfab/strike_freedom_gundam_2k.glb'))
scene=bpy.context.scene
objects=[o for o in scene.objects if o.type=='MESH']
records=[];all_points=[]
for o in objects:
    pts=[o.matrix_world@v.co for v in o.data.vertices];all_points+=pts
    o.data.calc_loop_triangles()
    rec={'name':o.name,'materials':[m.name if m else '' for m in o.data.materials], 'vertices':len(pts),'triangles':len(o.data.loop_triangles),
         'bounds':[[min(v[a] for v in pts) for a in range(3)],[max(v[a] for v in pts) for a in range(3)]]}
    records.append(rec)
lo=Vector([min(v[a] for v in all_points) for a in range(3)]);hi=Vector([max(v[a] for v in all_points) for a in range(3)])
(OUT/'source_geometry.json').write_text(json.dumps({'bounds':[list(lo),list(hi)],'meshes':records},indent=2),encoding='utf8')
print('SOURCE_BOUNDS',list(lo),list(hi),flush=True)
print('OBJECT_BOUNDS',json.dumps(records),flush=True)
if '--render' not in sys.argv:sys.exit(0)
center=(lo+hi)/2;span=max(hi-lo)
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8;scene.cycles.use_denoising=True
scene.render.threads_mode='FIXED';scene.render.threads=4
scene.world=bpy.data.worlds.new('AuditWorld');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.5
def aim(o,target):o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
for offset in [(-.8,-1,1.2),(1,.5,.8),(-.5,1,1)]:
    bpy.ops.object.light_add(type='AREA',location=center+Vector(offset)*span)
    o=bpy.context.object;o.data.energy=span*span*80;o.data.shape='DISK';o.data.size=span*.7;aim(o,center)
bpy.ops.object.camera_add();cam=bpy.context.object;scene.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=span*1.1;cam.data.clip_end=span*10
scene.render.resolution_x=800;scene.render.resolution_y=800;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
for name,direction in [('source_front',(0,-2,.15)),('source_back',(0,2,.15))]:
    cam.location=center+Vector(direction)*span;aim(cam,center)
    scene.render.filepath=str(OUT/(name+'_cpu.png'));bpy.ops.render.render(write_still=True)
