"""Read-only source geometry inventory and background CPU views."""
from pathlib import Path
import bpy,json,sys
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/'source/external/unicorn_sketchfab/author_source/UNICORN_GUNDAM_OBJ.obj'
OUT=ROOT/'previews/refined_unicorn';OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=str(SOURCE),use_split_objects=True,use_split_groups=False)
scene=bpy.context.scene;objects=[o for o in scene.objects if o.type=='MESH']
rows=[];all_points=[]
for o in objects:
    pts=[o.matrix_world@v.co for v in o.data.vertices];all_points+=pts
    o.data.calc_loop_triangles()
    rows.append({'name':o.name,'materials':[m.name if m else '' for m in o.data.materials],
                 'vertices':len(pts),'faces':len(o.data.polygons),'triangles':len(o.data.loop_triangles),
                 'bounds':[[min(v[a] for v in pts) for a in range(3)],[max(v[a] for v in pts) for a in range(3)]]})
lo=Vector([min(v[a] for v in all_points) for a in range(3)]);hi=Vector([max(v[a] for v in all_points) for a in range(3)])
report={'bounds':[list(lo),list(hi)],'triangles':sum(i['triangles'] for i in rows),'meshes':rows}
(OUT/'source_geometry.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('SOURCE_GEOMETRY',len(objects),report['triangles'],'BOUNDS',list(lo),list(hi),flush=True)
if '--render' not in sys.argv:sys.exit(0)
# Neutral material geometry reference; authored materials are reconstructed separately.
for mat in bpy.data.materials:
    mat.use_nodes=True;p=mat.node_tree.nodes.get('Principled BSDF')
    if p:
        for link in list(mat.node_tree.links):mat.node_tree.links.remove(link)
        p.inputs['Base Color'].default_value=(.62,.65,.69,1);p.inputs['Roughness'].default_value=.55
        p.inputs['Alpha'].default_value=1;p.inputs['Transmission Weight'].default_value=0;p.inputs['Metallic'].default_value=0
        mat.node_tree.links.new(p.outputs['BSDF'],mat.node_tree.nodes.get('Material Output').inputs['Surface'])
center=(lo+hi)/2;span=max(hi-lo)
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=12;scene.cycles.use_denoising=True
scene.render.threads_mode='FIXED';scene.render.threads=4
scene.world=bpy.data.worlds.new('AuditWorld');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.45
def aim(o,target):o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
for offset in [(-.8,-1,1.2),(1,.5,.8),(-.5,1,1)]:
    bpy.ops.object.light_add(type='AREA',location=center+Vector(offset)*span)
    o=bpy.context.object;o.data.energy=span*span*65;o.data.shape='DISK';o.data.size=span*.65;aim(o,center)
bpy.ops.object.camera_add();cam=bpy.context.object;scene.camera=cam;cam.data.type='ORTHO';cam.data.ortho_scale=span*1.08;cam.data.clip_end=span*10
scene.render.resolution_x=840;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.view_settings.view_transform='AgX'
for name,direction in [('source_minus_y',(0,-2,.12)),('source_plus_y',(0,2,.12))]:
    cam.location=center+Vector(direction)*span;aim(cam,center)
    scene.render.filepath=str(OUT/(name+'_clay.png'));bpy.ops.render.render(write_still=True)
